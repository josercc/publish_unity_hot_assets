import 'dart:async';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_auth_service.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server_service.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_browser_launcher.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/jenkins_workload_service.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';

class PackagingServerRow {
  PackagingServerRow({
    required this.server,
    this.workload = JenkinsWorkloadStatus.unknown,
  });

  final PackagingServer server;
  JenkinsWorkloadStatus workload;
}

class HomeController extends GetxController {
  /// 打包机列表（仅 active）
  final packagingRows = <PackagingServerRow>[].obs;

  final isLoadingServers = false.obs;

  /// 当前选中的打包机 id；null 表示未选，任务自动分配。
  String? get selectedServerId => packagingServers.selectedServerId.value;

  /// 单选切换：再次点击同一台取消选中。
  void togglePackagingServer(String serverId) {
    packagingServers.toggleSelectedServer(serverId);
  }

  /// 应用内浏览器打开 Jenkins，并自动填充账号密码。
  Future<void> openJenkinsInBrowser(PackagingServer server) async {
    try {
      await JenkinsBrowserLauncher.open(server);
    } catch (e) {
      SmartDialog.showToast('打开 Jenkins 失败: $e');
    }
  }

  /// Appwrite 会话检测定时任务
  Timer? _sessionCheckTimer;

  /// 打包机状态刷新
  Timer? _serversRefreshTimer;

  final _workloadService = JenkinsWorkloadService();
  bool _refreshingServers = false;

  @override
  void onInit() {
    super.onInit();
    _startSessionCheckTimer();
    refreshPackagingServers();
    _serversRefreshTimer =
        Timer.periodic(const Duration(minutes: 1), (_) {
      refreshPackagingServers();
    });
  }

  @override
  void onClose() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = null;
    _serversRefreshTimer?.cancel();
    _serversRefreshTimer = null;
    _workloadService.close();
    super.onClose();
  }

  /// 启动 Appwrite 会话检测定时任务
  void _startSessionCheckTimer() {
    _sessionCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkSessionValidity();
    });
  }

  /// 检查 Appwrite 会话是否仍然有效
  Future<void> _checkSessionValidity() async {
    final valid = await appwriteAuth.hasValidSession();
    if (!valid) {
      print('Appwrite 会话已过期，自动退出到登录页面');
      await logoutToLogin();
    }
  }

  /// 退出登录（结束 Appwrite 会话，保留本地用户名/密文密码）
  Future<void> logoutToLogin() async {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = null;
    _serversRefreshTimer?.cancel();
    _serversRefreshTimer = null;
    global.token = null;
    global.tokenExpireTime = null;
    global.jenkinsApi = null;
    packagingServers.clear();
    packagingRows.clear();
    await appwriteAuth.logout();
    Get.offAllNamed(Routes.LOGIN);
  }

  /// 从 Appwrite 拉取 active 打包机，再经 ntfy 查 Jenkins 工作状态。
  Future<void> refreshPackagingServers() async {
    if (_refreshingServers) return;
    _refreshingServers = true;
    if (packagingRows.isEmpty) {
      isLoadingServers.value = true;
    }
    try {
      final servers = await packagingServers.fetchActiveServers();
      final previous = {
        for (final row in packagingRows) row.server.id: row.workload,
      };

      // 列表只展示 active=true（fetchActiveServers 已过滤）
      final rows = servers
          .where((s) => s.active)
          .map(
            (s) => PackagingServerRow(
              server: s,
              workload: !s.online
                  ? JenkinsWorkloadStatus.offline
                  : (previous[s.id] ?? JenkinsWorkloadStatus.unknown),
            ),
          )
          .toList();
      packagingRows.assignAll(rows);

      // Jenkins 工作状态只查 online=true 的机器
      for (final row in rows) {
        if (!row.server.online) {
          row.workload = JenkinsWorkloadStatus.offline;
          packagingRows.refresh();
          continue;
        }
        final status = await _workloadService.queryStatus(row.server);
        row.workload = status;
        packagingRows.refresh();
      }
    } catch (e) {
      print('刷新打包机列表失败: $e');
    } finally {
      isLoadingServers.value = false;
      _refreshingServers = false;
    }
  }
}
