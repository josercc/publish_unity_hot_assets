import 'package:get/get.dart';

import '../controllers/unity_first_package_controller.dart';

class UnityFirstPackageBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UnityFirstPackageController>(
      () => UnityFirstPackageController(),
    );
  }
}
