import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/modules/login/controllers/login_controller.dart';

import '../controllers/jenkins_servers_controller.dart';

class JenkinsServersBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<LoginController>()) {
      Get.lazyPut<LoginController>(() => LoginController());
    }
    Get.lazyPut<JenkinsServersController>(() => JenkinsServersController());
  }
}
