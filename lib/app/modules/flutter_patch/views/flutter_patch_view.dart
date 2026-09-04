import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/widgets/jenkins_job_params_form.dart';

import '../controllers/flutter_patch_controller.dart';

class FlutterPatchView extends GetView<FlutterPatchController> {
  const FlutterPatchView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.stopJobRunPolling();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter热更'),
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
            title: 'publish_flutter_patch 参数',
          ),
        ),
      ),
    );
  }
}
