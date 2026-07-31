import 'dart:convert';

import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/ntfy_agent_client.dart';

/// Jenkins 工作负载状态（用于打包中心列表色标）。
enum JenkinsWorkloadStatus {
  /// 尚未查询 / 查询中
  unknown,

  /// 离线（Appwrite online=false 或代理失败）
  offline,

  /// 没有任务 — 绿色
  idle,

  /// 有打包、没有等待 — 黄色
  building,

  /// 有打包并且等待中 — 红色
  buildingWithQueue,
}

extension JenkinsWorkloadStatusX on JenkinsWorkloadStatus {
  String get label {
    switch (this) {
      case JenkinsWorkloadStatus.unknown:
        return '查询中';
      case JenkinsWorkloadStatus.offline:
        return '离线';
      case JenkinsWorkloadStatus.idle:
        return '空闲';
      case JenkinsWorkloadStatus.building:
        return '打包中';
      case JenkinsWorkloadStatus.buildingWithQueue:
        return '打包中(有等待)';
    }
  }

  /// 越小越闲，用于选机排序。
  int get idleScore {
    switch (this) {
      case JenkinsWorkloadStatus.idle:
        return 0;
      case JenkinsWorkloadStatus.unknown:
        return 1;
      case JenkinsWorkloadStatus.building:
        return 2;
      case JenkinsWorkloadStatus.buildingWithQueue:
        return 3;
      case JenkinsWorkloadStatus.offline:
        return 100;
    }
  }
}

/// 经 ntfy Agent 查询 Jenkins 队列/执行器状态。
class JenkinsWorkloadService {
  JenkinsWorkloadService({NtfyAgentClient? client})
      : _client = client ?? NtfyAgentClient(),
        _ownsClient = client == null;

  final NtfyAgentClient _client;
  final bool _ownsClient;

  /// 查询单台打包机的 Jenkins 工作状态。
  Future<JenkinsWorkloadStatus> queryStatus(PackagingServer server) async {
    if (!server.online) {
      return JenkinsWorkloadStatus.offline;
    }

    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      return JenkinsWorkloadStatus.offline;
    }

    final jenkinsBase = _localJenkinsBase(server.url);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };

    try {
      // 串行查询，复用同一 topic 订阅，避免并行多路 SSE 丢包
      final busy = await _fetchBusyExecutors(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
      );
      final queued = await _fetchQueueCount(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
      );

      // 有打包 + 等待 → 红；有打包无等待 → 黄；无任务 → 绿
      if (busy > 0 && queued > 0) {
        return JenkinsWorkloadStatus.buildingWithQueue;
      }
      if (busy > 0) {
        return JenkinsWorkloadStatus.building;
      }
      if (queued > 0) {
        return JenkinsWorkloadStatus.buildingWithQueue;
      }
      return JenkinsWorkloadStatus.idle;
    } catch (e) {
      // ignore: avoid_print
      print('[JenkinsWorkload] ${server.displayName} query failed: $e');
      return JenkinsWorkloadStatus.offline;
    }
  }

  Future<int> _fetchBusyExecutors({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
  }) async {
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/computer/api/json',
      headers: headers,
      params: const {'tree': 'busyExecutors,totalExecutors'},
    );
    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      throw StateError(
        'computer api failed: ok=${res.ok} status=${res.statusCode} '
        'error=${res.error}',
      );
    }
    final body = _asMap(res.body);
    final busy = body['busyExecutors'];
    if (busy is num) return busy.toInt();
    return int.tryParse('$busy') ?? 0;
  }

  Future<int> _fetchQueueCount({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
  }) async {
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/queue/api/json',
      headers: headers,
      params: const {'tree': 'items[id]'},
    );
    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      throw StateError(
        'queue api failed: ok=${res.ok} status=${res.statusCode} '
        'error=${res.error}',
      );
    }
    final body = _asMap(res.body);
    final items = body['items'];
    if (items is List) return items.length;
    return 0;
  }

  /// Agent 跑在打包机本机，Jenkins 用 127.0.0.1 + 文档端口。
  String _localJenkinsBase(String url) {
    final uri = Uri.tryParse(url.trim());
    final port = uri?.hasPort == true ? uri!.port : 8080;
    return 'http://127.0.0.1:$port';
  }

  String? _basicAuth(String userName, String password) {
    final user = userName.trim();
    if (user.isEmpty) return null;
    final token = base64Encode(utf8.encode('$user:$password'));
    return 'Basic $token';
  }

  Map<String, dynamic> _asMap(dynamic body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    if (body is String && body.trim().isNotEmpty) {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
