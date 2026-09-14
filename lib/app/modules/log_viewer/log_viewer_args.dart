import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';

enum LogViewerKind { agent, build }

/// 打开在线日志页时传入的参数。
class LogViewerArgs {
  const LogViewerArgs({
    required this.server,
    required this.kind,
    this.jobName,
    this.buildNumber,
    this.title,
  });

  final PackagingServer server;
  final LogViewerKind kind;
  final String? jobName;
  final String? buildNumber;
  final String? title;

  String get resolvedTitle {
    final custom = title?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    if (kind == LogViewerKind.agent) {
      return 'Agent 日志 · ${server.displayName}';
    }
    final job = jobName?.trim() ?? '';
    final build = buildNumber?.trim() ?? '';
    if (job.isNotEmpty && build.isNotEmpty) {
      return '$job #$build · ${server.displayName}';
    }
    return '构建日志 · ${server.displayName}';
  }
}
