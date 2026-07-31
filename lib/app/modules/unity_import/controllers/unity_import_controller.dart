import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_controller_mixin.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';

class UnityImportController extends GetxController
    with JenkinsJobParamsControllerMixin {
  @override
  String get jenkinsJobName => JenkinsJobParamsService.jobUnityCache;

  @override
  void onInit() {
    super.onInit();
    loadJenkinsJobParams();
  }

  @override
  void onClose() {
    disposeJobParams();
    super.onClose();
  }
}
