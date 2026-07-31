import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_controller_mixin.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';

class AppPackagingController extends GetxController
    with JenkinsJobParamsControllerMixin {
  @override
  String get jenkinsJobName => JenkinsJobParamsService.jobWinnerAppBinary;

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
