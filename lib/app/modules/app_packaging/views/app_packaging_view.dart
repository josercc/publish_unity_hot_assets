import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/widgets/jenkins_job_params_form.dart';
import 'package:publish_unity_hot_assets/app/modules/app_packaging/views/production_batch_packaging_panel.dart';

import '../controllers/app_packaging_controller.dart';

class AppPackagingView extends GetView<AppPackagingController> {
  const AppPackagingView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: PopScope(
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
            bottom: const TabBar(
              tabs: [
                Tab(text: '单次参数打包'),
                Tab(text: '一键生产打包'),
              ],
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TabBarView(
              children: [
                JenkinsJobParamsForm(
                  controller: controller,
                  title: 'build_winner_app_binary_2.0 参数',
                ),
                ProductionBatchPackagingPanel(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
