import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/widgets/jenkins_job_params_form.dart';

import '../controllers/unity_first_package_controller.dart';

class UnityFirstPackageView extends GetView<UnityFirstPackageController> {
  const UnityFirstPackageView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.stopJobRunPolling();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Unity首包'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '刷新当前参数',
              onPressed: controller.loadJenkinsJobParams,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: JenkinsJobParamsForm(
            controller: controller,
            title: 'build_unity_first_package 参数',
          ),
        ),
      ),
    );
  }
}
