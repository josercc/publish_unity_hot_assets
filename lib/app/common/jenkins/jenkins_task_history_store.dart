import 'dart:convert';

import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_historical_task.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地持久化 Jenkins 任务历史（SharedPreferences JSON 列表）。
class JenkinsTaskHistoryStore {
  JenkinsTaskHistoryStore._();
  static final JenkinsTaskHistoryStore instance = JenkinsTaskHistoryStore._();

  static const _prefsKey = 'jenkins_task_history_v1';
  static const _maxItems = 100;

  Future<List<JenkinsHistoricalTask>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => JenkinsHistoricalTask.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty && t.jobName.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      // ignore: avoid_print
      print('[TaskHistory] load failed: $e');
      return const [];
    }
  }

  Future<List<JenkinsHistoricalTask>> loadByJob(String jobName) async {
    final all = await loadAll();
    return all.where((t) => t.jobName == jobName).toList(growable: false);
  }

  Future<void> upsert(JenkinsHistoricalTask task) async {
    final all = List<JenkinsHistoricalTask>.from(await loadAll());
    final index = all.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      all[index] = task;
    } else {
      all.insert(0, task);
    }
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (all.length > _maxItems) {
      all.removeRange(_maxItems, all.length);
    }
    await _save(all);
  }

  Future<void> updateStatus({
    required String id,
    required JenkinsJobRunStatus status,
    String? message,
    int? queueId,
    int? buildNumber,
  }) async {
    final all = List<JenkinsHistoricalTask>.from(await loadAll());
    final index = all.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final prev = all[index];
    all[index] = prev.copyWith(
      status: status,
      message: message ?? prev.message,
      queueId: queueId ?? prev.queueId,
      buildNumber: buildNumber ?? prev.buildNumber,
      updatedAt: DateTime.now(),
    );
    await _save(all);
  }

  Future<void> remove(String id) async {
    final all = List<JenkinsHistoricalTask>.from(await loadAll());
    all.removeWhere((t) => t.id == id);
    await _save(all);
  }

  Future<void> clearJob(String jobName) async {
    final all = List<JenkinsHistoricalTask>.from(await loadAll());
    all.removeWhere((t) => t.jobName == jobName);
    await _save(all);
  }

  Future<void> _save(List<JenkinsHistoricalTask> tasks) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _prefsKey,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }
}
