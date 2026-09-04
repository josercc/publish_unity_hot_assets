import 'package:get/get.dart';

import '../controllers/flutter_patch_controller.dart';

class FlutterPatchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<FlutterPatchController>(() => FlutterPatchController());
  }
}
