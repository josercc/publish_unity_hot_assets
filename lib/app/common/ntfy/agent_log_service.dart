import 'package:path/path.dart' as p;
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/appwrite_temp_download.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/ntfy_agent_client.dart';

/// 经 ntfy 下载打包机 ip_ntfy_agent 运行日志到本机。
class AgentLogService {
  AgentLogService({NtfyAgentClient? client})
      : _client = client ?? NtfyAgentClient();

  final NtfyAgentClient _client;

  void close() => _client.close();

  /// Agent 上传完整日志 → 本机下载 → deleteLog 清理。
  Future<String> downloadFullLog({
    required PackagingServer server,
    required String saveDirectory,
    AppwriteDownloadProgress? onProgress,
  }) async {
    final topic = _requireTopic(server);
    final buildId = 'agent:${DateTime.now().millisecondsSinceEpoch}';

    onProgress?.call(
      phase: 'uploading',
      message: '正在请求打包机上传 Agent 日志...',
      percent: 0,
    );

    final uploadRes = await _client.downloadAgentLog(
      topic: topic,
      buildId: buildId,
      tag: server.tag.isEmpty ? null : server.tag,
      onProgress: (event) {
        final percent = event.percent;
        // 小文件 Appwrite SDK 中途不回调，Agent 会先推 0% 再等到结束才到 100%。
        // 避免 UI 长时间显示「0.0%」像卡住。
        final showPercent = percent != null && percent > 0;
        onProgress?.call(
          phase: 'uploading',
          message: showPercent
              ? '[${percent.toStringAsFixed(1)}%] Agent 正在上传日志...'
              : 'Agent 正在上传日志到 Appwrite，请稍候...',
          percent: showPercent ? percent : null,
        );
      },
    );

    if (!uploadRes.ok) {
      throw StateError(uploadRes.error ?? '上传 Agent 日志失败');
    }

    final body = uploadRes.bodyAsMap();
    final downloadUrl = body['downloadUrl']?.toString() ?? '';
    final fileId = body['fileId']?.toString() ?? '';
    final returnedBuildId = body['buildId']?.toString() ?? buildId;
    final fileName = body['fileName']?.toString().trim().isNotEmpty == true
        ? body['fileName'].toString().trim()
        : 'agent_$buildId.log'.replaceAll(':', '_');
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
      label: 'Agent 日志',
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
        print('删除服务端 Agent 日志失败: ${deleteRes.error}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('删除服务端 Agent 日志异常: $e');
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
