import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_build_log_service.dart';

/// 选目录并下载 Jenkins 构建日志到本机。
Future<String?> downloadJenkinsBuildLogToDisk({
  required PackagingServer server,
  required String jobName,
  required int buildNumber,
  JenkinsBuildLogService? service,
  void Function(String message)? onMessage,
}) async {
  final dir = await pickLogSaveDirectory();
  if (dir == null) return null;

  final owned = service == null;
  final logService = service ?? JenkinsBuildLogService();
  try {
    return await logService.downloadFullLog(
      server: server,
      jobName: jobName,
      buildNumber: buildNumber,
      saveDirectory: dir,
      onProgress: ({
        required String phase,
        required String message,
        double? percent,
      }) {
        onMessage?.call(message);
      },
    );
  } finally {
    if (owned) logService.close();
  }
}

Future<String?> pickLogSaveDirectory() async {
  try {
    final dir = await getDirectoryPath(confirmButtonText: '选择保存目录');
    if (dir != null && dir.isNotEmpty) return dir;
    return null;
  } on PlatformException catch (e) {
    // ignore: avoid_print
    print('file_selector 不可用 ($e)，回退到系统下载目录');
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      Get.snackbar(
        '无法选择保存目录',
        '请完全退出应用后重新启动（勿用热重启），再试下载',
      );
      return null;
    }
    Get.snackbar('已使用下载目录', downloads.path);
    return downloads.path;
  }
}
