import 'package:get/get.dart';

import '../controllers/unity_hot_update_controller.dart';

class UnityHotUpdateBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UnityHotUpdateController>(
      () => UnityHotUpdateController(),
    );
  }
}
