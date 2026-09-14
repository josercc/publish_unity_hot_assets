import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_config.dart';

/// 经 ntfy 调用 ip_ntfy_agent 的 HTTP 代理客户端。
///
/// 每个 topic 只维持一条订阅流，按 `requestId` 多路复用，避免并行开多条
/// SSE 导致 Dio/连接池收不到 Agent 回包。
class NtfyAgentClient {
  NtfyAgentClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final _sessions = <String, _NtfyTopicSession>{};
  bool _closed = false;

  /// 串行发布，避免短时间连发触发 ntfy 429。
  Future<void> _publishChain = Future<void>.value();
  DateTime? _lastPublishAt;

  /// 两次 publish 最小间隔（ntfy 默认限流较严）。
  static const _minPublishInterval = Duration(milliseconds: 350);
  static const _maxPublishRetries = 5;

  String get _base =>
      AppwriteConfig.ntfyBaseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _authHeaders {
    final auth = AppwriteConfig.ntfyAuth.trim();
    if (auth.isEmpty) return const {};
    return {'Authorization': auth};
  }

  _NtfyTopicSession _sessionFor(String topic) {
    return _sessions.putIfAbsent(
      topic,
      () => _NtfyTopicSession(
        baseUrl: _base,
        topic: topic,
        authHeaders: _authHeaders,
        publish: _publish,
      ),
    );
  }

  /// 预先订阅一组 topic，确保后续 publish 能收到各打包机 Agent 回包。
  Future<void> ensureTopicsListening(Iterable<String> topics) async {
    if (_closed) {
      throw StateError('NtfyAgentClient is closed');
    }
    final unique = <String>{};
    for (final raw in topics) {
      final topic = raw.trim();
      if (topic.isEmpty) continue;
      unique.add(topic);
    }
    for (final topic in unique) {
      await _sessionFor(topic).ensureListening();
    }
  }

  String _newRequestId(String topic) =>
      'req_${DateTime.now().microsecondsSinceEpoch}_${topic.hashCode.abs()}';

  /// 向 [topic] 发送代理 HTTP 请求，等待 Agent 回传的 `type=response`。
  Future<NtfyProxyResponse> proxyHttp({
    required String topic,
    required String method,
    required String url,
    Map<String, String>? headers,
    Map<String, String>? params,
    Object? body,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_closed) {
      throw StateError('NtfyAgentClient is closed');
    }

    final session = _sessionFor(topic);
    final requestId = _newRequestId(topic);
    final payload = <String, dynamic>{
      'requestId': requestId,
      'method': method.toUpperCase(),
      'url': url,
      if (headers != null && headers.isNotEmpty) 'headers': headers,
      if (params != null && params.isNotEmpty) 'params': params,
      if (body != null) 'body': body,
    };

    await session.ensureListening();
    return session.send(requestId: requestId, payload: payload, timeout: timeout);
  }

  /// 请求 Agent 将 Jenkins workspace 热更 zip 上传到 Appwrite。
  ///
  /// 上传中会收到 `type=progress`，经 [onProgress] 回传；结束为 `type=response`。
  Future<NtfyProxyResponse> uploadZip({
    required String topic,
    required String buildId,
    required String platform,
    String? tag,
    void Function(NtfyProgressEvent event)? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) {
    return sendAction(
      topic: topic,
      action: 'uploadZip',
      fields: {
        'buildId': buildId,
        'platform': platform,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  /// 请求 Agent 按 tag + buildId 删除 Appwrite 上的热更 zip。
  Future<NtfyProxyResponse> deleteZip({
    required String topic,
    required String buildId,
    String? tag,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return sendAction(
      topic: topic,
      action: 'deleteZip',
      fields: {
        'buildId': buildId,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
      timeout: timeout,
    );
  }

  /// 请求 Agent 将打包机本地路径或 Jenkins workspace URL 的 apk 上传到 Appwrite。
  ///
  /// 上传中会收到 `type=progress`，经 [onProgress] 回传；结束为 `type=response`。
  Future<NtfyProxyResponse> uploadApk({
    required String topic,
    required String path,
    required String buildId,
    String? tag,
    String? fileName,
    void Function(NtfyProgressEvent event)? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) {
    return sendAction(
      topic: topic,
      action: 'uploadApk',
      fields: {
        'path': path,
        'buildId': buildId,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        if (fileName != null && fileName.isNotEmpty) 'fileName': fileName,
      },
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  /// 请求 Agent 按 tag + buildId 删除 Appwrite 上的 apk（资源表键为 `apk:{buildId}`）。
  Future<NtfyProxyResponse> deleteApk({
    required String topic,
    required String buildId,
    String? tag,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return sendAction(
      topic: topic,
      action: 'deleteApk',
      fields: {
        'buildId': buildId,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
      timeout: timeout,
    );
  }

  /// 拉取打包机 Agent 运行日志末尾（`.run/agent.log`）。
  Future<NtfyProxyResponse> getAgentLog({
    required String topic,
    int lines = 500,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return sendAction(
      topic: topic,
      action: 'getAgentLog',
      fields: {
        'lines': lines,
      },
      timeout: timeout,
    );
  }

  /// 打开 Agent 日志在线查看会话（Agent 复制到临时快照并返回末尾一块）。
  Future<NtfyProxyResponse> openAgentLogView({
    required String topic,
    int lines = 10,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return sendAction(
      topic: topic,
      action: 'openAgentLogView',
      fields: {
        'lines': lines,
      },
      timeout: timeout,
    );
  }

  /// 打开 Jenkins 构建日志在线查看会话（先拉 consoleText 到临时快照）。
  Future<NtfyProxyResponse> openBuildLogView({
    required String topic,
    required String jobName,
    required String buildNumber,
    int lines = 10,
    Duration timeout = const Duration(minutes: 10),
  }) {
    return sendAction(
      topic: topic,
      action: 'openBuildLogView',
      fields: {
        'jobName': jobName,
        'buildNumber': buildNumber,
        'lines': lines,
      },
      timeout: timeout,
    );
  }

  /// 从只读快照继续向上取更早日志块。
  Future<NtfyProxyResponse> getLogViewChunk({
    required String topic,
    required String sessionId,
    required int beforeOffset,
    int lines = 10,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return sendAction(
      topic: topic,
      action: 'getLogViewChunk',
      fields: {
        'sessionId': sessionId,
        'beforeOffset': beforeOffset,
        'lines': lines,
      },
      timeout: timeout,
    );
  }

  /// 关闭日志查看会话并删除临时快照。
  Future<NtfyProxyResponse> closeLogView({
    required String topic,
    required String sessionId,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return sendAction(
      topic: topic,
      action: 'closeLogView',
      fields: {
        'sessionId': sessionId,
      },
      timeout: timeout,
    );
  }

  /// 请求 Agent 将完整 agent.log 上传 Appwrite，回传 downloadUrl。
  Future<NtfyProxyResponse> downloadAgentLog({
    required String topic,
    String? buildId,
    String? tag,
    void Function(NtfyProgressEvent event)? onProgress,
    Duration timeout = const Duration(minutes: 10),
  }) {
    return sendAction(
      topic: topic,
      action: 'downloadAgentLog',
      fields: {
        if (buildId != null && buildId.isNotEmpty) 'buildId': buildId,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  /// 请求 Agent 拉取 Jenkins consoleText 并上传 Appwrite。
  Future<NtfyProxyResponse> downloadBuildLog({
    required String topic,
    required String jobName,
    required String buildNumber,
    String? tag,
    void Function(NtfyProgressEvent event)? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) {
    return sendAction(
      topic: topic,
      action: 'downloadBuildLog',
      fields: {
        'jobName': jobName,
        'buildNumber': buildNumber,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  /// 删除临时日志资源（Agent / 构建日志下载产生）。
  Future<NtfyProxyResponse> deleteLog({
    required String topic,
    required String buildId,
    String? tag,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return sendAction(
      topic: topic,
      action: 'deleteLog',
      fields: {
        'buildId': buildId,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
      timeout: timeout,
    );
  }

  /// 向 [topic] 发送带 `action` 的 Agent 请求（uploadZip / deleteZip 等）。
  Future<NtfyProxyResponse> sendAction({
    required String topic,
    required String action,
    Map<String, dynamic> fields = const {},
    void Function(NtfyProgressEvent event)? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    if (_closed) {
      throw StateError('NtfyAgentClient is closed');
    }

    final session = _sessionFor(topic);
    final requestId = _newRequestId(topic);
    final payload = <String, dynamic>{
      'action': action,
      'requestId': requestId,
      ...fields,
    };

    await session.ensureListening();
    return session.send(
      requestId: requestId,
      payload: payload,
      timeout: timeout,
      onProgress: onProgress,
    );
  }

  Future<void> _publish(String topic, Map<String, dynamic> payload) {
    // 排队串行，保证间隔与 429 重试不会交错打爆限流
    final done = _publishChain.then((_) => _publishThrottled(topic, payload));
    _publishChain = done.catchError((_) {});
    return done;
  }

  Future<void> _publishThrottled(
    String topic,
    Map<String, dynamic> payload,
  ) async {
    final last = _lastPublishAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < _minPublishInterval) {
        await Future<void>.delayed(_minPublishInterval - elapsed);
      }
    }

    Object? lastError;
    for (var attempt = 0; attempt < _maxPublishRetries; attempt++) {
      try {
        await _dio.post(
          '$_base/$topic',
          data: jsonEncode(payload),
          options: Options(
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/json; charset=utf-8',
            },
            // 发布是短请求，避免被长连接 receiveTimeout 影响
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        );
        _lastPublishAt = DateTime.now();
        return;
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode;
        if (code != 429 && code != 503) rethrow;

        final retryAfter = _retryAfterDuration(e.response?.headers);
        final backoff = Duration(
          milliseconds: 500 * (1 << attempt.clamp(0, 4)),
        );
        final wait = retryAfter != null && retryAfter > backoff
            ? retryAfter
            : backoff;
        // ignore: avoid_print
        print(
          '[ntfy] publish $code topic=$topic '
          'attempt=${attempt + 1}/$_maxPublishRetries wait=${wait.inMilliseconds}ms',
        );
        await Future<void>.delayed(wait);
      }
    }
    throw lastError ??
        StateError('ntfy publish failed after $_maxPublishRetries retries');
  }

  Duration? _retryAfterDuration(Headers? headers) {
    if (headers == null) return null;
    final raw = headers.value('retry-after');
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    try {
      final date = HttpDate.parse(raw);
      final delta = date.difference(DateTime.now());
      if (delta.isNegative) return Duration.zero;
      return delta;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _closed = true;
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
    _dio.close(force: true);
  }
}

typedef _PublishFn = Future<void> Function(
  String topic,
  Map<String, dynamic> payload,
);

class _NtfyTopicSession {
  _NtfyTopicSession({
    required this.baseUrl,
    required this.topic,
    required this.authHeaders,
    required this.publish,
  });

  final String baseUrl;
  final String topic;
  final Map<String, String> authHeaders;
  final _PublishFn publish;

  final _pending = <String, Completer<NtfyProxyResponse>>{};
  final _progressHandlers = <String, void Function(NtfyProgressEvent event)>{};
  /// 已收到过 progress 的 requestId（用于忽略 zip/apk 多 Agent 抢跑失败响应）。
  final _seenProgress = <String>{};
  /// zip/apk 在 progress 后收到的失败包（超时后用于给出真实错误而非笼统 timeout）。
  final _deferredErrors = <String, Map<String, dynamic>>{};
  final _http = HttpClient();

  StreamSubscription<String>? _subscription;
  Completer<void>? _ready;
  bool _closed = false;
  bool _connecting = false;
  var _buffer = '';

  Future<void> ensureListening() async {
    if (_closed) throw StateError('ntfy session closed: $topic');
    if (_subscription != null && _ready?.isCompleted == true) return;
    if (_connecting) {
      final ready = _ready;
      if (ready != null) await ready.future;
      return;
    }
    await _connect();
  }

  Future<void> _connect() async {
    _connecting = true;
    final ready = Completer<void>();
    _ready = ready;
    try {
      await _tearDownStream();

      final uri = Uri.parse('$baseUrl/$topic/json');
      final request = await _http.getUrl(uri);
      authHeaders.forEach(request.headers.set);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/x-ndjson, application/json',
      );

      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw HttpException(
          'ntfy subscribe failed (${response.statusCode}): $body',
          uri: uri,
        );
      }

      _buffer = '';
      _subscription = response.transform(utf8.decoder).listen(
            _onChunk,
            onError: (Object e, StackTrace st) {
              // ignore: avoid_print
              print('[ntfy] stream error $topic: $e');
              _failAll(e);
              _scheduleReconnect();
            },
            onDone: () {
              // ignore: avoid_print
              print('[ntfy] stream done $topic; reconnecting');
              _scheduleReconnect();
            },
            cancelOnError: true,
          );

      // open 事件或短延迟后视为订阅就绪
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!ready.isCompleted) ready.complete();
        }),
      );

      // ignore: avoid_print
      print('[ntfy] subscribed: $topic');
      await ready.future;
    } catch (e) {
      if (!ready.isCompleted) ready.completeError(e);
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  void _onChunk(String chunk) {
    _buffer += chunk;
    final lines = _buffer.split('\n');
    _buffer = lines.removeLast();
    for (final line in lines) {
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final event = jsonDecode(trimmed);
      if (event is! Map) return;
      final eventType = event['event']?.toString();

      if (eventType == 'open') {
        if (_ready != null && !_ready!.isCompleted) {
          _ready!.complete();
        }
        return;
      }
      if (eventType != null && eventType != 'message') return;

      final rawMessage = event['message'];
      if (rawMessage == null) return;

      Map<String, dynamic>? map;
      if (rawMessage is Map) {
        map = Map<String, dynamic>.from(rawMessage);
      } else {
        final text = rawMessage.toString();
        if (text.isEmpty) return;
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }
      if (map == null) return;

      final type = map['type']?.toString();
      final requestId = map['requestId']?.toString();
      if (requestId == null || requestId.isEmpty) return;

      if (type == 'progress') {
        _seenProgress.add(requestId);
        // 仍在推进进度，说明另一台 Agent 可能在干活，清掉暂存失败。
        _deferredErrors.remove(requestId);
        final handler = _progressHandlers[requestId];
        if (handler != null) {
          handler(NtfyProgressEvent.fromJson(map));
        }
        return;
      }
      if (type != 'response') return;

      // 同 topic 若残留旧 Agent，zip/apk 会先回失败；新 Agent 已在上传并推
      // progress。仅对这两类 action 暂存失败、继续等成功包。
      // downloadAgentLog / downloadBuildLog 只有一台 Agent，失败必须立刻抛出，
      // 否则会一直停在 0%「正在上传」直到超时。
      if (map['ok'] != true && _seenProgress.contains(requestId)) {
        final action = map['action']?.toString() ?? '';
        if (action == 'uploadZip' || action == 'uploadApk') {
          _deferredErrors[requestId] = Map<String, dynamic>.from(map);
          // ignore: avoid_print
          print(
            '[ntfy] defer error after progress requestId=$requestId '
            'action=$action error=${map['error']}',
          );
          return;
        }
      }

      _progressHandlers.remove(requestId);
      _seenProgress.remove(requestId);
      _deferredErrors.remove(requestId);
      final completer = _pending.remove(requestId);
      if (completer == null || completer.isCompleted) return;
      completer.complete(NtfyProxyResponse.fromJson(map));
    } catch (e) {
      // ignore: avoid_print
      print('[ntfy] parse line failed: $e line=$trimmed');
    }
  }

  Future<NtfyProxyResponse> send({
    required String requestId,
    required Map<String, dynamic> payload,
    required Duration timeout,
    void Function(NtfyProgressEvent event)? onProgress,
  }) async {
    final completer = Completer<NtfyProxyResponse>();
    _pending[requestId] = completer;
    if (onProgress != null) {
      _progressHandlers[requestId] = onProgress;
    }

    try {
      await publish(topic, payload);
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pending.remove(requestId);
          _progressHandlers.remove(requestId);
          _seenProgress.remove(requestId);
          final deferred = _deferredErrors.remove(requestId);
          if (deferred != null) {
            return NtfyProxyResponse.fromJson(deferred);
          }
          throw TimeoutException(
            'ntfy proxy timeout for $requestId (topic=$topic)',
            timeout,
          );
        },
      );
    } catch (e) {
      _pending.remove(requestId);
      _progressHandlers.remove(requestId);
      _seenProgress.remove(requestId);
      _deferredErrors.remove(requestId);
      rethrow;
    }
  }

  void _failAll(Object error) {
    final pending = Map<String, Completer<NtfyProxyResponse>>.from(_pending);
    _pending.clear();
    _progressHandlers.clear();
    _seenProgress.clear();
    _deferredErrors.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  void _scheduleReconnect() {
    _subscription = null;
    if (_closed || _pending.isEmpty) {
      _ready = null;
      return;
    }
    // 有未完成请求时自动重连，便于继续收包
    unawaited(() async {
      try {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_closed || _pending.isEmpty) return;
        await _connect();
      } catch (e) {
        // ignore: avoid_print
        print('[ntfy] reconnect failed $topic: $e');
      }
    }());
  }

  Future<void> _tearDownStream() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void close() {
    _closed = true;
    _failAll(StateError('ntfy session closed: $topic'));
    unawaited(_tearDownStream());
    _http.close(force: true);
  }
}

class NtfyProgressEvent {
  final String? requestId;
  final String? action;
  final String? phase;
  final double? percent;
  final int? sizeUploaded;
  final int? chunksUploaded;
  final int? chunksTotal;

  const NtfyProgressEvent({
    this.requestId,
    this.action,
    this.phase,
    this.percent,
    this.sizeUploaded,
    this.chunksUploaded,
    this.chunksTotal,
  });

  factory NtfyProgressEvent.fromJson(Map<String, dynamic> json) {
    double? percent;
    final rawPercent = json['percent'];
    if (rawPercent is num) {
      percent = rawPercent.toDouble();
    } else if (rawPercent != null) {
      percent = double.tryParse('$rawPercent');
    }

    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v == null) return null;
      return int.tryParse('$v');
    }

    return NtfyProgressEvent(
      requestId: json['requestId']?.toString(),
      action: json['action']?.toString(),
      phase: json['phase']?.toString(),
      percent: percent,
      sizeUploaded: asInt(json['sizeUploaded']),
      chunksUploaded: asInt(json['chunksUploaded']),
      chunksTotal: asInt(json['chunksTotal']),
    );
  }
}

class NtfyProxyResponse {
  final String? requestId;
  final String? action;
  final bool ok;
  final int? statusCode;
  final dynamic body;
  final String? error;
  final Map<String, String> headers;

  /// Agent 因文件/体积过大省略 body 时为 true。
  final bool bodyOmitted;
  final String? omitReason;
  final String? fileName;
  final String? folderName;
  final String? contentType;
  final int? contentLength;

  const NtfyProxyResponse({
    required this.requestId,
    required this.ok,
    this.action,
    this.statusCode,
    this.body,
    this.error,
    this.headers = const {},
    this.bodyOmitted = false,
    this.omitReason,
    this.fileName,
    this.folderName,
    this.contentType,
    this.contentLength,
  });

  factory NtfyProxyResponse.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (value is List && value.isNotEmpty) {
          headers['$key'] = value.map((e) => '$e').join(', ');
        } else if (value != null) {
          headers['$key'] = '$value';
        }
      });
    }

    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v == null) return null;
      return int.tryParse('$v');
    }

    return NtfyProxyResponse(
      requestId: json['requestId']?.toString(),
      action: json['action']?.toString(),
      ok: json['ok'] == true,
      statusCode: json['statusCode'] is int
          ? json['statusCode'] as int
          : int.tryParse('${json['statusCode'] ?? ''}'),
      body: json['body'],
      error: json['error']?.toString(),
      headers: headers,
      bodyOmitted: json['bodyOmitted'] == true,
      omitReason: json['omitReason']?.toString(),
      fileName: json['fileName']?.toString(),
      folderName: json['folderName']?.toString(),
      contentType: json['contentType']?.toString(),
      contentLength: asInt(json['contentLength']),
    );
  }

  Map<String, dynamic> bodyAsMap() {
    if (body is Map<String, dynamic>) return body as Map<String, dynamic>;
    if (body is Map) return Map<String, dynamic>.from(body as Map);
    if (body is String && body.toString().trim().isNotEmpty) {
      final decoded = jsonDecode(body as String);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }
}
