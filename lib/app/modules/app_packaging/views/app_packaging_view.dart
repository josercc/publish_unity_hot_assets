import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/widgets/jenkins_job_params_form.dart';

import '../controllers/app_packaging_controller.dart';

class AppPackagingView extends GetView<AppPackagingController> {
  const AppPackagingView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.stopJobRunPolling();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('App 打包'),
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
            title: 'build_winner_app_binary_2.0 参数',
          ),
        ),
      ),
    );
  }
}
