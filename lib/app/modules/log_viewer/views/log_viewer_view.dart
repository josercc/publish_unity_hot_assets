import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/modules/log_viewer/controllers/log_viewer_controller.dart';

class LogViewerView extends GetView<LogViewerController> {
  const LogViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final err = controller.errorMessage.value;
          if (err != null && controller.lines.isEmpty) {
            return const Text('日志');
          }
          try {
            return Text(controller.args.resolvedTitle);
          } catch (_) {
            return const Text('日志');
          }
        }),
        actions: [
          Obx(() {
            final busy = controller.isOpening.value ||
                controller.isDownloading.value;
            return IconButton(
              tooltip: '重新打开快照',
              onPressed: busy ? null : controller.openSession,
              icon: const Icon(Icons.refresh),
            );
          }),
          Obx(() {
            final busy = controller.isDownloading.value ||
                controller.isOpening.value;
            return PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (value) {
                if (value == 'download') {
                  // ignore: discarded_futures
                  controller.downloadFullLog();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'download',
                  child: Text('下载完整日志'),
                ),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        if (controller.isOpening.value && controller.lines.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final err = controller.errorMessage.value;
        if (err != null && err.isNotEmpty && controller.lines.isEmpty) {
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
                    onPressed: controller.openSession,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        final items = controller.lines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    if (controller.hasMore.value)
                      FilledButton.tonalIcon(
                        onPressed: controller.isLoadingMore.value
                            ? null
                            : () {
                                // ignore: discarded_futures
                                controller.loadEarlier();
                              },
                        icon: controller.isLoadingMore.value
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.vertical_align_top, size: 18),
                        label: Text(
                          controller.isLoadingMore.value
                              ? '加载中'
                              : '加载更早日志',
                        ),
                      )
                    else
                      Text(
                        '已到日志开头',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '${items.length} 行'
                      '${controller.snapshotSize.value > 0 ? ' · 快照 ${(controller.snapshotSize.value / 1024).toStringAsFixed(1)} KB' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '暂无日志内容',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        controller: controller.scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return Text(
                            items[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.35,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }
}
