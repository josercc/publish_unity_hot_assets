import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/modules/update/controllers/update_controller.dart';

class UpdateBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => UpdateController());
  }
}
