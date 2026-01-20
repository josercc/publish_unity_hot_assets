import 'dart:convert';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/functions.dart';
import 'package:publish_unity_hot_assets/app/modules/login/controllers/login_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JenkinsServersController extends GetxController {
  final LoginController loginController = Get.find<LoginController>();

  RxList<JenkinsServerConfig> get servers => loginController.jenkinsServers;
  RxnString get selectedId => loginController.selectedJenkinsServerId;

  Environment get env => loginController.curEnv.value;

  JenkinsServerConfig? get selectedServer => loginController.selectedServer;

  @override
  void onInit() {
    super.onInit();
    // 确保从本地加载/迁移过（登录页已有 initLocalLoginInfo，这里兜底刷新一次）
    loginController.initLocalLoginInfo(env);
  }

  void setDefault(String id) {
    loginController.selectServer(id);
    saveToLocal();
  }

  void addServer(JenkinsServerConfig server) {
    servers.add(server);
    loginController.selectServer(server.id);
    saveToLocal();
  }

  void updateServer(JenkinsServerConfig server) {
    final idx = servers.indexWhere((e) => e.id == server.id);
    if (idx >= 0) {
      servers[idx] = server;
      if (selectedId.value == server.id) {
        loginController.selectServer(server.id);
      }
      saveToLocal();
    }
  }

  void deleteServer(String id) {
    final idx = servers.indexWhere((e) => e.id == id);
    if (idx < 0) return;

    servers.removeAt(idx);
    if (selectedId.value == id) {
      selectedId.value = servers.isNotEmpty ? servers.first.id : null;
      if (selectedId.value != null) {
        loginController.selectServer(selectedId.value);
      }
    }
    saveToLocal();
  }

  Future<void> saveToLocal() async {
    final sp = await SharedPreferences.getInstance();
    final key = env.toString();
    final raw = sp.getString(key);
    if (raw == null) {
      // 允许只保存服务器配置：其它字段为空
      final cfg = LoginConfig(
        gmallUsername: '',
        gmallPassword: '',
        jenkinsUsername: selectedServer?.jenkinsUsername ?? '',
        jenkinsPassword: selectedServer?.jenkinsPassword ?? '',
        environmentConfig: EnvironmentConfig(gmallUrl: '', gmallKey: '', jenkinsUrl: selectedServer?.jenkinsUrl ?? ''),
        jenkinsServers: servers.toList(),
        selectedJenkinsServerId: selectedId.value,
      );
      await sp.setString(key, jsonEncode(cfg.toJson()));
      return;
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final existing = LoginConfig.fromJson(json);
    final currentSelected = selectedServer;
    final cfg = LoginConfig(
      environmentConfig: EnvironmentConfig(
        gmallUrl: existing.environmentConfig.gmallUrl,
        gmallKey: existing.environmentConfig.gmallKey,
        // 兼容旧字段：同步为选中服务器的 Jenkins URL
        jenkinsUrl: currentSelected?.jenkinsUrl ?? existing.environmentConfig.jenkinsUrl,
      ),
      gmallUsername: existing.gmallUsername,
      gmallPassword: existing.gmallPassword,
      // 兼容旧字段：同步为选中服务器的账号密码
      jenkinsUsername: currentSelected?.jenkinsUsername ?? existing.jenkinsUsername,
      jenkinsPassword: currentSelected?.jenkinsPassword ?? existing.jenkinsPassword,
      jenkinsServers: servers.toList(),
      selectedJenkinsServerId: selectedId.value,
    );
    await sp.setString(key, jsonEncode(cfg.toJson()));
    await loginController.saveSharedJenkinsCurrent();
  }

  /// 校验并标准化：服务器名称可空，空则回退为服务器 IP
  JenkinsServerConfig normalize(JenkinsServerConfig server) {
    final nameInput = server.name.trim();
    if (server.jenkinsUrl.trim().isEmpty) {
      showErrorToast('请输入 Jenkins 请求地址');
      throw Exception('Jenkins请求地址为空');
    }
    String host = '';
    try {
      host = Uri.parse(server.jenkinsUrl.trim()).host.trim();
    } catch (_) {
      host = '';
    }
    final fallbackName = host.isEmpty ? server.jenkinsUrl.trim() : host;
    final name = nameInput.isEmpty ? fallbackName : nameInput;
    return server.copyWith(name: name);
  }
}


