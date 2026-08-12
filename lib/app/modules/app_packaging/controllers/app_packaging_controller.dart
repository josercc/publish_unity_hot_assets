import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_historical_task.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_controller_mixin.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_task_history_store.dart';

enum ProductionBatchItemStatus { pending, submitting, ok, fail }

class ProductionBatchItem {
  ProductionBatchItem({
    required this.id,
    required this.label,
    this.status = ProductionBatchItemStatus.pending,
    this.message = '',
  });

  final String id;
  final String label;
  ProductionBatchItemStatus status;
  String message;
}

class AppPackagingController extends GetxController
    with JenkinsJobParamsControllerMixin {
  static const androidChannels = [
    'Winner',
    'Tencent',
    'Huawei',
    'Xiaomi',
    'Oppo',
    'Meizu',
    'Vivo',
    'Honor',
    'Samsung',
  ];

  final _batchParamsService = JenkinsJobParamsService();
  final _historyStore = JenkinsTaskHistoryStore.instance;

  final buildNameController = TextEditingController();
  final customBuildNumberController = TextEditingController();
  final melosBranchController = TextEditingController(text: 'release');
  final unityBranchController = TextEditingController(text: 'release2.0.0');

  /// Flutter 分支（MELOS_BRANCH），默认 release。
  final melosBranch = 'release'.obs;

  /// Unity 分支（UNITY_BRANCH），默认 release2.0.0。
  final unityBranch = 'release2.0.0'.obs;

  final useCustomBuildNumber = false.obs;
  final includeIos = true.obs;
  final iosUseCache = true.obs;
  final winnerUseCache = true.obs;
  final selectedChannels = <String>{...androidChannels}.obs;
  final isBatchRunning = false.obs;
  final batchItems = <ProductionBatchItem>[].obs;
  final batchSummary = ''.obs;

  @override
  String get jenkinsJobName => JenkinsJobParamsService.jobWinnerAppBinary;

  @override
  void onInit() {
    super.onInit();
    loadJenkinsJobParams();
  }

  @override
  void onClose() {
    buildNameController.dispose();
    customBuildNumberController.dispose();
    melosBranchController.dispose();
    unityBranchController.dispose();
    _batchParamsService.close();
    disposeJobParams();
    super.onClose();
  }

  /// Jenkins 参数里的分支选项；无选项时返回空（界面改用输入框）。
  List<String> branchChoicesFor(String paramName) {
    final lower = paramName.toLowerCase();
    final param = jobParams.firstWhereOrNull(
      (p) => p.name.toLowerCase() == lower,
    );
    if (param == null || param.choices.isEmpty) return const [];
    return List<String>.from(param.choices);
  }

  void setMelosBranch(String value) {
    final v = value.trim().isEmpty ? 'release' : value.trim();
    melosBranch.value = v;
    if (melosBranchController.text != v) {
      melosBranchController.text = v;
    }
  }

  void setUnityBranch(String value) {
    final v = value.trim().isEmpty ? 'release2.0.0' : value.trim();
    unityBranch.value = v;
    if (unityBranchController.text != v) {
      unityBranchController.text = v;
    }
  }

  void toggleChannel(String channel, bool selected) {
    if (selected) {
      selectedChannels.add(channel);
    } else {
      selectedChannels.remove(channel);
    }
    selectedChannels.refresh();
  }

  void selectAllChannels() {
    selectedChannels
      ..clear()
      ..addAll(androidChannels);
    selectedChannels.refresh();
  }

  void clearAllChannels() {
    selectedChannels.clear();
    selectedChannels.refresh();
  }

  Future<void> refreshProductionServer() async {
    final server = await ensureTaskServer();
    if (server == null) {
      Get.snackbar('提示', '没有可用的打包机');
      return;
    }
    if (!server.online) {
      Get.snackbar('提示', '打包机离线: ${server.displayName}');
    }
  }

  @override
  Future<void> executeJenkinsJob() async {
    if (isBatchRunning.value) {
      Get.snackbar('提示', '一键生产打包进行中，请等待结束');
      return;
    }
    await super.executeJenkinsJob();
  }

  Future<void> executeProductionBatch() async {
    if (isBatchRunning.value) {
      Get.snackbar('提示', '一键生产打包进行中，请等待结束');
      return;
    }
    if (jobRunStatus.value.isRunning) {
      Get.snackbar('提示', '单次参数打包任务进行中，请等待结束');
      return;
    }

    final includeIosBuild = includeIos.value;
    final channels = androidChannels
        .where((c) => selectedChannels.contains(c))
        .toList(growable: false);
    if (!includeIosBuild && channels.isEmpty) {
      Get.snackbar('提示', '请至少选择 iOS 或一个 Android 渠道');
      return;
    }

    final buildName = buildNameController.text.trim();
    if (buildName.isEmpty) {
      Get.snackbar('提示', '请填写 BUILD_NAME');
      return;
    }

    if (useCustomBuildNumber.value) {
      final custom = customBuildNumberController.text.trim();
      if (custom.isEmpty) {
        Get.snackbar('提示', '自定义构建号不能为空');
        return;
      }
    }

    isBatchRunning.value = true;
    batchSummary.value = '正在分配打包机...';
    try {
      final server = await ensureTaskServer();
      if (server == null) {
        batchSummary.value = '没有可用的打包机';
        Get.snackbar('错误', batchSummary.value);
        return;
      }
      if (!server.online) {
        batchSummary.value = '打包机离线: ${server.displayName}';
        Get.snackbar('错误', batchSummary.value);
        return;
      }

      final melos = melosBranchController.text.trim().isEmpty
          ? 'release'
          : melosBranchController.text.trim();
      final unity = unityBranchController.text.trim().isEmpty
          ? 'release2.0.0'
          : unityBranchController.text.trim();
      melosBranch.value = melos;
      unityBranch.value = unity;
      final buildNumber = useCustomBuildNumber.value
          ? customBuildNumberController.text.trim()
          : '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

      final items = <ProductionBatchItem>[
        if (includeIosBuild)
          ProductionBatchItem(id: 'ios', label: 'iOS (Winner)'),
        for (final channel in channels)
          ProductionBatchItem(
            id: 'android_$channel',
            label: 'Android · $channel',
          ),
      ];
      batchItems.assignAll(items);
      batchSummary.value =
          'BUILD_NUMBER=$buildNumber · Flutter=$melos · Unity=$unity · '
          '共 ${items.length} 项 · ${server.displayName}';

      var okCount = 0;
      var failCount = 0;

      if (includeIosBuild) {
        final iosItem = batchItems.firstWhere((e) => e.id == 'ios');
        final ok = await _triggerOne(
          item: iosItem,
          parameters: _iosParams(
            buildName: buildName,
            buildNumber: buildNumber,
            melosBranch: melos,
            unityBranch: unity,
            useCache: iosUseCache.value,
            serverTag: server.tag,
          ),
          serverName: server.displayName,
          serverTag: server.tag,
          delayBefore: false,
        );
        if (ok) {
          okCount++;
        } else {
          failCount++;
        }
        // 与脚本一致：iOS 之后等待 5 秒再跑 Android
        if (channels.isNotEmpty) {
          batchSummary.value = 'iOS 已处理，等待 5 秒后开始 Android...';
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }

      for (var i = 0; i < channels.length; i++) {
        final channel = channels[i];
        final item = batchItems.firstWhere((e) => e.id == 'android_$channel');
        final useCache = channel == 'Winner' ? winnerUseCache.value : true;
        final ok = await _triggerOne(
          item: item,
          parameters: _androidParams(
            channel: channel,
            buildName: buildName,
            buildNumber: buildNumber,
            melosBranch: melos,
            unityBranch: unity,
            useCache: useCache,
            serverTag: server.tag,
          ),
          serverName: server.displayName,
          serverTag: server.tag,
          // 渠道之间间隔 2 秒；第一项不额外等待（iOS 后的 5 秒已处理）
          delayBefore: i > 0,
        );
        if (ok) {
          okCount++;
        } else {
          failCount++;
        }
      }

      batchSummary.value =
          '完成: 成功 $okCount / 失败 $failCount / 共 ${items.length} · BUILD_NUMBER=$buildNumber';
      Get.snackbar(
        failCount == 0 ? '生产打包已提交' : '生产打包部分失败',
        batchSummary.value,
      );
    } catch (e) {
      batchSummary.value = e.toString();
      Get.snackbar('执行失败', e.toString());
    } finally {
      isBatchRunning.value = false;
    }
  }

  Future<bool> _triggerOne({
    required ProductionBatchItem item,
    required Map<String, String> parameters,
    required String serverName,
    required String serverTag,
    required bool delayBefore,
  }) async {
    final server = selectedPackagingServer;
    if (server == null) {
      _updateBatchItem(
        item,
        status: ProductionBatchItemStatus.fail,
        message: '打包机丢失',
      );
      return false;
    }

    if (delayBefore) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    _updateBatchItem(
      item,
      status: ProductionBatchItemStatus.submitting,
      message: '正在提交...',
    );
    batchSummary.value = '正在提交 ${item.label}...';

    try {
      final triggered = await _batchParamsService.triggerBuild(
        jobName: jenkinsJobName,
        server: server,
        parameters: parameters,
      );
      final msg = triggered.queueId == null
          ? '已提交'
          : '已提交，队列 #${triggered.queueId}';
      _updateBatchItem(
        item,
        status: ProductionBatchItemStatus.ok,
        message: msg,
      );

      final now = DateTime.now();
      await _historyStore.upsert(
        JenkinsHistoricalTask(
          id:
              '${jenkinsJobName}_prod_${item.id}_${now.millisecondsSinceEpoch}',
          jobName: jenkinsJobName,
          serverName: serverName,
          serverTag: serverTag,
          parameters: Map<String, String>.from(parameters),
          status: JenkinsJobRunStatus.waiting,
          message: '一键生产 · ${item.label} · $msg',
          queueId: triggered.queueId,
          buildNumber: triggered.buildNumber,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return true;
    } catch (e) {
      _updateBatchItem(
        item,
        status: ProductionBatchItemStatus.fail,
        message: e.toString(),
      );
      final now = DateTime.now();
      try {
        await _historyStore.upsert(
          JenkinsHistoricalTask(
            id:
                '${jenkinsJobName}_prod_${item.id}_${now.millisecondsSinceEpoch}',
            jobName: jenkinsJobName,
            serverName: serverName,
            serverTag: serverTag,
            parameters: Map<String, String>.from(parameters),
            status: JenkinsJobRunStatus.error,
            message: '一键生产 · ${item.label} · $e',
            createdAt: now,
            updatedAt: now,
          ),
        );
      } catch (_) {}
      return false;
    }
  }

  void _updateBatchItem(
    ProductionBatchItem item, {
    required ProductionBatchItemStatus status,
    required String message,
  }) {
    item.status = status;
    item.message = message;
    batchItems.refresh();
  }

  Map<String, String> _iosParams({
    required String buildName,
    required String buildNumber,
    required String melosBranch,
    required String unityBranch,
    required bool useCache,
    required String serverTag,
  }) {
    return _withCommonExtras({
      'PLATFORM': 'ios',
      'MELOS_BRANCH': melosBranch,
      'UNITY_BRANCH': unityBranch,
      'BUILD_NAME': buildName,
      'FORCE_BUILD': 'true',
      'IS_UPLOAD': 'true',
      'SEND_LOG': 'false',
      'IS_STORE': 'true',
      'zealotChannel': 'Winner',
      'IS_USE_CACHE': useCache ? 'true' : 'false',
      'BUILD_NUMBER': buildNumber,
    }, serverTag: serverTag);
  }

  Map<String, String> _androidParams({
    required String channel,
    required String buildName,
    required String buildNumber,
    required String melosBranch,
    required String unityBranch,
    required bool useCache,
    required String serverTag,
  }) {
    return _withCommonExtras({
      'PLATFORM': 'android',
      'MELOS_BRANCH': melosBranch,
      'UNITY_BRANCH': unityBranch,
      'BUILD_NAME': buildName,
      'FORCE_BUILD': 'true',
      'IS_UPLOAD': channel == 'Winner' ? 'true' : 'false',
      'SEND_LOG': 'false',
      'IS_STORE': 'true',
      'zealotChannel': channel,
      'IS_USE_CACHE': useCache ? 'true' : 'false',
      'BUILD_NUMBER': buildNumber,
    }, serverTag: serverTag);
  }

  /// 附带打包机 tag；若 Job 定义含 uid 则自动补时间戳。
  Map<String, String> _withCommonExtras(
    Map<String, String> base, {
    required String serverTag,
  }) {
    final params = Map<String, String>.from(base);
    String? tagKey;
    String? uidKey;
    for (final p in jobParams) {
      final lower = p.name.toLowerCase();
      if (lower == 'tag') tagKey = p.name;
      if (lower == 'uid') uidKey = p.name;
    }
    if (tagKey != null && serverTag.trim().isNotEmpty) {
      params[tagKey] = serverTag;
    } else if (serverTag.trim().isNotEmpty) {
      params['tag'] = serverTag;
    }
    if (uidKey != null) {
      params[uidKey] = DateTime.now().millisecondsSinceEpoch.toString();
    }
    return params;
  }
}
