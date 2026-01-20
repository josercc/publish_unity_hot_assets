import 'package:get/get.dart';

import '../controllers/jenkins_servers_controller.dart';

class JenkinsServersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JenkinsServersController>(() => JenkinsServersController());
  }
}


