/// 客户端展示的 Jenkins 任务运行状态。
enum JenkinsJobRunStatus {
  idle,
  submitting,
  waiting,
  building,
  success,
  failure,
  aborted,
  error,
}

extension JenkinsJobRunStatusX on JenkinsJobRunStatus {
  String get label {
    switch (this) {
      case JenkinsJobRunStatus.idle:
        return '未执行';
      case JenkinsJobRunStatus.submitting:
        return '提交中';
      case JenkinsJobRunStatus.waiting:
        return '等待中';
      case JenkinsJobRunStatus.building:
        return '打包中';
      case JenkinsJobRunStatus.success:
        return '打包完成';
      case JenkinsJobRunStatus.failure:
        return '打包失败';
      case JenkinsJobRunStatus.aborted:
        return '打包取消';
      case JenkinsJobRunStatus.error:
        return '状态异常';
    }
  }

  bool get isTerminal {
    switch (this) {
      case JenkinsJobRunStatus.success:
      case JenkinsJobRunStatus.failure:
      case JenkinsJobRunStatus.aborted:
        return true;
      case JenkinsJobRunStatus.idle:
      case JenkinsJobRunStatus.submitting:
      case JenkinsJobRunStatus.waiting:
      case JenkinsJobRunStatus.building:
      case JenkinsJobRunStatus.error:
        return false;
    }
  }

  bool get isRunning =>
      this == JenkinsJobRunStatus.submitting ||
      this == JenkinsJobRunStatus.waiting ||
      this == JenkinsJobRunStatus.building;
}

/// 触发构建后的跟踪句柄（队列项 → 构建号）。
class JenkinsTriggeredBuild {
  final int? queueId;
  final int? buildNumber;

  const JenkinsTriggeredBuild({
    this.queueId,
    this.buildNumber,
  });
}

/// 一次状态查询结果。
class JenkinsJobRunSnapshot {
  final JenkinsJobRunStatus status;
  final int? queueId;
  final int? buildNumber;
  final String? message;

  const JenkinsJobRunSnapshot({
    required this.status,
    this.queueId,
    this.buildNumber,
    this.message,
  });
}
