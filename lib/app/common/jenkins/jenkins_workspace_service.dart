import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_auth_service.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_config.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_workspace_entry.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/ntfy_agent_client.dart';

/// 经 ntfy Agent 浏览 Jenkins workspace，并按 Agent 约定下载 apk。
class JenkinsWorkspaceService {
  JenkinsWorkspaceService({NtfyAgentClient? client})
      : _client = client ?? NtfyAgentClient();

  final NtfyAgentClient _client;

  /// crumb + 会话 Cookie 短时缓存（与 JobParams 触发构建同一套 Jenkins CSRF）。
  final _crumbCache = <String, _WsCachedCrumb>{};
  static const _crumbTtl = Duration(minutes: 5);

  void close() {
    _crumbCache.clear();
    _client.close();
  }

  /// 列出 [relativePath]（相对 job workspace 根，如 `HotUpdate/123/`）下的条目。
  ///
  /// 按 Agent 约定：代理 Jenkins `/job/.../ws/.../` 目录时，响应 body 为
  /// `{ files: [...], folders: [...], folderName: "..." }`（Agent 自动走 `*plain*`）。
  Future<List<JenkinsWorkspaceEntry>> listDirectory({
    required PackagingServer server,
    required String jobName,
    String relativePath = '',
  }) async {
    final topic = _requireTopic(server);
    final jenkinsBase = _jenkinsBase(server.url);
    final encodedJob = Uri.encodeComponent(jobName);
    final rel = _normalizeRelativePath(relativePath);
    final url = rel.isEmpty
        ? '$jenkinsBase/job/$encodedJob/ws/'
        : '$jenkinsBase/job/$encodedJob/ws/${_encodeWorkspacePath(rel)}/';

    final auth = _basicAuth(server.userName, server.password);
    final res = await _requestJenkins(
      topic: topic,
      serverUrl: server.url,
      method: 'GET',
      url: url,
      headers: {
        if (auth != null) 'Authorization': auth,
      },
      timeout: const Duration(seconds: 60),
    );

    if (!res.ok || (res.statusCode != null && res.statusCode! >= 400)) {
      throw StateError(
        '列出工作空间失败 status=${res.statusCode} error=${res.error}',
      );
    }

    if (res.bodyOmitted) {
      throw StateError(
        '列出工作空间失败：Agent 省略了响应体'
        '（omitReason=${res.omitReason ?? '?'}，可能路径指向了文件而非目录）',
      );
    }

    if (_useDirectJenkins) {
      return _entriesFromDirectWorkspaceHtml('${res.body}');
    }
    return _entriesFromAgentListing(res.bodyAsMap());
  }

  /// 清空 Job 整个工作目录，对应 Jenkins「Wipe Out Current Workspace」。
  ///
  /// 调用 `POST /job/{job}/doWipeOutWorkspace`（需 CSRF crumb）。
  Future<void> wipeOutWorkspace({
    required PackagingServer server,
    required String jobName,
  }) async {
    final topic = _requireTopic(server);
    final jenkinsBase = _jenkinsBase(server.url);
    final encodedJob = Uri.encodeComponent(jobName);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };

    final crumbHeaders = await _fetchCrumbHeaders(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
    );

    Future<NtfyProxyResponse> postWipe(Map<String, String> crumbs) {
      return _requestJenkins(
        topic: topic,
        serverUrl: server.url,
        method: 'POST',
        url: '$jenkinsBase/job/$encodedJob/doWipeOutWorkspace',
        headers: {
          ...headers,
          ...crumbs,
        },
        timeout: const Duration(seconds: 120),
      );
    }

    var res = await postWipe(crumbHeaders);
    if (res.statusCode == 403) {
      _invalidateCrumb(topic, jenkinsBase);
      final fresh = await _fetchCrumbHeaders(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
      );
      res = await postWipe(fresh);
    }

    final code = res.statusCode ?? 0;
    // Jenkins 成功多为 302 跳转到 workspace；跟随重定向后也可能是 200。
    final okStatus = code == 200 ||
        code == 201 ||
        code == 204 ||
        code == 302 ||
        code == 303 ||
        code == 307 ||
        code == 308;
    if (!res.ok || !okStatus) {
      throw StateError(
        '清理工作目录失败 job=$jobName status=$code error=${res.error}',
      );
    }
  }

  /// 将相对路径各段 encode，去掉首尾 `/`。
  String _encodeWorkspacePath(String relativePath) {
    return relativePath
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }

  /// 解析 Agent workspace 目录响应：`files` / `folders` / `folderName`。
  List<JenkinsWorkspaceEntry> _entriesFromAgentListing(
    Map<String, dynamic> body,
  ) {
    final files = _stringList(body['files']);
    final folders = _stringList(body['folders']);
    if (files.isEmpty &&
        folders.isEmpty &&
        body.isNotEmpty &&
        !body.containsKey('files') &&
        !body.containsKey('folders')) {
      throw StateError(
        '工作空间响应格式不正确（缺少 files/folders）: $body',
      );
    }

    final entries = <JenkinsWorkspaceEntry>[
      for (final name in folders)
        if (name.isNotEmpty)
          JenkinsWorkspaceEntry(
            name: name,
            href: '$name/',
            isDirectory: true,
          ),
      for (final name in files)
        if (name.isNotEmpty)
          JenkinsWorkspaceEntry(
            name: name,
            href: name,
            isDirectory: false,
          ),
    ];

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Agent `uploadApk` → 本机下载 Appwrite → `deleteApk`。
  ///
  /// [onProgress] 的 [phase] 为 `uploading` / `downloading` / `cleanup`。
  Future<String> downloadApk({
    required PackagingServer server,
    required String jobName,
    required String relativeFilePath,
    required String saveDirectory,
    required String buildId,
    void Function({
      required String phase,
      required String message,
      double? percent,
    })? onProgress,
  }) async {
    final topic = _requireTopic(server);
    final jenkinsBase = _jenkinsBase(server.url);
    final encodedJob = Uri.encodeComponent(jobName);
    final rel = _normalizeRelativePath(relativeFilePath);
    if (rel.isEmpty || !rel.toLowerCase().endsWith('.apk')) {
      throw ArgumentError('不是 apk 文件: $relativeFilePath');
    }

    final apkUrl =
        '$jenkinsBase/job/$encodedJob/ws/${_encodeWorkspacePath(rel)}';
    final fileName = p.basename(rel);
    final savePath = p.join(saveDirectory, fileName);

    if (_useDirectJenkins) {
      onProgress?.call(
        phase: 'downloading',
        message: '正在从 Jenkins 直接下载 APK...',
        percent: 0,
      );
      await _downloadDirectFromJenkins(
        url: apkUrl,
        savePath: savePath,
        authHeader: _basicAuth(server.userName, server.password),
        onProgress: onProgress,
      );
      onProgress?.call(
        phase: 'cleanup',
        message: '已保存到 $savePath',
        percent: 100,
      );
      return savePath;
    }

    onProgress?.call(
      phase: 'uploading',
      message: '正在请求打包机上传 APK 到 Appwrite...',
      percent: 0,
    );

    final uploadRes = await _client.uploadApk(
      topic: topic,
      path: apkUrl,
      buildId: buildId,
      tag: server.tag.isEmpty ? null : server.tag,
      fileName: fileName,
      onProgress: (event) {
        final percent = event.percent;
        final percentText =
            percent == null ? '' : '${percent.toStringAsFixed(1)}%';
        final sizeText = event.sizeUploaded == null
            ? ''
            : ' ${(event.sizeUploaded! / 1024 / 1024).toStringAsFixed(2)}MB';
        final chunkText =
            (event.chunksUploaded != null && event.chunksTotal != null)
                ? ' (${event.chunksUploaded}/${event.chunksTotal})'
                : '';
        onProgress?.call(
          phase: 'uploading',
          message: '[$percentText$sizeText$chunkText] Agent 正在上传 APK...',
          percent: percent,
        );
      },
      timeout: const Duration(minutes: 30),
    );

    if (!uploadRes.ok) {
      throw StateError('上传 APK 失败: ${uploadRes.error ?? '未知错误'}');
    }

    final body = uploadRes.bodyAsMap();
    final downloadUrl = body['downloadUrl']?.toString() ?? '';
    final fileId = body['fileId']?.toString() ?? '';
    if (downloadUrl.isEmpty && fileId.isEmpty) {
      throw StateError('上传成功但未返回 downloadUrl / fileId');
    }

    onProgress?.call(
      phase: 'downloading',
      message: '上传完成，开始下载到本地...',
      percent: 0,
    );

    await _downloadFromAppwrite(
      downloadUrl: downloadUrl,
      fileId: fileId,
      savePath: savePath,
      onProgress: onProgress,
    );

    onProgress?.call(
      phase: 'cleanup',
      message: '下载完成，正在清理服务端临时文件...',
      percent: 100,
    );

    try {
      final deleteRes = await _client.deleteApk(
        topic: topic,
        buildId: buildId,
        tag: server.tag.isEmpty ? null : server.tag,
      );
      if (!deleteRes.ok) {
        // ignore: avoid_print
        print('删除服务端 APK 失败: ${deleteRes.error}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('删除服务端 APK 异常: $e');
    }

    onProgress?.call(
      phase: 'cleanup',
      message: '已保存到 $savePath',
      percent: 100,
    );
    return savePath;
  }

  Future<void> _downloadFromAppwrite({
    required String downloadUrl,
    required String fileId,
    required String savePath,
    void Function({
      required String phase,
      required String message,
      double? percent,
    })? onProgress,
  }) async {
    // 优先走 dio（有 onReceiveProgress）；Storage SDK 一次读完全部字节无进度。
    // 对齐 metax：先 getFile 取 sizeOriginal 算百分比，进度回调节流。
    final url = downloadUrl.isNotEmpty
        ? downloadUrl
        : (fileId.isNotEmpty ? _appwriteFileDownloadUrl(fileId) : '');
    if (url.isEmpty) {
      throw StateError('无法下载：downloadUrl 与 fileId 均不可用');
    }

    final storage = Storage(appwriteAuth.client);
    int? sizeOriginal;
    if (fileId.isNotEmpty) {
      try {
        final fileInfo = await storage.getFile(
          bucketId: AppwriteConfig.hotUpdateBucketId,
          fileId: fileId,
        );
        if (fileInfo.sizeOriginal > 0) {
          sizeOriginal = fileInfo.sizeOriginal;
        }
      } catch (e) {
        // ignore: avoid_print
        print('获取 Appwrite 文件元数据失败，进度改用 Content-Length: $e');
      }
    }

    final headers = await appwriteAuth.storageDownloadHeaders(Uri.parse(url));

    try {
      DateTime? lastProgressAt;
      await global.dio.download(
        url,
        savePath,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          final knownTotal =
              (sizeOriginal != null && sizeOriginal > 0)
                  ? sizeOriginal
                  : (total > 0 ? total : 0);
          final isComplete =
              knownTotal > 0 ? received >= knownTotal : false;
          final now = DateTime.now();
          final shouldEmit = lastProgressAt == null ||
              now.difference(lastProgressAt!).inMilliseconds >= 200 ||
              isComplete;
          if (!shouldEmit) return;
          lastProgressAt = now;

          final receivedMb = (received / 1024 / 1024).toStringAsFixed(2);
          final totalText = knownTotal > 0
              ? ' / ${(knownTotal / 1024 / 1024).toStringAsFixed(2)}MB'
              : 'MB';
          final percent = knownTotal > 0
              ? (received / knownTotal * 100).clamp(0, 100).toDouble()
              : null;
          onProgress?.call(
            phase: 'downloading',
            message: '[$receivedMb$totalText] 正在下载 APK...',
            percent: percent,
          );
        },
      );
      return;
    } catch (e) {
      // ignore: avoid_print
      print('dio 下载失败，回退 Storage.getFileDownload: $e');
    }

    if (fileId.isEmpty) {
      throw StateError('下载失败且无法回退：缺少 fileId');
    }
    onProgress?.call(
      phase: 'downloading',
      message: '正在从 Appwrite Storage 下载...',
      percent: null,
    );
    final bytes = await storage.getFileDownload(
      bucketId: AppwriteConfig.hotUpdateBucketId,
      fileId: fileId,
    );
    await File(savePath).writeAsBytes(bytes, flush: true);
    onProgress?.call(
      phase: 'downloading',
      message: '下载完成 (${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB)',
      percent: 100,
    );
  }

  String _appwriteFileDownloadUrl(String fileId) {
    final base = AppwriteConfig.endpoint.replaceAll(RegExp(r'/+$'), '');
    return '$base/storage/buckets/${AppwriteConfig.hotUpdateBucketId}'
        '/files/$fileId/download?project=${AppwriteConfig.projectId}';
  }

  String _requireTopic(PackagingServer server) {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('无法从打包机 URL 解析 ntfy topic: ${server.url}');
    }
    return topic;
  }

  String _localJenkinsBase(String url) {
    final uri = Uri.tryParse(url.trim());
    final port = uri?.hasPort == true ? uri!.port : 8080;
    return 'http://127.0.0.1:$port';
  }

  bool get _useDirectJenkins => global.isIntranetJenkinsMode;

  String _jenkinsBase(String url) {
    if (_useDirectJenkins) {
      return url.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return _localJenkinsBase(url);
  }

  String? _basicAuth(String userName, String password) {
    final user = userName.trim();
    if (user.isEmpty) return null;
    return 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
  }

  /// 去掉首尾 `/`。
  String _normalizeRelativePath(String path) {
    var s = path.trim().replaceAll('\\', '/');
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String _crumbCacheKey(String topic, String jenkinsBase) =>
      '$topic|$jenkinsBase';

  void _invalidateCrumb(String topic, String jenkinsBase) {
    _crumbCache.remove(_crumbCacheKey(topic, jenkinsBase));
  }

  Future<Map<String, String>> _fetchCrumbHeaders({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
  }) async {
    final key = _crumbCacheKey(topic, jenkinsBase);
    final cached = _crumbCache[key];
    if (cached != null && !cached.isExpired) {
      return Map<String, String>.from(cached.headers);
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _requestJenkins(
          topic: topic,
          serverUrl: jenkinsBase,
          method: 'GET',
          url: '$jenkinsBase/crumbIssuer/api/json',
          headers: headers,
          timeout: const Duration(seconds: 90),
        );
        if (!res.ok || res.statusCode != 200) {
          lastError = StateError(
            'crumb HTTP status=${res.statusCode} error=${res.error}',
          );
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        final body = res.bodyAsMap();
        final field = body['crumbRequestField']?.toString() ?? '';
        final crumb = body['crumb']?.toString() ?? '';
        if (field.isEmpty || crumb.isEmpty) {
          lastError = StateError('crumb 响应缺少字段');
          break;
        }

        final out = <String, String>{field: crumb};
        final cookie = _extractCookie(res.headers);
        if (cookie != null && cookie.isNotEmpty) {
          out['Cookie'] = cookie;
        }
        _crumbCache[key] = _WsCachedCrumb(
          headers: out,
          fetchedAt: DateTime.now(),
        );
        return Map<String, String>.from(out);
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    throw StateError(
      '无法获取 Jenkins CSRF crumb，请稍后重试。原因: $lastError',
    );
  }

  String? _extractCookie(Map<String, String> headers) {
    String? raw;
    headers.forEach((key, value) {
      if (key.toLowerCase() == 'set-cookie') {
        raw = value;
      }
    });
    if (raw == null || raw!.isEmpty) return null;

    final pairs = <String>[];
    for (final part in raw!.split(',')) {
      final pair = part.split(';').first.trim();
      if (pair.contains('=') && !pair.toLowerCase().startsWith('expires=')) {
        pairs.add(pair);
      }
    }
    if (pairs.isEmpty) return null;
    return pairs.join('; ');
  }

  List<JenkinsWorkspaceEntry> _entriesFromDirectWorkspaceHtml(String html) {
    final entries = <JenkinsWorkspaceEntry>[];
    final matches = RegExp(
      r'<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>',
      caseSensitive: false,
    ).allMatches(html);
    for (final match in matches) {
      final href = match.group(1)?.trim() ?? '';
      final name = match.group(2)?.trim() ?? '';
      if (href.isEmpty || name.isEmpty) continue;
      if (name == '..' || href == '../') continue;
      final decodedHref = Uri.decodeFull(href);
      final decodedName = Uri.decodeFull(name);
      entries.add(
        JenkinsWorkspaceEntry(
          name: decodedName.replaceAll(RegExp(r'/$'), ''),
          href: decodedHref,
          isDirectory: decodedHref.endsWith('/'),
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<NtfyProxyResponse> _requestJenkins({
    required String topic,
    required String serverUrl,
    required String method,
    required String url,
    Map<String, String>? headers,
    Map<String, String>? params,
    Object? body,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!_useDirectJenkins) {
      return _client.proxyHttp(
        topic: topic,
        method: method,
        url: url,
        headers: headers,
        params: params,
        body: body,
        timeout: timeout,
      );
    }

    final res = await global.dio.request(
      url,
      data: body,
      queryParameters: params,
      options: Options(
        method: method,
        headers: headers,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    final responseHeaders = <String, String>{};
    res.headers.map.forEach((key, value) {
      if (value.isNotEmpty) {
        responseHeaders[key] = value.join(', ');
      }
    });
    return NtfyProxyResponse(
      requestId: null,
      ok: (res.statusCode ?? 500) < 400,
      statusCode: res.statusCode,
      body: res.data,
      error: (res.statusCode ?? 500) >= 400 ? '${res.data}' : null,
      headers: responseHeaders,
    );
  }

  Future<void> _downloadDirectFromJenkins({
    required String url,
    required String savePath,
    required String? authHeader,
    void Function({
      required String phase,
      required String message,
      double? percent,
    })? onProgress,
  }) async {
    await global.dio.download(
      url,
      savePath,
      options: Options(
        headers: {
          if (authHeader != null) 'Authorization': authHeader,
        },
      ),
      onReceiveProgress: (received, total) {
        final percent =
            total > 0 ? (received / total * 100).clamp(0, 100).toDouble() : null;
        final receivedMb = (received / 1024 / 1024).toStringAsFixed(2);
        final totalText = total > 0
            ? ' / ${(total / 1024 / 1024).toStringAsFixed(2)}MB'
            : 'MB';
        onProgress?.call(
          phase: 'downloading',
          message: '[$receivedMb$totalText] 正在下载 APK...',
          percent: percent,
        );
      },
    );
  }
}

class _WsCachedCrumb {
  final Map<String, String> headers;
  final DateTime fetchedAt;

  const _WsCachedCrumb({
    required this.headers,
    required this.fetchedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) >= JenkinsWorkspaceService._crumbTtl;
}
