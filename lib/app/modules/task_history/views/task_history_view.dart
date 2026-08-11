import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_historical_task.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';

import '../controllers/task_history_controller.dart';

class TaskHistoryView extends GetView<TaskHistoryController> {
  const TaskHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: controller.loadHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.tasks.isEmpty) {
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
                    onPressed: controller.loadHistory,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        final items = controller.tasks.toList();
        if (items.isEmpty) {
          return Center(
            child: Text(
              '暂无构建历史',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: controller.loadHistory,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final task = items[index];
              final cancelling =
                  controller.cancellingTaskIds.contains(task.id);
              final canCancel = task.status == JenkinsJobRunStatus.waiting ||
                  task.status == JenkinsJobRunStatus.building;
              return _TaskHistoryTile(
                task: task,
                canCancel: canCancel,
                cancelling: cancelling,
                onRetry: () => controller.retryTask(task),
                onCancel: canCancel
                    ? () {
                        // ignore: discarded_futures
                        controller.cancelTask(task);
                      }
                    : null,
              );
            },
          ),
        );
      }),
    );
  }
}

class _TaskHistoryTile extends StatelessWidget {
  const _TaskHistoryTile({
    required this.task,
    required this.onRetry,
    required this.canCancel,
    required this.cancelling,
    this.onCancel,
  });

  final JenkinsHistoricalTask task;
  final VoidCallback onRetry;
  final bool canCancel;
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildText = task.buildNumber != null
        ? '#${task.buildNumber}'
        : (task.queueId != null ? '队列 #${task.queueId}' : null);
    final serverText = [
      if (task.serverName.isNotEmpty) task.serverName,
      if (task.serverTag.isNotEmpty) task.serverTag,
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Row(
        children: [
          Expanded(
            child: Text(
              task.summaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status: task.status),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (buildText != null) buildText,
                if (serverText.isNotEmpty) serverText,
                _formatTime(task.updatedAt),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            if (task.message.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canCancel)
                  FilledButton.tonalIcon(
                    onPressed: cancelling ? null : onCancel,
                    icon: cancelling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined, size: 16),
                    label: Text(cancelling ? '取消中' : '取消'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.replay, size: 16),
                  label: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      ),
      isThreeLine: true,
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final JenkinsJobRunStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late Color bg;
    late Color fg;
    switch (status) {
      case JenkinsJobRunStatus.success:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
      case JenkinsJobRunStatus.failure:
      case JenkinsJobRunStatus.error:
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
      case JenkinsJobRunStatus.aborted:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
      case JenkinsJobRunStatus.waiting:
      case JenkinsJobRunStatus.building:
      case JenkinsJobRunStatus.submitting:
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
      case JenkinsJobRunStatus.idle:
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.hintColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
