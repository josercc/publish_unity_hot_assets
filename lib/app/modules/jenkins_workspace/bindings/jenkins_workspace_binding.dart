import 'package:get/get.dart';

import '../controllers/jenkins_workspace_controller.dart';

class JenkinsWorkspaceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JenkinsWorkspaceController>(
      () => JenkinsWorkspaceController(),
    );
  }
}
