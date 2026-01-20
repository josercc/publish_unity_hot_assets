import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';

import '../controllers/jenkins_servers_controller.dart';

class JenkinsServersView extends GetView<JenkinsServersController> {
  const JenkinsServersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jenkins服务器配置'),
      ),
      body: Obx(() {
        final servers = controller.servers;
        if (servers.isEmpty) {
          return const Center(child: Text('暂无服务器，请点击右下角新增'));
        }
        return ListView.separated(
          itemCount: servers.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final s = servers[index];
            final isSelected = controller.selectedId.value == s.id;
            return ListTile(
              title: Text('${s.displayName}${isSelected ? '（默认）' : ''}'),
              subtitle: Text(s.jenkinsUrl),
              onTap: () => controller.setDefault(s.id),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑',
                    onPressed: () => _openEditDialog(context, s),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => _confirmDelete(context, s),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, JenkinsServerConfig s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除服务器：${s.displayName}？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) controller.deleteServer(s.id);
  }

  Future<void> _openAddDialog(BuildContext context) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _openUpsertDialog(
      context,
      title: '新增服务器',
      initial: JenkinsServerConfig(
        id: id,
        name: '',
        jenkinsUrl: '',
        jenkinsUsername: '',
        jenkinsPassword: '',
      ),
      onSubmit: (server) {
        final normalized = controller.normalize(server);
        controller.addServer(normalized);
      },
    );
  }

  Future<void> _openEditDialog(BuildContext context, JenkinsServerConfig s) async {
    await _openUpsertDialog(
      context,
      title: '编辑服务器',
      initial: s,
      onSubmit: (server) {
        final normalized = controller.normalize(server);
        controller.updateServer(normalized);
      },
    );
  }

  Future<void> _openUpsertDialog(
    BuildContext context, {
    required String title,
    required JenkinsServerConfig initial,
    required void Function(JenkinsServerConfig server) onSubmit,
  }) async {
    final nameCtrl = TextEditingController(text: initial.name);
    final urlCtrl = TextEditingController(text: initial.jenkinsUrl);
    final userCtrl = TextEditingController(text: initial.jenkinsUsername);
    final passCtrl = TextEditingController(text: initial.jenkinsPassword);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '服务器名称（可不填，不填则用请求地址host）'),
              ),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'Jenkins请求地址'),
              ),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: 'Jenkins用户名'),
              ),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Jenkins密码'),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              try {
                onSubmit(
                  initial.copyWith(
                    name: nameCtrl.text,
                    jenkinsUrl: urlCtrl.text,
                    jenkinsUsername: userCtrl.text,
                    jenkinsPassword: passCtrl.text,
                  ),
                );
                Navigator.pop(context);
              } catch (_) {
                // normalize 内会 toast
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}


