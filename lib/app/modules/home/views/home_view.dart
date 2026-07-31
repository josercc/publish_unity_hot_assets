import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/jenkins_workload_service.dart';
import 'package:publish_unity_hot_assets/app/modules/home/controllers/home_controller.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  static const _features = [
    _HomeFeature(
      title: 'Unity导包',
      icon: Icons.unarchive_outlined,
      route: Routes.UNITY_IMPORT,
    ),
    _HomeFeature(
      title: 'Unity首包',
      icon: Icons.inventory_2_outlined,
      route: Routes.UNITY_FIRST_PACKAGE,
    ),
    _HomeFeature(
      title: 'Unity打热更',
      icon: Icons.system_update_alt,
      route: Routes.UNITY_HOT_UPDATE,
    ),
    _HomeFeature(
      title: 'App 打包',
      icon: Icons.phone_android,
      route: Routes.APP_PACKAGING,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('打包中心'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '刷新打包机状态',
            onPressed: controller.refreshPackagingServers,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: () async {
              await controller.logoutToLogin();
            },
            child: const Text('退出'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 720 ? 4 : 2;
                final itemWidth =
                    (constraints.maxWidth - (crossAxisCount - 1) * 16) /
                        crossAxisCount;
                final itemHeight = itemWidth / 1.2;
                final rows = (_features.length / crossAxisCount).ceil();
                final gridHeight = rows * itemHeight + (rows - 1) * 16;
                return SizedBox(
                  height: gridHeight.clamp(120, 220),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: _features.length,
                    itemBuilder: (context, index) {
                      final feature = _features[index];
                      return _FeatureCard(
                        title: feature.title,
                        icon: feature.icon,
                        onTap: () => Get.toNamed(feature.route),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '打包机',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                Obx(() {
                  if (!controller.isLoadingServers.value) {
                    return const SizedBox.shrink();
                  }
                  return const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }),
                const Spacer(),
                Obx(() {
                  final selected = controller.selectedServerId;
                  return Text(
                    selected == null ? '未选中 · 任务自动分配' : '已指定打包机',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Obx(() {
                final rows = controller.packagingRows;
                final selectedId = controller.selectedServerId;
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      controller.isLoadingServers.value
                          ? '正在加载打包机…'
                          : '暂无可用打包机',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _PackagingServerTile(
                      name: row.server.displayName,
                      url: row.server.url,
                      online: row.server.online,
                      tag: row.server.tag,
                      workload: row.workload,
                      selected: selectedId == row.server.id,
                      onTap: () =>
                          controller.togglePackagingServer(row.server.id),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeature {
  final String title;
  final IconData icon;
  final String route;

  const _HomeFeature({
    required this.title,
    required this.icon,
    required this.route,
  });
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackagingServerTile extends StatelessWidget {
  final String name;
  final String url;
  final bool online;
  final String tag;
  final JenkinsWorkloadStatus workload;
  final bool selected;
  final VoidCallback onTap;

  const _PackagingServerTile({
    required this.name,
    required this.url,
    required this.online,
    required this.tag,
    required this.workload,
    required this.selected,
    required this.onTap,
  });

  Color get _workloadColor {
    switch (workload) {
      case JenkinsWorkloadStatus.idle:
        return Colors.green;
      case JenkinsWorkloadStatus.building:
        return Colors.amber.shade700;
      case JenkinsWorkloadStatus.buildingWithQueue:
        return Colors.red;
      case JenkinsWorkloadStatus.offline:
        return Colors.grey;
      case JenkinsWorkloadStatus.unknown:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = Uri.tryParse(url)?.host ?? url;
    final bg = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _workloadColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _workloadColor.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              const SizedBox(width: 8),
              _StatusChip(
                label: online ? '在线' : '离线',
                color: online ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              _StatusChip(
                label: workload.label,
                color: _workloadColor,
              ),
              if (tag.isNotEmpty) ...[
                const SizedBox(width: 6),
                _StatusChip(
                  label: tag,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
