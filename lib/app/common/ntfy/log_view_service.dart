import 'dart:convert';

import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/ntfy_agent_client.dart';

/// 一次分块结果（相对 Agent 临时目录只读快照）。
class LogViewChunk {
  const LogViewChunk({
    required this.sessionId,
    required this.text,
    required this.lineCount,
    required this.startOffset,
    required this.endOffset,
    required this.hasMore,
    required this.size,
  });

  final String sessionId;
  final String text;
  final int lineCount;
  final int startOffset;
  final int endOffset;
  final bool hasMore;
  final int size;

  List<String> get lines {
    if (text.isEmpty) return const [];
    return const LineSplitter().convert(text);
  }

  factory LogViewChunk.fromBody(Map<String, dynamic> body) {
    int asInt(dynamic v, [int fallback = 0]) {
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? fallback;
    }

    return LogViewChunk(
      sessionId: body['sessionId']?.toString() ?? '',
      text: body['text']?.toString() ?? '',
      lineCount: asInt(body['lineCount']),
      startOffset: asInt(body['startOffset']),
      endOffset: asInt(body['endOffset']),
      hasMore: body['hasMore'] == true,
      size: asInt(body['size']),
    );
  }
}

/// 经 ntfy 打开/分块/关闭 Agent 侧日志查看会话。
class LogViewService {
  LogViewService({NtfyAgentClient? client})
      : _client = client ?? NtfyAgentClient();

  final NtfyAgentClient _client;

  static const defaultChunkLines = 10;

  void close() => _client.close();

  Future<LogViewChunk> openAgentLog({
    required PackagingServer server,
    int lines = defaultChunkLines,
  }) async {
    final topic = _requireTopic(server);
    final res = await _client.openAgentLogView(topic: topic, lines: lines);
    if (!res.ok) {
      throw StateError(res.error ?? '打开 Agent 日志失败');
    }
    return LogViewChunk.fromBody(res.bodyAsMap());
  }

  Future<LogViewChunk> openBuildLog({
    required PackagingServer server,
    required String jobName,
    required String buildNumber,
    int lines = defaultChunkLines,
  }) async {
    final topic = _requireTopic(server);
    final res = await _client.openBuildLogView(
      topic: topic,
      jobName: jobName,
      buildNumber: buildNumber,
      lines: lines,
    );
    if (!res.ok) {
      throw StateError(res.error ?? '打开构建日志失败');
    }
    return LogViewChunk.fromBody(res.bodyAsMap());
  }

  Future<LogViewChunk> loadEarlier({
    required PackagingServer server,
    required String sessionId,
    required int beforeOffset,
    int lines = defaultChunkLines,
  }) async {
    final topic = _requireTopic(server);
    final res = await _client.getLogViewChunk(
      topic: topic,
      sessionId: sessionId,
      beforeOffset: beforeOffset,
      lines: lines,
    );
    if (!res.ok) {
      throw StateError(res.error ?? '加载更早日志失败');
    }
    return LogViewChunk.fromBody(res.bodyAsMap());
  }

  Future<void> closeSession({
    required PackagingServer server,
    required String sessionId,
  }) async {
    if (sessionId.isEmpty) return;
    final topic = _requireTopic(server);
    try {
      await _client.closeLogView(topic: topic, sessionId: sessionId);
    } catch (e) {
      // ignore: avoid_print
      print('closeLogView failed: $e');
    }
  }

  String _requireTopic(PackagingServer server) {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('打包机 URL 无效，无法推导 ntfy topic: ${server.url}');
    }
    return topic;
  }
}
