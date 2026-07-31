import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/widgets/jenkins_job_params_form.dart';

import '../controllers/unity_import_controller.dart';

class UnityImportView extends GetView<UnityImportController> {
  const UnityImportView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.stopJobRunPolling();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Unity导包'),
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
            title: 'build_unity_cache 参数',
          ),
        ),
      ),
    );
  }
}
