import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_build_log_download.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_build_log_service.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/agent_log_service.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/log_view_service.dart';
import 'package:publish_unity_hot_assets/app/modules/log_viewer/log_viewer_args.dart';

class LogViewerController extends GetxController {
  LogViewerController({LogViewService? service})
      : _service = service ?? LogViewService();

  final LogViewService _service;
  final _agentDownload = AgentLogService();
  final _buildDownload = JenkinsBuildLogService();
  final scrollController = ScrollController();

  late final LogViewerArgs args;

  final lines = <String>[].obs;
  final isOpening = false.obs;
  final isLoadingMore = false.obs;
  final isDownloading = false.obs;
  final hasMore = false.obs;
  final errorMessage = RxnString();
  final snapshotSize = 0.obs;

  String? _sessionId;
  int? _oldestOffset;
  bool _loadLocked = false;

  @override
  void onInit() {
    super.onInit();
    final raw = Get.arguments;
    if (raw is! LogViewerArgs) {
      errorMessage.value = '缺少日志页参数';
      return;
    }
    args = raw;
    // ignore: discarded_futures
    openSession();
  }

  @override
  void onClose() {
    // ignore: discarded_futures
    _closeRemoteSession();
    scrollController.dispose();
    _service.close();
    _agentDownload.close();
    _buildDownload.close();
    super.onClose();
  }

  Future<void> openSession() async {
    if (_loadLocked) return;
    _loadLocked = true;
    isOpening.value = true;
    errorMessage.value = null;
    try {
      await _closeRemoteSession();
      lines.clear();
      _oldestOffset = null;
      hasMore.value = false;

      final LogViewChunk chunk;
      if (args.kind == LogViewerKind.agent) {
        chunk = await _service.openAgentLog(server: args.server);
      } else {
        final job = args.jobName?.trim() ?? '';
        final build = args.buildNumber?.trim() ?? '';
        if (job.isEmpty || build.isEmpty) {
          throw StateError('构建日志需要 jobName 与 buildNumber');
        }
        chunk = await _service.openBuildLog(
          server: args.server,
          jobName: job,
          buildNumber: build,
        );
      }

      _sessionId = chunk.sessionId;
      _oldestOffset = chunk.startOffset;
      hasMore.value = chunk.hasMore;
      snapshotSize.value = chunk.size;
      lines.assignAll(chunk.lines);
      _scrollToBottom();
    } catch (e) {
      errorMessage.value = e.toString();
      lines.clear();
    } finally {
      isOpening.value = false;
      _loadLocked = false;
    }
  }

  /// 仅用户点击时向上再拉一块，不自动滚动加载。
  Future<void> loadEarlier() async {
    final sessionId = _sessionId;
    final before = _oldestOffset;
    if (_loadLocked ||
        sessionId == null ||
        sessionId.isEmpty ||
        before == null ||
        !hasMore.value) {
      return;
    }

    _loadLocked = true;
    isLoadingMore.value = true;
    try {
      final chunk = await _service.loadEarlier(
        server: args.server,
        sessionId: sessionId,
        beforeOffset: before,
      );
      _oldestOffset = chunk.startOffset;
      hasMore.value = chunk.hasMore;
      snapshotSize.value = chunk.size;
      if (chunk.lines.isNotEmpty) {
        lines.insertAll(0, chunk.lines);
      }
    } catch (e) {
      Get.snackbar('加载失败', '$e');
    } finally {
      isLoadingMore.value = false;
      _loadLocked = false;
    }
  }

  Future<void> downloadFullLog() async {
    if (isDownloading.value) return;
    isDownloading.value = true;
    try {
      final dir = await pickLogSaveDirectory();
      if (dir == null) return;

      SmartDialog.showLoading(msg: '正在下载完整日志...');
      final String saved;
      if (args.kind == LogViewerKind.agent) {
        saved = await _agentDownload.downloadFullLog(
          server: args.server,
          saveDirectory: dir,
          onProgress: ({
            required String phase,
            required String message,
            double? percent,
          }) {
            SmartDialog.showLoading(msg: message);
          },
        );
      } else {
        final job = args.jobName?.trim() ?? '';
        final build = int.tryParse(args.buildNumber?.trim() ?? '');
        if (job.isEmpty || build == null) {
          throw StateError('无法下载：缺少 jobName / buildNumber');
        }
        saved = await _buildDownload.downloadFullLog(
          server: args.server,
          jobName: job,
          buildNumber: build,
          saveDirectory: dir,
          onProgress: ({
            required String phase,
            required String message,
            double? percent,
          }) {
            SmartDialog.showLoading(msg: message);
          },
        );
      }
      SmartDialog.dismiss();
      Get.snackbar('下载完成', saved);
    } catch (e) {
      SmartDialog.dismiss();
      Get.snackbar('下载失败', '$e');
    } finally {
      isDownloading.value = false;
    }
  }

  Future<void> _closeRemoteSession() async {
    final sessionId = _sessionId;
    _sessionId = null;
    if (sessionId == null || sessionId.isEmpty) return;
    await _service.closeSession(server: args.server, sessionId: sessionId);
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    });
  }
}
