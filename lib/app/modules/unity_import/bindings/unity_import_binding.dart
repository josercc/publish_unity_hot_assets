import 'package:get/get.dart';

import '../controllers/unity_import_controller.dart';

class UnityImportBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UnityImportController>(() => UnityImportController());
  }
}
