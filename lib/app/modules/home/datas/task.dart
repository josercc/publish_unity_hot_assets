import 'package:get/get.dart';

/// 发布热更资源任务
abstract class Task<T> {
  /// 名称
  final String name;

  /// 当前进度显示的文案
  final progressText = '等待中...'.obs;

  /// 任务状态
  final status = TaskStatus.fromCode(TaskStatusCode.waiting, '等待中......').obs;

  Task({required this.name});

  /// 执行任务
  Future<T> execute();
}

enum TaskStatusCode {
  waiting,
  error,
  processing,
  success,
}

/// 任务状态
class TaskStatus {
  final TaskStatusCode code;
  final String title;
  const TaskStatus(this.code, this.title);

  factory TaskStatus.fromCode(TaskStatusCode code, String title) {
    return TaskStatus(code, title);
  }
}
