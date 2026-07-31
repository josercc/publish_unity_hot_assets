/// Appwrite 服务配置（与公司其他桌面工具保持一致）
class AppwriteConfig {
  static const String endpoint = 'https://appwrite.winnermedical.com/v1';
  static const String projectId = '677f626b0012252b422e';

  /// 打包服务器所在数据库
  static const String databaseId = '6a6aaced00065290a69c';

  /// 打包服务器集合（字段：url / userName / password / active / tag / online）
  static const String packagingServersCollectionId = '6a6aacfb00024a65ba3d';

  /// 热更 zip Storage 桶（与 ip_ntfy_agent APPWRITE_BUCKET_ID 一致）
  static const String hotUpdateBucketId = '6a6b20d0002630974471';

  /// ntfy（与 ip_ntfy_agent 对齐，经 Agent 代理访问打包机 Jenkins）
  static const String ntfyBaseUrl = 'http://119.23.47.1:8385';
  static const String ntfyAuth = 'Bearer tk_6c0b3ec5cf01uyy46swg86330rqho';
}
