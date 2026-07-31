import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_workspace_entry.dart';

import '../controllers/jenkins_workspace_controller.dart';

class JenkinsWorkspaceView extends GetView<JenkinsWorkspaceController> {
  const JenkinsWorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作空间'),
        actions: [
          Obx(() {
            final busy = controller.isBusy;
            return IconButton(
              tooltip: '清理工作目录',
              onPressed: busy
                  ? null
                  : () {
                      // ignore: discarded_futures
                      controller.wipeOutWorkspace();
                    },
              icon: controller.isWiping.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
            );
          }),
          Obx(() {
            final busy = controller.isBusy;
            return IconButton(
              tooltip: '刷新',
              onPressed: busy ? null : controller.loadCurrent,
              icon: const Icon(Icons.refresh),
            );
          }),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BreadcrumbBar(controller: controller),
          Obx(() {
            if (!controller.isWiping.value) {
              return const SizedBox.shrink();
            }
            return Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '正在清理 Jenkins 工作目录…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Obx(() {
            if (!controller.isDownloading.value) {
              return const SizedBox.shrink();
            }
            return _DownloadBanner(controller: controller);
          }),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.entries.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final err = controller.errorMessage.value;
              if (err != null && err.isNotEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          err,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: controller.loadCurrent,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final items = controller.entries.toList();
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    '目录为空',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  return _EntryTile(
                    entry: entry,
                    downloading: controller.isBusy,
                    onOpen: () => controller.openEntry(entry),
                    onDownload: () {
                      // ignore: discarded_futures
                      controller.downloadApk(entry);
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.controller});

  final JenkinsWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Obx(() {
          final segments = controller.pathSegments.toList();
          return Row(
            children: [
              IconButton(
                tooltip: '上级目录',
                onPressed: segments.isEmpty || controller.isBusy
                    ? null
                    : controller.goUp,
                icon: const Icon(Icons.arrow_upward, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                        TextButton(
                          onPressed: !controller.hasArgs ||
                                  segments.isEmpty ||
                                  controller.isBusy
                              ? null
                              : controller.goToRoot,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: Text(
                            controller.hasArgs
                                ? controller.args.jobName
                                : 'ws',
                          ),
                        ),
                      for (var i = 0; i < segments.length; i++) ...[
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: theme.hintColor,
                        ),
                        TextButton(
                          onPressed: i >= segments.length - 1 ||
                                  controller.isBusy
                              ? null
                              : () => controller.goToSegment(i),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: Text(
                            segments[i].replaceAll(RegExp(r'/+$'), ''),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({required this.controller});

  final JenkinsWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Obx(() {
          final percent = controller.downloadPercent.value;
          final phase = controller.downloadPhase.value;
          final phaseLabel = switch (phase) {
            'uploading' => '上传中',
            'downloading' => '下载中',
            'cleanup' => '清理中',
            _ => '处理中',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: percent == null ? null : percent / 100,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    phaseLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (percent != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${percent.toStringAsFixed(1)}%',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                controller.downloadMessage.value,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: percent == null ? null : (percent / 100).clamp(0, 1),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.downloading,
    required this.onOpen,
    required this.onDownload,
  });

  final JenkinsWorkspaceEntry entry;
  final bool downloading;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final isDir = entry.isDirectory;
    return ListTile(
      leading: Icon(
        isDir
            ? Icons.folder
            : (entry.isApk ? Icons.android : Icons.insert_drive_file_outlined),
      ),
      title: Text(entry.name),
      subtitle: entry.isApk ? const Text('APK') : null,
      onTap: isDir && !downloading ? onOpen : null,
      trailing: entry.isApk
          ? TextButton.icon(
              onPressed: downloading ? null : onDownload,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('下载'),
            )
          : (isDir
              ? const Icon(Icons.chevron_right)
              : null),
    );
  }
}
