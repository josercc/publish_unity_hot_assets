import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';

/// 发现同配置进行中任务时弹框；返回 true 表示用户选择继续提交。
Future<bool> confirmContinueDespiteDuplicateJobs(
  List<JenkinsDuplicateActiveJob> duplicates,
) async {
  if (duplicates.isEmpty) return true;

  final lines = duplicates.map((e) => '· ${e.userMessage}').join('\n');
  final result = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('发现相同配置任务'),
      content: SingleChildScrollView(
        child: Text(
          '以下打包机已有相同配置的任务在进行：\n\n'
          '$lines\n\n'
          '是否仍要继续提交？',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Get.back(result: true),
          child: const Text('继续'),
        ),
      ],
    ),
    barrierDismissible: false,
  );
  return result == true;
}
