import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/release_choice_tag.dart';

/// 选中生产 release 时二次确认；返回 true 表示继续提交。
Future<bool> confirmProdReleaseBeforeSubmit({
  required List<String> prodParamLines,
}) async {
  if (prodParamLines.isEmpty) return true;

  final lines = prodParamLines.map((e) => '· $e').join('\n');
  final result = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('⚠️ 生产版本打包确认'),
      content: SingleChildScrollView(
        child: Text(
          '当前选中了生产（prod）热更版本：\n\n'
          '$lines\n\n'
          '打出的包会对应线上正式包。请确认分支与参数无误后再继续。',
          style: const TextStyle(height: 1.4),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Get.back(result: true),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          child: const Text('确认打生产包'),
        ),
      ],
    ),
    barrierDismissible: false,
  );
  return result == true;
}

/// 从参数 Map 里找出带【生产】前缀的项，供确认文案使用。
List<String> collectProdReleaseParamLines(Map<String, String> params) {
  final lines = <String>[];
  for (final entry in params.entries) {
    if (!ReleaseChoiceTag.isProd(entry.value)) continue;
    final version = ReleaseChoiceTag.strip(entry.value);
    lines.add('${entry.key}: $version');
  }
  return lines;
}
