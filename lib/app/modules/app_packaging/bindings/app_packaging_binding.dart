import 'package:get/get.dart';

import '../controllers/app_packaging_controller.dart';

class AppPackagingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AppPackagingController>(() => AppPackagingController());
  }
}
