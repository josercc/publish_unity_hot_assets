import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/updater/app_updater_service.dart';
import 'package:publish_unity_hot_assets/app/common/log_exporter.dart';

class UpdateController extends GetxController {
  final AppUpdaterService _updaterService = AppUpdaterService();

  // 更新状态
  final isChecking = false.obs;
  final isDownloading = false.obs;
  final isInstalling = false.obs;

  // 下载进度
  final downloadProgress = 0.0.obs;
  final downloadSpeed = 0.0.obs; // KB/s

  // 更新信息
  final updateInfo = Rxn<UpdateInfo>();

  // 上次检查时间
  DateTime? _lastCheckTime;
  static const _checkInterval = Duration(hours: 1); // 每小时检查一次

  /// 检查更新（带间隔限制）
  /// [forceCheck] 是否强制检查
  /// [showLoading] 是否显示加载动画（默认显示，让用户知道正在检查）
  Future<void> checkForUpdate({
    bool forceCheck = false,
    bool? showLoading,
  }) async {
    // 如果不在强制检查模式，且距离上次检查时间不足1小时，则跳过
    if (!forceCheck && _lastCheckTime != null) {
      final elapsed = DateTime.now().difference(_lastCheckTime!);
      if (elapsed < _checkInterval) {
        return;
      }
    }

    if (isChecking.value) return;

    // 默认显示加载动画，除非明确指定不显示
    final shouldShowLoading = showLoading ?? true;

    isChecking.value = true;

    // 显示加载动画
    if (shouldShowLoading) {
      SmartDialog.showLoading(msg: '正在检查最新版本...');
    }

    try {
      final info = await _updaterService.checkForUpdate();
      _lastCheckTime = DateTime.now();

      // 关闭加载动画后再显示对话框
      if (shouldShowLoading) {
        SmartDialog.dismiss();
      }

      if (info != null) {
        updateInfo.value = info;
        // 显示更新对话框
        _showUpdateDialog(info);
      } else if (forceCheck) {
        SmartDialog.showToast('当前已是最新版本');
      }
    } catch (e) {
      // 确保关闭加载动画
      if (shouldShowLoading) {
        SmartDialog.dismiss();
      }

      if (forceCheck) {
        SmartDialog.showToast('检查更新失败: $e');
      } else {
        // 非强制检查时也打印错误，但不显示给用户
        print('检查更新失败: $e');
      }
    } finally {
      isChecking.value = false;
    }
  }

  /// 下载并安装更新
  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (isDownloading.value || isInstalling.value) return;

    isDownloading.value = true;
    downloadProgress.value = 0.0;
    downloadSpeed.value = 0.0;

    // 显示下载进度对话框
    showDownloadProgress();

    try {
      int lastBytes = 0;
      DateTime lastTime = DateTime.now();

      // 下载更新文件
      final downloadPath = await _updaterService.downloadUpdate(
        info,
        (received, total) {
          final now = DateTime.now();
          final elapsed = now.difference(lastTime).inMilliseconds;

          if (elapsed > 0) {
            final bytesPerSecond = (received - lastBytes) / (elapsed / 1000);
            downloadSpeed.value = bytesPerSecond / 1024; // KB/s
          }

          downloadProgress.value = received / total;
          lastBytes = received;
          lastTime = now;
        },
      );

      // 关闭下载进度对话框
      Get.back();

      isDownloading.value = false;
      isInstalling.value = true;

      SmartDialog.showLoading(msg: '正在安装更新...');

      // 安装更新，获取新应用的路径
      final newAppPath = await _updaterService.installUpdate(downloadPath);

      SmartDialog.dismiss();
      isInstalling.value = false;

      // 安装完成后，启动新版本并退出当前版本
      if (newAppPath != null) {
        print('准备启动新版本: $newAppPath');

        if (Platform.isMacOS) {
          // macOS: 使用 open 命令启动新应用
          try {
            await Process.run(
              'open',
              [newAppPath],
            );
            print('已启动新版本应用');
          } catch (e) {
            print('启动新版本失败: $e');
          }
        } else if (Platform.isWindows) {
          // Windows: 启动新版本的 exe 文件
          try {
            final exePath =
                path.join(newAppPath, 'publish_unity_hot_assets.exe');
            if (await File(exePath).exists()) {
              await Process.start(
                exePath,
                [],
                mode: ProcessStartMode.detached,
              );
              print('已启动新版本应用: $exePath');
            }
          } catch (e) {
            print('启动新版本失败: $e');
          }
        }
      }

      // 显示重启提示
      Get.dialog(
        AlertDialog(
          title: const Text('更新完成'),
          content: Text(
            Platform.isWindows ? '应用已更新成功，新版本正在启动...' : '应用已更新成功，新版本正在启动...',
          ),
        ),
        barrierDismissible: false,
      );

      // 延迟一下让用户看到提示，然后退出应用
      await Future.delayed(const Duration(seconds: 2));

      // 退出当前应用
      exit(0);
    } catch (e, stackTrace) {
      // 打印详细错误信息
      print('更新失败 - 错误: $e');
      print('更新失败 - 堆栈: $stackTrace');

      Get.back(); // 关闭下载进度对话框（如果还在显示）
      SmartDialog.dismiss(); // 关闭加载对话框（如果还在显示）

      // 显示详细的错误信息对话框
      Get.dialog(
        AlertDialog(
          title: const Text('更新失败'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('更新过程中发生错误：'),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请查看控制台日志获取详细信息。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            // 导出日志按钮
            TextButton.icon(
              onPressed: () async {
                try {
                  // 显示导出中提示
                  SmartDialog.showLoading(msg: '正在导出日志...');

                  // 收集额外信息
                  final additionalInfo = <String, dynamic>{
                    '更新文件路径': info.downloadUrl,
                    '更新版本': info.version,
                    '文件大小':
                        '${(info.fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
                  };

                  // 导出日志
                  final logPath = await LogExporter.exportUpdateErrorLog(
                    error: e,
                    stackTrace: stackTrace,
                    additionalInfo: additionalInfo,
                  );

                  SmartDialog.dismiss();

                  // 显示成功提示
                  Get.dialog(
                    AlertDialog(
                      title: const Text('日志导出成功'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('日志文件已保存到：'),
                          const SizedBox(height: 8),
                          SelectableText(
                            logPath,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '请将此文件发送给开发者以便排查问题。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            Get.back();
                            // 尝试打开文件所在目录
                            await LogExporter.openFileLocation(logPath);
                          },
                          child: const Text('打开文件位置'),
                        ),
                        ElevatedButton(
                          onPressed: () => Get.back(),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                } catch (exportError) {
                  SmartDialog.dismiss();
                  SmartDialog.showToast('导出日志失败: $exportError');
                }
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('导出日志'),
            ),
            // 确定按钮
            ElevatedButton(
              onPressed: () => Get.back(),
              child: const Text('确定'),
            ),
          ],
        ),
        barrierDismissible: false,
      );

      isDownloading.value = false;
      isInstalling.value = false;
    }
  }

  /// 显示更新对话框
  void _showUpdateDialog(UpdateInfo info) {
    Get.dialog(
      AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最新版本: ${info.version}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                  '下载大小: ${(info.fileSize / 1024 / 1024).toStringAsFixed(2)} MB'),
              if (info.releaseNotes != null &&
                  info.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '更新内容:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    info.releaseNotes!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // 只能点击安装，不能取消
          ElevatedButton(
            onPressed: () {
              Get.back();
              downloadAndInstall(info);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 40),
            ),
            child: const Text('安装更新'),
          ),
        ],
      ),
      barrierDismissible: false, // 不允许点击外部关闭
    );
  }

  /// 显示下载进度对话框
  void showDownloadProgress() {
    Get.dialog(
      PopScope(
        canPop: false, // 下载中不允许关闭
        child: AlertDialog(
          title: const Text('正在下载更新'),
          content: Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: downloadProgress.value),
                const SizedBox(height: 8),
                Text(
                  '${(downloadProgress.value * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 16),
                ),
                if (downloadSpeed.value > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '速度: ${downloadSpeed.value.toStringAsFixed(1)} KB/s',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  @override
  void onClose() {
    super.onClose();
  }
}
