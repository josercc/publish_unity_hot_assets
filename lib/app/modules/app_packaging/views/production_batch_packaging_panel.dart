import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/modules/app_packaging/controllers/app_packaging_controller.dart';

/// 一键生产打包：映射 build_automation.py 的确认与输入项。
class ProductionBatchPackagingPanel extends StatefulWidget {
  const ProductionBatchPackagingPanel({
    super.key,
    required this.controller,
  });

  final AppPackagingController controller;

  @override
  State<ProductionBatchPackagingPanel> createState() =>
      _ProductionBatchPackagingPanelState();
}

class _ProductionBatchPackagingPanelState
    extends State<ProductionBatchPackagingPanel> {
  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    widget.controller.refreshProductionServer();
  }

  AppPackagingController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final busy = c.isBatchRunning.value;
      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Text(
            '一键生产打包',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '按生产脚本规则批量触发 build_winner_app_binary_2.0（iOS + Android 渠道）',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (c.selectedPackagingServerName.value.isNotEmpty)
                Text(
                  c.selectedPackagingServerName.value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        // ignore: discarded_futures
                        c.refreshProductionServer();
                      },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新打包机'),
              ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        // ignore: discarded_futures
                        c.executeProductionBatch();
                      },
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.rocket_launch, size: 18),
                label: Text(busy ? '提交中...' : '开始生产打包'),
              ),
            ],
          ),
          if (c.batchSummary.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              c.batchSummary.value,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          _BranchField(
            label: 'Flutter 分支 (MELOS_BRANCH)',
            hint: '默认 release',
            controller: c.melosBranchController,
            selected: c.melosBranch.value,
            choices: c.branchChoicesFor('MELOS_BRANCH'),
            enabled: !busy,
            onSelected: c.setMelosBranch,
          ),
          const SizedBox(height: 8),
          _BranchField(
            label: 'Unity 分支 (UNITY_BRANCH)',
            hint: '默认 release2.0.0',
            controller: c.unityBranchController,
            selected: c.unityBranch.value,
            choices: c.branchChoicesFor('UNITY_BRANCH'),
            enabled: !busy,
            onSelected: c.setUnityBranch,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c.buildNameController,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'BUILD_NAME（必填）',
              hintText: '请输入构建名称',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用自定义构建号'),
            subtitle: const Text('关闭则自动生成 10 位秒级时间戳'),
            value: c.useCustomBuildNumber.value,
            onChanged: busy
                ? null
                : (v) => c.useCustomBuildNumber.value = v,
          ),
          if (c.useCustomBuildNumber.value) ...[
            TextField(
              controller: c.customBuildNumberController,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: '自定义 BUILD_NUMBER',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 24),
          Text('iOS', style: theme.textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('打包 iOS'),
            subtitle: const Text('关闭则跳过 iOS（对应脚本「是否跳过 iOS」）'),
            value: c.includeIos.value,
            onChanged: busy ? null : (v) => c.includeIos.value = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('iOS 使用缓存'),
            value: c.iosUseCache.value,
            onChanged: busy || !c.includeIos.value
                ? null
                : (v) => c.iosUseCache.value = v,
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Android 渠道', style: theme.textTheme.titleSmall),
              ),
              TextButton(
                onPressed: busy ? null : c.selectAllChannels,
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: busy ? null : c.clearAllChannels,
                child: const Text('全不选'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '取消勾选即跳过该渠道；Winner 可单独设置缓存，其它渠道固定使用缓存',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final channel in AppPackagingController.androidChannels)
                FilterChip(
                  label: Text(channel),
                  selected: c.selectedChannels.contains(channel),
                  onSelected: busy
                      ? null
                      : (selected) => c.toggleChannel(channel, selected),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Winner 渠道使用缓存'),
            subtitle: const Text('仅对 Android Winner 生效；其它渠道始终使用缓存'),
            value: c.winnerUseCache.value,
            onChanged: busy || !c.selectedChannels.contains('Winner')
                ? null
                : (v) => c.winnerUseCache.value = v,
          ),
          if (c.batchItems.isNotEmpty) ...[
            const Divider(height: 24),
            Text('提交进度', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final item in c.batchItems)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: _statusIcon(theme, item.status),
                title: Text(item.label),
                subtitle: item.message.isEmpty ? null : Text(item.message),
              ),
          ],
        ],
      );
    });
  }

  Widget _statusIcon(ThemeData theme, ProductionBatchItemStatus status) {
    switch (status) {
      case ProductionBatchItemStatus.pending:
        return Icon(Icons.schedule, color: theme.hintColor);
      case ProductionBatchItemStatus.submitting:
        return const SizedBox(
          width: 24,
          height: 24,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case ProductionBatchItemStatus.ok:
        return Icon(Icons.check_circle, color: theme.colorScheme.primary);
      case ProductionBatchItemStatus.fail:
        return Icon(Icons.error, color: theme.colorScheme.error);
    }
  }
}

/// Jenkins 有选项时下拉选择，否则可自由输入。
class _BranchField extends StatelessWidget {
  const _BranchField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.selected,
    required this.choices,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String selected;
  final List<String> choices;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) {
      return TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onSelected,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }

    final items = <String>{
      ...choices,
      if (selected.isNotEmpty) selected,
      if (controller.text.trim().isNotEmpty) controller.text.trim(),
    }.toList();
    final value = items.contains(selected) ? selected : items.first;

    return DropdownButtonFormField<String>(
      key: ValueKey('$label|$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final c in items)
          DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) onSelected(v);
            }
          : null,
    );
  }
}
