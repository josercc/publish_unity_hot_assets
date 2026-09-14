import 'package:path/path.dart' as p;
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/appwrite_temp_download.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/ntfy_agent_client.dart';

/// 经 Agent 将 Jenkins 构建日志上传 Appwrite 后下载到本机（与 APK 旁路一致）。
class JenkinsBuildLogService {
  JenkinsBuildLogService({NtfyAgentClient? client})
      : _client = client ?? NtfyAgentClient();

  final NtfyAgentClient _client;

  void close() => _client.close();

  /// Agent 拉取 consoleText → Appwrite → 本机保存 → deleteLog。
  Future<String> downloadFullLog({
    required PackagingServer server,
    required String jobName,
    required int buildNumber,
    required String saveDirectory,
    AppwriteDownloadProgress? onProgress,
  }) async {
    final topic = _requireTopic(server);
    final storageBuildId = 'log:$jobName:$buildNumber';

    onProgress?.call(
      phase: 'uploading',
      message: '正在请求打包机上传构建日志...',
      percent: 0,
    );

    final uploadRes = await _client.downloadBuildLog(
      topic: topic,
      jobName: jobName,
      buildNumber: '$buildNumber',
      tag: server.tag.isEmpty ? null : server.tag,
      onProgress: (event) {
        final percent = event.percent;
        final showPercent = percent != null && percent > 0;
        onProgress?.call(
          phase: 'uploading',
          message: showPercent
              ? '[${percent.toStringAsFixed(1)}%] Agent 正在上传构建日志...'
              : 'Agent 正在上传构建日志到 Appwrite，请稍候...',
          percent: showPercent ? percent : null,
        );
      },
    );

    if (!uploadRes.ok) {
      throw StateError(uploadRes.error ?? '上传构建日志失败');
    }

    final body = uploadRes.bodyAsMap();
    final downloadUrl = body['downloadUrl']?.toString() ?? '';
    final fileId = body['fileId']?.toString() ?? '';
    final returnedBuildId = body['buildId']?.toString() ?? storageBuildId;
    final fileName = body['fileName']?.toString().trim().isNotEmpty == true
        ? body['fileName'].toString().trim()
        : '${jobName}_$buildNumber.log';
    final savePath = p.join(saveDirectory, fileName);

    onProgress?.call(
      phase: 'downloading',
      message: '上传完成，开始下载到本地...',
      percent: 0,
    );

    await downloadAppwriteTempFile(
      downloadUrl: downloadUrl,
      fileId: fileId,
      savePath: savePath,
      label: '构建日志',
      onProgress: onProgress,
    );

    onProgress?.call(
      phase: 'cleanup',
      message: '下载完成，正在清理服务端临时文件...',
      percent: 100,
    );

    try {
      final deleteRes = await _client.deleteLog(
        topic: topic,
        buildId: returnedBuildId,
        tag: server.tag.isEmpty ? null : server.tag,
      );
      if (!deleteRes.ok) {
        // ignore: avoid_print
        print('删除服务端构建日志失败: ${deleteRes.error}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('删除服务端构建日志异常: $e');
    }

    onProgress?.call(
      phase: 'cleanup',
      message: '已保存到 $savePath',
      percent: 100,
    );
    return savePath;
  }

  String _requireTopic(PackagingServer server) {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('打包机 URL 无效，无法推导 ntfy topic: ${server.url}');
    }
    return topic;
  }
}
