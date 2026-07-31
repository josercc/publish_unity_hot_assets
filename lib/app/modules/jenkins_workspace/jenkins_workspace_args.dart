import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';

/// 打开 Jenkins 工作空间浏览页时传入的参数。
class JenkinsWorkspaceArgs {
  final PackagingServer server;
  final String jobName;
  /// 相对 workspace 根的初始路径，如 `HotUpdate/123/` 或空。
  final String initialRelativePath;
  final int? buildNumber;

  const JenkinsWorkspaceArgs({
    required this.server,
    required this.jobName,
    this.initialRelativePath = '',
    this.buildNumber,
  });
}
