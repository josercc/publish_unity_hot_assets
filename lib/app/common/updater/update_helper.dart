import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/modules/update/controllers/update_controller.dart';

/// 更新助手类，用于在应用启动时自动检查更新
class UpdateHelper {
  /// 在应用启动时检查更新
  /// [showLoading] 是否显示加载动画（默认显示，让用户知道正在检查）
  static void checkUpdateOnStartup({bool showLoading = true}) {
    // 延迟检查，避免影响应用启动速度
    Future.delayed(const Duration(seconds: 3), () {
      final controller = Get.put(UpdateController());
      controller.checkForUpdate(showLoading: showLoading);
    });
  }

  /// 手动检查更新（显示加载动画）
  static void checkUpdateManually() {
    final controller = Get.put(UpdateController());
    controller.checkForUpdate(forceCheck: true, showLoading: true);
  }
}
