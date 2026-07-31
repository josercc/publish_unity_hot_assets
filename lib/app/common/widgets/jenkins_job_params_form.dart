import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_parameter.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_controller_mixin.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';

/// 展示 Jenkins Job 参数：选项(可筛选) / 开关 / 输入框。
class JenkinsJobParamsForm extends StatelessWidget {
  const JenkinsJobParamsForm({
    super.key,
    required this.controller,
    this.title = '构建参数',
    this.hiddenParamNames = const {},
    /// 为 true 时不自建滚动/Expanded，便于嵌入父级 [SingleChildScrollView]。
    this.shrinkWrap = false,
  });

  final JenkinsJobParamsControllerMixin controller;
  final String title;

  /// 不展示的参数名（大小写不敏感），提交时仍会带上默认值。
  final Set<String> hiddenParamNames;

  final bool shrinkWrap;

  bool _isHidden(String name) {
    final lower = name.toLowerCase();
    return hiddenParamNames.any((h) => h.toLowerCase() == lower);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      if (controller.isLoadingJobParams.value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: shrinkWrap
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const CircularProgressIndicator(),
          ),
        );
      }

      final error = controller.jobParamsError.value;
      if (error != null && error.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Text(
                '加载参数失败',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(error),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: controller.loadJenkinsJobParams,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ),
            ],
          ),
        );
      }

      final params = controller.jobParams
          .where((p) => !_isHidden(p.name))
          .toList();
      if (params.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '该 Job 没有可显示的参数',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: controller.loadJenkinsJobParams,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
        );
      }

      final runStatus = controller.jobRunStatus.value;
      final runBusy = runStatus.isRunning;

      final header = Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (controller.selectedPackagingServerName.value.isNotEmpty)
                  Text(
                    controller.selectedPackagingServerName.value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                _RunStatusChip(status: runStatus),
                FilledButton.icon(
                  onPressed: runBusy
                      ? null
                      : () {
                          // ignore: discarded_futures
                          controller.executeJenkinsJob();
                        },
                  icon: runBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(runBusy ? '执行中' : '执行任务'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    // ignore: discarded_futures
                    controller.openTaskHistory();
                  },
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('任务列表'),
                ),
                if (controller.canOpenJenkinsWorkspace)
                  OutlinedButton.icon(
                    onPressed: controller.openJenkinsWorkspace,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('工作空间'),
                  ),
              ],
            ),
            if (controller.jobRunMessage.value.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _runDetailText(controller),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _statusColor(theme, runStatus),
                ),
              ),
            ],
          ],
        ),
      );

      final paramTiles = [
        for (final param in params)
          _ParamTile(
            controller: controller,
            param: param,
          ),
      ];

      if (shrinkWrap) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            ...paramTiles,
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 独立页：标题行固定，参数列表自滚动
          Material(
            elevation: 1,
            color: theme.colorScheme.surface,
            child: header,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: paramTiles,
            ),
          ),
        ],
      );
    });
  }

  String _runDetailText(JenkinsJobParamsControllerMixin c) {
    final parts = <String>[c.jobRunStatus.value.label];
    final buildNo = c.jobRunBuildNumber.value;
    if (buildNo != null) parts.add('#$buildNo');
    final msg = c.jobRunMessage.value.trim();
    if (msg.isNotEmpty && msg != c.jobRunStatus.value.label) {
      parts.add(msg);
    }
    return parts.join(' · ');
  }

  Color _statusColor(ThemeData theme, JenkinsJobRunStatus status) {
    switch (status) {
      case JenkinsJobRunStatus.success:
        return Colors.green.shade700;
      case JenkinsJobRunStatus.failure:
      case JenkinsJobRunStatus.error:
        return theme.colorScheme.error;
      case JenkinsJobRunStatus.aborted:
        return Colors.orange.shade800;
      case JenkinsJobRunStatus.waiting:
      case JenkinsJobRunStatus.building:
      case JenkinsJobRunStatus.submitting:
        return theme.colorScheme.primary;
      case JenkinsJobRunStatus.idle:
        return theme.hintColor;
    }
  }
}

class _RunStatusChip extends StatelessWidget {
  const _RunStatusChip({required this.status});

  final JenkinsJobRunStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == JenkinsJobRunStatus.idle) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    switch (status) {
      case JenkinsJobRunStatus.success:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case JenkinsJobRunStatus.failure:
      case JenkinsJobRunStatus.error:
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
        break;
      case JenkinsJobRunStatus.aborted:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
        break;
      case JenkinsJobRunStatus.waiting:
      case JenkinsJobRunStatus.building:
      case JenkinsJobRunStatus.submitting:
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
        break;
      case JenkinsJobRunStatus.idle:
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.hintColor;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ParamTile extends StatelessWidget {
  const _ParamTile({
    required this.controller,
    required this.param,
  });

  final JenkinsJobParamsControllerMixin controller;
  final JenkinsJobParameter param;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              param.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (param.description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                param.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _buildInput(context),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    switch (param.widgetType) {
      case JenkinsParamWidgetType.boolean:
        return Obx(() {
          final value = controller.jobParamValues[param.name] == true;
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(value ? '开启' : '关闭'),
            value: value,
            onChanged: (v) => controller.setJobParamValue(param.name, v),
          );
        });
      case JenkinsParamWidgetType.choice:
        return Obx(() {
          final live = controller.jobParams.firstWhereOrNull(
                (p) => p.name == param.name,
              ) ??
              param;
          final isRefreshing =
              controller.refreshingParamNames.contains(live.name);
          if (isRefreshing) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            );
          }
          final current = '${controller.jobParamValues[live.name] ?? ''}';
          final choices = live.choices;
          if (choices.isEmpty) {
            return TextField(
              controller: controller.textControllerFor(
                live.name,
                current,
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: live.isActiveChoices
                    ? 'Active Choices 暂无选项（Groovy 未返回）'
                    : '请输入（无可选项）',
              ),
              onChanged: (v) => controller.setJobParamValue(live.name, v),
            );
          }

          final display = controller.choiceDisplayControllerFor(
            live.name,
            current,
          );
          final filter = controller.choiceFilterControllerFor(live.name);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: display,
                readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: '当前选项',
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: '选择选项',
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: (v) {
                      filter.clear();
                      controller.setJobParamValue(live.name, v);
                    },
                    itemBuilder: (context) => choices
                        .map(
                          (c) => PopupMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: filter,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: '输入筛选，自动选中第一项',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                style: Theme.of(context).textTheme.bodySmall,
                onChanged: (q) =>
                    controller.filterChoiceAndSelectFirst(live.name, q),
              ),
            ],
          );
        });
      case JenkinsParamWidgetType.password:
        return TextField(
          controller: controller.textControllerFor(
            param.name,
            '${param.initialValue ?? ''}',
          ),
          obscureText: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: '请输入',
          ),
          onChanged: (v) => controller.setJobParamValue(param.name, v),
        );
      case JenkinsParamWidgetType.multiLine:
        return TextField(
          controller: controller.textControllerFor(
            param.name,
            '${param.initialValue ?? ''}',
          ),
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: '请输入',
            alignLabelWithHint: true,
          ),
          onChanged: (v) => controller.setJobParamValue(param.name, v),
        );
      case JenkinsParamWidgetType.text:
        return TextField(
          controller: controller.textControllerFor(
            param.name,
            '${param.initialValue ?? ''}',
          ),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: '请输入',
          ),
          onChanged: (v) => controller.setJobParamValue(param.name, v),
        );
    }
  }
}
