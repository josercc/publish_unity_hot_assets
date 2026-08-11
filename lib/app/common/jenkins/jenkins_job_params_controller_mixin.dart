import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server_service.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_duplicate_confirm.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_historical_task.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_parameter.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_task_history_store.dart';
import 'package:publish_unity_hot_assets/app/modules/jenkins_workspace/jenkins_workspace_args.dart';
import 'package:publish_unity_hot_assets/app/modules/task_history/jenkins_task_history_args.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';

/// 加载并持有 Jenkins Job 参数表单状态。
mixin JenkinsJobParamsControllerMixin on GetxController {
  final jobParams = <JenkinsJobParameter>[].obs;
  final jobParamValues = <String, dynamic>{}.obs;
  final isLoadingJobParams = false.obs;
  final jobParamsError = RxnString();
  final selectedPackagingServerName = ''.obs;
  final refreshingParamNames = <String>{}.obs;

  final jobRunStatus = JenkinsJobRunStatus.idle.obs;
  final jobRunMessage = ''.obs;
  final jobRunBuildNumber = RxnInt();
  final jobRunQueueId = RxnInt();

  final _textControllers = <String, TextEditingController>{};
  final _choiceFilterControllers = <String, TextEditingController>{};
  final _choiceDisplayControllers = <String, TextEditingController>{};
  final _paramsService = JenkinsJobParamsService();
  final _historyStore = JenkinsTaskHistoryStore.instance;
  PackagingServer? _selectedServer;
  var _refreshSeq = 0;
  Timer? _runPollTimer;
  var _runPollSeq = 0;
  String? _activeHistoryId;
  Map<String, String>? _pendingRetryParams;

  /// 对应 Jenkins Job 名。
  String get jenkinsJobName;

  /// 当前选中的打包机（加载参数 / 选机后可用）。
  PackagingServer? get selectedPackagingServer => _selectedServer;

  TextEditingController textControllerFor(String name, String initial) {
    return _textControllers.putIfAbsent(
      name,
      () => TextEditingController(text: initial),
    );
  }

  TextEditingController choiceFilterControllerFor(String name) {
    return _choiceFilterControllers.putIfAbsent(
      name,
      () => TextEditingController(),
    );
  }

  TextEditingController choiceDisplayControllerFor(String name, String initial) {
    return _choiceDisplayControllers.putIfAbsent(
      name,
      () => TextEditingController(text: initial),
    );
  }

  /// 按筛选关键字匹配选项，并把上方展示值设为第一个匹配项。
  void filterChoiceAndSelectFirst(String name, String query) {
    final param = jobParams.firstWhereOrNull((p) => p.name == name);
    if (param == null || param.choices.isEmpty) return;

    final q = query.trim().toLowerCase();
    final matched = q.isEmpty
        ? param.choices
        : param.choices
            .where((c) => c.toLowerCase().contains(q))
            .toList();
    if (matched.isEmpty) return;

    final first = matched.first;
    jobParamValues[name] = first;
    jobParamValues.refresh();
    final display = choiceDisplayControllerFor(name, first);
    if (display.text != first) {
      display.text = first;
    }
    _refreshDependentActiveChoices(changedParam: name);
  }

  String _formatServerLabel(PackagingServer server, {required bool manual}) {
    final tag = server.tag.isEmpty ? 'unknown' : server.tag;
    final mode = manual ? '指定' : '自动';
    return '$mode · ${server.displayName} ($tag)';
  }

  void _applyResolvedServer(PackagingServer? server) {
    final manual = packagingServers.selectedServer != null;
    _selectedServer = server;
    selectedPackagingServerName.value = server == null
        ? ''
        : _formatServerLabel(server, manual: manual);
  }

  /// 未选中 → 自动分配；已选中 → 走指定机器。
  Future<PackagingServer?> ensureTaskServer() async {
    final server = await _paramsService.resolveTaskServer();
    _applyResolvedServer(server);
    return server;
  }

  Future<void> loadJenkinsJobParams() async {
    isLoadingJobParams.value = true;
    jobParamsError.value = null;
    try {
      final server = await ensureTaskServer();
      final params = await _paramsService.fetchJobParameters(
        jobName: jenkinsJobName,
        server: server,
      );

      for (final c in _textControllers.values) {
        c.dispose();
      }
      _textControllers.clear();
      for (final c in _choiceFilterControllers.values) {
        c.dispose();
      }
      _choiceFilterControllers.clear();
      for (final c in _choiceDisplayControllers.values) {
        c.dispose();
      }
      _choiceDisplayControllers.clear();

      final values = <String, dynamic>{};
      for (final p in params) {
        values[p.name] = p.initialValue;
        // tag 由打包机文档决定，不展示给用户改
        if (p.name.toLowerCase() == 'tag' &&
            server != null &&
            server.tag.isNotEmpty) {
          values[p.name] = server.tag;
        }
        if (p.widgetType == JenkinsParamWidgetType.text ||
            p.widgetType == JenkinsParamWidgetType.password ||
            p.widgetType == JenkinsParamWidgetType.multiLine) {
          textControllerFor(p.name, '${values[p.name] ?? ''}');
        } else if (p.widgetType == JenkinsParamWidgetType.choice &&
            p.choices.isNotEmpty) {
          choiceDisplayControllerFor(p.name, '${values[p.name] ?? ''}');
          choiceFilterControllerFor(p.name);
        }
      }
      jobParams.assignAll(params);
      jobParamValues.assignAll(values);

      final pending = _pendingRetryParams;
      if (pending != null && pending.isNotEmpty) {
        _pendingRetryParams = null;
        await applyJobParamValues(pending);
      }
    } catch (e) {
      jobParams.clear();
      jobParamValues.clear();
      jobParamsError.value = e.toString();
      // ignore: avoid_print
      print('[JobParams] load $jenkinsJobName failed: $e');
    } finally {
      isLoadingJobParams.value = false;
    }
  }

  void setJobParamValue(String name, dynamic value) {
    jobParamValues[name] = value;
    jobParamValues.refresh();
    final display = _choiceDisplayControllers[name];
    if (display != null && display.text != '$value') {
      display.text = '$value';
    }
    _refreshDependentActiveChoices(changedParam: name);
  }

  /// 将历史任务参数填回表单（跳过 tag / UID，保留当前打包机 tag）。
  Future<void> applyJobParamValues(Map<String, String> values) async {
    if (jobParams.isEmpty || values.isEmpty) {
      _pendingRetryParams = Map<String, String>.from(values);
      return;
    }

    // 先按定义顺序写入，便于 Active Choices 依赖链刷新。
    for (final p in jobParams) {
      final lower = p.name.toLowerCase();
      if (lower == 'tag' || lower == 'uid') continue;

      String? matched;
      for (final e in values.entries) {
        if (e.key.toLowerCase() == lower) {
          matched = e.value;
          break;
        }
      }
      if (matched == null) continue;

      if (p.widgetType == JenkinsParamWidgetType.boolean) {
        jobParamValues[p.name] = matched.toLowerCase() == 'true';
        jobParamValues.refresh();
        await _refreshDependentActiveChoices(changedParam: p.name);
      } else if (p.widgetType == JenkinsParamWidgetType.text ||
          p.widgetType == JenkinsParamWidgetType.password ||
          p.widgetType == JenkinsParamWidgetType.multiLine) {
        final ctrl = textControllerFor(p.name, matched);
        if (ctrl.text != matched) ctrl.text = matched;
        jobParamValues[p.name] = matched;
        jobParamValues.refresh();
        await _refreshDependentActiveChoices(changedParam: p.name);
      } else {
        jobParamValues[p.name] = matched;
        jobParamValues.refresh();
        final display = _choiceDisplayControllers[p.name];
        if (display != null && display.text != matched) {
          display.text = matched;
        }
        await _refreshDependentActiveChoices(changedParam: p.name);
      }
    }
  }

  /// 打开当前 Job 的历史任务列表；若用户点「重试」则回填参数。
  Future<void> openTaskHistory() async {
    final server = _selectedServer ?? await ensureTaskServer();
    if (server == null) {
      Get.snackbar('无法打开', '没有可用的打包机');
      return;
    }
    final result = await Get.toNamed(
      Routes.TASK_HISTORY,
      arguments: JenkinsTaskHistoryArgs(
        jobName: jenkinsJobName,
        server: server,
      ),
    );
    if (result is! Map) return;
    final params = <String, String>{};
    for (final e in result.entries) {
      params['${e.key}'] = '${e.value}';
    }
    if (params.isEmpty) return;
    await applyJobParamValues(params);
    Get.snackbar('已填充', '历史任务参数已填入表单，可直接执行');
  }

  /// 当被引用参数变化时，重新用 Groovy getChoices 刷新 Reactive 选项。
  Future<void> _refreshDependentActiveChoices({
    required String changedParam,
  }) async {
    final server = _selectedServer;
    if (server == null) return;

    final dependents = jobParams
        .where(
          (p) =>
              p.isActiveChoices &&
              p.referencedParameters.contains(changedParam),
        )
        .toList();
    if (dependents.isEmpty) return;

    final seq = ++_refreshSeq;
    for (final param in dependents) {
      refreshingParamNames.add(param.name);
      refreshingParamNames.refresh();
      try {
        final refs = <String, String>{};
        for (final ref in param.referencedParameters) {
          refs[ref] = '${jobParamValues[ref] ?? ''}';
        }
        final choices = await _paramsService.evaluateActiveChoiceChoices(
          jobName: jenkinsJobName,
          paramName: param.name,
          server: server,
          referencedValues: refs,
        );
        if (seq != _refreshSeq) return;

        final index = jobParams.indexWhere((p) => p.name == param.name);
        if (index < 0) continue;
        jobParams[index] = param.copyWith(choices: choices);
        jobParams.refresh();

        final current = '${jobParamValues[param.name] ?? ''}';
        if (choices.isNotEmpty && !choices.contains(current)) {
          final next = choices.first;
          jobParamValues[param.name] = next;
          jobParamValues.refresh();
          final display = _choiceDisplayControllers[param.name];
          if (display != null) {
            display.text = next;
          }
          final filter = _choiceFilterControllers[param.name];
          filter?.clear();
          await _refreshDependentActiveChoices(changedParam: param.name);
        }
      } catch (e) {
        // ignore: avoid_print
        print('[JobParams] refresh ${param.name} failed: $e');
      } finally {
        refreshingParamNames.remove(param.name);
        refreshingParamNames.refresh();
      }
    }
  }

  /// 提交构建时使用的参数 Map（字符串化）。
  Map<String, String> collectJobParamQuery() {
    final result = <String, String>{};
    for (final p in jobParams) {
      final raw = jobParamValues[p.name];
      if (p.widgetType == JenkinsParamWidgetType.text ||
          p.widgetType == JenkinsParamWidgetType.password ||
          p.widgetType == JenkinsParamWidgetType.multiLine) {
        result[p.name] = _textControllers[p.name]?.text ?? '${raw ?? ''}';
      } else if (p.widgetType == JenkinsParamWidgetType.boolean) {
        result[p.name] = (raw == true).toString();
      } else {
        result[p.name] = '${raw ?? ''}';
      }
    }
    return result;
  }

  /// 右上角「执行任务」：触发构建后立即查状态，再每 10 秒轮询。
  Future<void> executeJenkinsJob() async {
    if (jobRunStatus.value.isRunning) {
      Get.snackbar('提示', '任务正在进行中，请等待结束');
      return;
    }

    // 先切到「提交中」，避免 ensureTaskServer / 网络等待时按钮看起来没反应
    stopJobRunPolling();
    _activeHistoryId = null;
    jobRunStatus.value = JenkinsJobRunStatus.submitting;
    jobRunMessage.value = '正在分配打包机并提交构建...';
    jobRunBuildNumber.value = null;
    jobRunQueueId.value = null;

    try {
      // 未选中 → 自动分配；已选中 → 走指定机器
      final server = await ensureTaskServer();
      if (server == null) {
        jobRunStatus.value = JenkinsJobRunStatus.error;
        jobRunMessage.value = '没有可用的打包机，请先刷新参数';
        Get.snackbar('错误', jobRunMessage.value);
        return;
      }
      if (!server.online) {
        jobRunStatus.value = JenkinsJobRunStatus.error;
        jobRunMessage.value = '打包机离线: ${server.displayName}';
        Get.snackbar('错误', jobRunMessage.value);
        return;
      }

      final params = collectJobParamQuery();
      if (params.isEmpty && jobParams.isNotEmpty) {
        throw StateError('打包参数为空，请刷新参数后重试');
      }
      // UID 大小写不敏感：隐藏字段也要自动补全
      String? uidKey;
      for (final key in params.keys) {
        if (key.toLowerCase() == 'uid') {
          uidKey = key;
          break;
        }
      }
      uidKey ??= jobParams
          .map((p) => p.name)
          .cast<String?>()
          .firstWhere(
            (n) => n != null && n.toLowerCase() == 'uid',
            orElse: () => null,
          );
      if (uidKey != null &&
          (params[uidKey] == null || params[uidKey]!.trim().isEmpty)) {
        params[uidKey] = DateTime.now().millisecondsSinceEpoch.toString();
        jobParamValues[uidKey] = params[uidKey];
        final uidCtrl = _textControllers[uidKey];
        if (uidCtrl != null) uidCtrl.text = params[uidKey]!;
      }

      jobRunMessage.value = '正在检查各打包机是否有相同任务...';
      final duplicates = await _paramsService.findDuplicateActiveJobs(
        jobName: jenkinsJobName,
        parameters: params,
      );
      if (duplicates.isNotEmpty) {
        final tip = duplicates.map((e) => e.userMessage).join('\n');
        // ignore: avoid_print
        print('[JobParams] duplicate found, ask continue: $tip');
        jobRunMessage.value = '发现相同配置任务，等待确认...';
        final continueSubmit =
            await confirmContinueDespiteDuplicateJobs(duplicates);
        if (!continueSubmit) {
          jobRunStatus.value = JenkinsJobRunStatus.idle;
          jobRunMessage.value = '已取消提交（存在相同配置任务）';
          // ignore: avoid_print
          print('[JobParams] duplicate declined: $tip');
          return;
        }
      }

      jobRunMessage.value = '正在提交构建...';
      // ignore: avoid_print
      print(
        '[JobParams] execute $jenkinsJobName params=${params.keys.join(',')}',
      );

      final triggered = await _paramsService.triggerBuild(
        jobName: jenkinsJobName,
        server: server,
        parameters: params,
      );
      jobRunQueueId.value = triggered.queueId;
      jobRunBuildNumber.value = triggered.buildNumber;
      jobRunStatus.value = JenkinsJobRunStatus.waiting;
      jobRunMessage.value = triggered.queueId == null
          ? '已提交，等待队列信息...'
          : '已提交，队列 #${triggered.queueId}';

      await _recordHistoryAfterSubmit(
        server: server,
        parameters: params,
        status: JenkinsJobRunStatus.waiting,
        message: jobRunMessage.value,
        queueId: triggered.queueId,
        buildNumber: triggered.buildNumber,
      );

      await _pollJobRunOnce();
      if (!jobRunStatus.value.isTerminal) {
        _startRunPolling();
      }
    } catch (e) {
      jobRunStatus.value = JenkinsJobRunStatus.error;
      jobRunMessage.value = e.toString();
      // ignore: avoid_print
      print('[JobParams] execute $jenkinsJobName failed: $e');
      final server = _selectedServer;
      if (server != null && _activeHistoryId == null) {
        await _recordHistoryAfterSubmit(
          server: server,
          parameters: collectJobParamQuery(),
          status: JenkinsJobRunStatus.error,
          message: e.toString(),
        );
      } else if (_activeHistoryId != null) {
        await _syncActiveHistory();
      }
      Get.snackbar('执行失败', e.toString());
    }
  }

  Future<void> _recordHistoryAfterSubmit({
    required PackagingServer server,
    required Map<String, String> parameters,
    required JenkinsJobRunStatus status,
    required String message,
    int? queueId,
    int? buildNumber,
  }) async {
    final now = DateTime.now();
    final id =
        '${jenkinsJobName}_${now.millisecondsSinceEpoch}_${identityHashCode(this)}';
    _activeHistoryId = id;
    try {
      await _historyStore.upsert(
        JenkinsHistoricalTask(
          id: id,
          jobName: jenkinsJobName,
          serverName: server.displayName,
          serverTag: server.tag,
          parameters: Map<String, String>.from(parameters),
          status: status,
          message: message,
          queueId: queueId,
          buildNumber: buildNumber,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[JobParams] save history failed: $e');
    }
  }

  Future<void> _syncActiveHistory() async {
    final id = _activeHistoryId;
    if (id == null || id.isEmpty) return;
    try {
      await _historyStore.updateStatus(
        id: id,
        status: jobRunStatus.value,
        message: jobRunMessage.value,
        queueId: jobRunQueueId.value,
        buildNumber: jobRunBuildNumber.value,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[JobParams] update history failed: $e');
    }
  }

  void _startRunPolling() {
    stopJobRunPolling();
    final seq = ++_runPollSeq;
    _runPollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (seq != _runPollSeq) return;
      await _pollJobRunOnce();
      if (seq != _runPollSeq) return;
      if (jobRunStatus.value.isTerminal) {
        stopJobRunPolling();
      }
    });
  }

  /// 退出界面或主动停止时，取消状态轮询。
  void stopJobRunPolling() {
    _runPollTimer?.cancel();
    _runPollTimer = null;
    _runPollSeq++;
  }

  final isCancellingJobRun = false.obs;

  /// 取消当前排队中 / 打包中的 Jenkins 任务。
  Future<void> cancelJenkinsJob() async {
    final status = jobRunStatus.value;
    if (status != JenkinsJobRunStatus.waiting &&
        status != JenkinsJobRunStatus.building &&
        status != JenkinsJobRunStatus.submitting) {
      return;
    }
    if (isCancellingJobRun.value) return;

    final server = _selectedServer;
    final queueId = jobRunQueueId.value;
    final buildNumber = jobRunBuildNumber.value;

    // 尚未拿到队列/构建号：只停止本地轮询
    if (server == null || (queueId == null && buildNumber == null)) {
      stopJobRunPolling();
      jobRunStatus.value = JenkinsJobRunStatus.aborted;
      jobRunMessage.value = '已取消提交';
      await _syncActiveHistory();
      return;
    }

    isCancellingJobRun.value = true;
    try {
      jobRunMessage.value = buildNumber != null
          ? '正在停止构建 #$buildNumber...'
          : '正在取消队列 #$queueId...';
      await _paramsService.cancelJobRun(
        server: server,
        jobName: jenkinsJobName,
        queueId: queueId,
        buildNumber: buildNumber,
      );
      stopJobRunPolling();
      jobRunStatus.value = JenkinsJobRunStatus.aborted;
      jobRunMessage.value = buildNumber != null
          ? '已停止构建 #$buildNumber'
          : '已取消队列 #$queueId';
      await _syncActiveHistory();
      Get.snackbar('已取消', jobRunMessage.value);
    } catch (e) {
      Get.snackbar('取消失败', e.toString());
      // 失败后继续轮询真实状态
      await _pollJobRunOnce();
    } finally {
      isCancellingJobRun.value = false;
    }
  }

  /// 是否已有打包机，可打开 Jenkins 工作空间。
  bool get canOpenJenkinsWorkspace =>
      _selectedServer != null && _selectedServer!.url.trim().isNotEmpty;

  /// 相对 workspace 根的初始路径（热更 Job 有构建号时进产物目录）。
  String jenkinsWorkspaceInitialPath() {
    final buildNo = jobRunBuildNumber.value;
    if (buildNo != null &&
        jenkinsJobName == JenkinsJobParamsService.jobUnityHotAsset) {
      return 'HotUpdate/$buildNo/';
    }
    return '';
  }

  /// 打开应用内工作空间浏览页。
  void openJenkinsWorkspace() {
    final server = _selectedServer;
    if (server == null || server.url.trim().isEmpty) {
      Get.snackbar('提示', '请先刷新参数或执行任务以确定打包机');
      return;
    }
    Get.toNamed(
      Routes.JENKINS_WORKSPACE,
      arguments: JenkinsWorkspaceArgs(
        server: server,
        jobName: jenkinsJobName,
        initialRelativePath: jenkinsWorkspaceInitialPath(),
        buildNumber: jobRunBuildNumber.value,
      ),
    );
  }

  Future<void> _pollJobRunOnce() async {
    final server = _selectedServer;
    if (server == null) return;
    try {
      final snap = await _paramsService.queryRunStatus(
        jobName: jenkinsJobName,
        server: server,
        queueId: jobRunQueueId.value,
        buildNumber: jobRunBuildNumber.value,
      );
      jobRunStatus.value = snap.status;
      jobRunMessage.value = snap.message ?? snap.status.label;
      if (snap.queueId != null) jobRunQueueId.value = snap.queueId;
      if (snap.buildNumber != null) jobRunBuildNumber.value = snap.buildNumber;
      await _syncActiveHistory();
      // ignore: avoid_print
      print(
        '[JobParams] run status=${snap.status.label} '
        'build=#${snap.buildNumber} queue=#${snap.queueId} '
        'msg=${snap.message}',
      );
    } catch (e) {
      jobRunMessage.value = '状态查询失败: $e';
      // ignore: avoid_print
      print('[JobParams] poll failed: $e');
    }
  }

  /// 释放参数表单资源（由宿主 Controller 的 onClose 调用）。
  void disposeJobParams() {
    stopJobRunPolling();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _textControllers.clear();
    for (final c in _choiceFilterControllers.values) {
      c.dispose();
    }
    _choiceFilterControllers.clear();
    for (final c in _choiceDisplayControllers.values) {
      c.dispose();
    }
    _choiceDisplayControllers.clear();
    _paramsService.close();
  }
}
