import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';

/// 一次 Jenkins 任务提交的本地历史记录。
class JenkinsHistoricalTask {
  final String id;
  final String jobName;
  final String serverName;
  final String serverTag;
  final Map<String, String> parameters;
  final JenkinsJobRunStatus status;
  final String message;
  final int? queueId;
  final int? buildNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JenkinsHistoricalTask({
    required this.id,
    required this.jobName,
    required this.serverName,
    required this.serverTag,
    required this.parameters,
    required this.status,
    required this.message,
    this.queueId,
    this.buildNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  String get jobTitle => jobTitleFor(jobName);

  static String jobTitleFor(String jobName) {
    switch (jobName) {
      case JenkinsJobParamsService.jobUnityCache:
        return 'Unity导包';
      case JenkinsJobParamsService.jobUnityFirstPackage:
        return 'Unity首包';
      case JenkinsJobParamsService.jobUnityHotAsset:
        return 'Unity打热更';
      case JenkinsJobParamsService.jobFlutterPatch:
        return 'Flutter热更';
      case JenkinsJobParamsService.jobWinnerAppBinary:
        return 'App 打包';
      default:
        return jobName;
    }
  }

  /// 列表摘要：优先展示常用参数。
  String get summaryText {
    const preferred = [
      'Platform',
      'platform',
      'Branch',
      'branch',
      'Config',
      'config',
      'CHANNEL',
      'channel',
      'Version',
      'version',
    ];
    for (final key in preferred) {
      final value = parameters[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return '$key=$value';
      }
    }
    for (final entry in parameters.entries) {
      final k = entry.key.toLowerCase();
      if (k == 'tag' || k == 'uid') continue;
      final v = entry.value.trim();
      if (v.isNotEmpty) return '${entry.key}=$v';
    }
    return jobName;
  }

  JenkinsHistoricalTask copyWith({
    String? id,
    String? jobName,
    String? serverName,
    String? serverTag,
    Map<String, String>? parameters,
    JenkinsJobRunStatus? status,
    String? message,
    int? queueId,
    int? buildNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearQueueId = false,
    bool clearBuildNumber = false,
  }) {
    return JenkinsHistoricalTask(
      id: id ?? this.id,
      jobName: jobName ?? this.jobName,
      serverName: serverName ?? this.serverName,
      serverTag: serverTag ?? this.serverTag,
      parameters: parameters ?? this.parameters,
      status: status ?? this.status,
      message: message ?? this.message,
      queueId: clearQueueId ? null : (queueId ?? this.queueId),
      buildNumber: clearBuildNumber ? null : (buildNumber ?? this.buildNumber),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobName': jobName,
        'serverName': serverName,
        'serverTag': serverTag,
        'parameters': parameters,
        'status': status.name,
        'message': message,
        'queueId': queueId,
        'buildNumber': buildNumber,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory JenkinsHistoricalTask.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'];
    final params = <String, String>{};
    if (rawParams is Map) {
      for (final e in rawParams.entries) {
        params['${e.key}'] = '${e.value}';
      }
    }
    return JenkinsHistoricalTask(
      id: '${json['id'] ?? ''}',
      jobName: '${json['jobName'] ?? ''}',
      serverName: '${json['serverName'] ?? ''}',
      serverTag: '${json['serverTag'] ?? ''}',
      parameters: params,
      status: _statusFromName('${json['status'] ?? ''}'),
      message: '${json['message'] ?? ''}',
      queueId: _asInt(json['queueId']),
      buildNumber: _asInt(json['buildNumber']),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static JenkinsJobRunStatus _statusFromName(String name) {
    for (final s in JenkinsJobRunStatus.values) {
      if (s.name == name) return s;
    }
    return JenkinsJobRunStatus.error;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }
}
