import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_workspace_entry.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_workspace_service.dart';
import 'package:publish_unity_hot_assets/app/modules/jenkins_workspace/jenkins_workspace_args.dart';

class JenkinsWorkspaceController extends GetxController {
  final _service = JenkinsWorkspaceService();

  JenkinsWorkspaceArgs? _args;
  JenkinsWorkspaceArgs get args => _args!;
  bool get hasArgs => _args != null;

  /// 相对 workspace 根的路径栈，如 `['HotUpdate/', '123/']` 拼成 `HotUpdate/123/`。
  final pathSegments = <String>[].obs;
  final entries = <JenkinsWorkspaceEntry>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  final isDownloading = false.obs;
  final downloadPhase = ''.obs;
  final downloadMessage = ''.obs;
  final downloadPercent = RxnDouble();

  final isWiping = false.obs;

  String get currentRelativePath => pathSegments.join();

  bool get isBusy =>
      isLoading.value || isDownloading.value || isWiping.value;

  @override
  void onInit() {
    super.onInit();
    final raw = Get.arguments;
    if (raw is! JenkinsWorkspaceArgs) {
      errorMessage.value = '缺少工作空间参数';
      return;
    }
    _args = raw;
    final initial = raw.initialRelativePath.trim().replaceAll('\\', '/');
    if (initial.isNotEmpty) {
      for (final part in initial.split('/')) {
        if (part.isEmpty) continue;
        pathSegments.add('$part/');
      }
    }
    loadCurrent();
  }

  @override
  void onClose() {
    _service.close();
    super.onClose();
  }

  Future<void> loadCurrent() async {
    if (!hasArgs) return;
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final list = await _service.listDirectory(
        server: args.server,
        jobName: args.jobName,
        relativePath: currentRelativePath,
      );
      entries.assignAll(list);
    } catch (e) {
      entries.clear();
      errorMessage.value = '$e';
    } finally {
      isLoading.value = false;
    }
  }

  void openEntry(JenkinsWorkspaceEntry entry) {
    if (!entry.isDirectory || isBusy) return;
    pathSegments.add(entry.href.endsWith('/') ? entry.href : '${entry.href}/');
    loadCurrent();
  }

  void goUp() {
    if (pathSegments.isEmpty || isBusy) return;
    pathSegments.removeLast();
    loadCurrent();
  }

  void goToRoot() {
    if (pathSegments.isEmpty || isBusy) return;
    pathSegments.clear();
    loadCurrent();
  }

  /// 截断到第 [index] 段（含），再刷新。
  void goToSegment(int index) {
    if (isBusy) return;
    if (index < 0) {
      goToRoot();
      return;
    }
    if (index >= pathSegments.length - 1) return;
    pathSegments.value = pathSegments.sublist(0, index + 1);
    loadCurrent();
  }

  /// 调用 Jenkins `doWipeOutWorkspace`，清空当前 Job 整个工作目录。
  Future<void> wipeOutWorkspace() async {
    if (!hasArgs || isBusy) return;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('清理工作目录'),
        content: Text(
          '将清空 Job「${args.jobName}」在 Jenkins 上的整个工作目录，'
          '与 Jenkins「Wipe Out Current Workspace」相同，此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    isWiping.value = true;
    errorMessage.value = null;
    try {
      await _service.wipeOutWorkspace(
        server: args.server,
        jobName: args.jobName,
      );
      pathSegments.clear();
      Get.snackbar('清理完成', '已清空 Job「${args.jobName}」的工作目录');
      await loadCurrent();
    } catch (e) {
      Get.snackbar('清理失败', '$e');
    } finally {
      isWiping.value = false;
    }
  }

  Future<void> downloadApk(JenkinsWorkspaceEntry entry) async {
    if (!entry.isApk || isBusy) return;

    final dir = await _pickSaveDirectory();
    if (dir == null || dir.isEmpty) return;

    final relFile = '$currentRelativePath${entry.href}';
    final buildId = _resolveBuildId();

    isDownloading.value = true;
    downloadPhase.value = 'uploading';
    downloadMessage.value = '准备下载...';
    downloadPercent.value = 0;

    try {
      final saved = await _service.downloadApk(
        server: args.server,
        jobName: args.jobName,
        relativeFilePath: relFile,
        saveDirectory: dir,
        buildId: buildId,
        onProgress: ({
          required String phase,
          required String message,
          double? percent,
        }) {
          downloadPhase.value = phase;
          downloadMessage.value = message;
          downloadPercent.value = percent;
        },
      );
      Get.snackbar('下载完成', saved);
    } catch (e) {
      Get.snackbar('下载失败', '$e');
    } finally {
      isDownloading.value = false;
      downloadPhase.value = '';
      downloadMessage.value = '';
      downloadPercent.value = null;
    }
  }

  /// 弹出目录选择；若 file_selector 原生通道未就绪（常见于热重启后），回退到下载目录。
  Future<String?> _pickSaveDirectory() async {
    try {
      final dir = await getDirectoryPath(confirmButtonText: '选择保存目录');
      if (dir != null && dir.isNotEmpty) return dir;
      return null;
    } on PlatformException catch (e) {
      print('file_selector 不可用 ($e)，回退到系统下载目录');
      final downloads = await getDownloadsDirectory();
      if (downloads == null) {
        Get.snackbar(
          '无法选择保存目录',
          '请完全退出应用后重新启动（勿用热重启），再试下载',
        );
        return null;
      }
      Get.snackbar('已使用下载目录', downloads.path);
      return downloads.path;
    }
  }

  String _resolveBuildId() {
    final fromArgs = args.buildNumber;
    if (fromArgs != null && fromArgs > 0) return '$fromArgs';

    // 路径中 HotUpdate/{n}/ 提取构建号
    final m = RegExp(r'(?:^|/)HotUpdate/(\d+)(?:/|$)')
        .firstMatch(currentRelativePath);
    if (m != null) return m.group(1)!;

    return 'ws_${DateTime.now().millisecondsSinceEpoch}';
  }
}
