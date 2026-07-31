import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';

/// 打开任务历史列表时传入的过滤条件。
class JenkinsTaskHistoryArgs {
  /// 为空则展示全部 Job；非空则只展示该 Job。
  final String? jobName;

  /// 从哪台打包机拉 Jenkins 构建历史；为空则无法查远程历史。
  final PackagingServer? server;

  const JenkinsTaskHistoryArgs({this.jobName, this.server});
}
