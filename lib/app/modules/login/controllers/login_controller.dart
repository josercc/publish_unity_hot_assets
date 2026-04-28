import 'dart:convert';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/functions.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins_api.dart';
import 'package:publish_unity_hot_assets/app/common/r_s_a_encryptor.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginController extends GetxController {
  static const String _sharedJenkinsKey = 'shared_jenkins_servers';
  final userNameTextController = TextEditingController();
  final passwordTextController = TextEditingController();
  final jenkinsUserNameTextController = TextEditingController();
  final jenkinsPasswordTextController = TextEditingController();
  final jenkinsServerNameTextController = TextEditingController();

  /// Gmall 请求地址
  TextEditingController gmallUrlController = TextEditingController();

  /// Gmall 密钥
  TextEditingController gmallKeyController = TextEditingController();

  /// Jenkins 请求地址
  TextEditingController jenkinsUrlController = TextEditingController();

  /// 当前环境
  final curEnv = Environment.test.obs;

  /// Jenkins 服务器列表
  final jenkinsServers = <JenkinsServerConfig>[].obs;

  /// 当前选中的 Jenkins 服务器 ID
  final selectedJenkinsServerId = RxnString();

  @override
  void onInit() {
    super.onInit();
    initLocalLoginInfo(curEnv.value);
  }

  switchEnv(Environment env) {
    curEnv.value = env;
    initLocalLoginInfo(curEnv.value);
  }

  JenkinsServerConfig? get selectedServer {
    final id = selectedJenkinsServerId.value;
    if (id == null) return null;
    try {
      return jenkinsServers.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  void selectServer(String? id) {
    if (id == null) return;
    selectedJenkinsServerId.value = id;
    final server = selectedServer;
    if (server == null) return;
    jenkinsServerNameTextController.text = server.name;
    jenkinsUrlController.text = server.jenkinsUrl;
    jenkinsUserNameTextController.text = server.jenkinsUsername;
    jenkinsPasswordTextController.text = server.jenkinsPassword;
  }

  void upsertSelectedServerFromInputs() {
    final current = selectedServer;
    final nameInput = jenkinsServerNameTextController.text.trim();
    final url = jenkinsUrlController.text.trim();
    String host = '';
    try {
      host = Uri.parse(url).host.trim();
    } catch (_) {
      host = '';
    }
    final name = nameInput.isEmpty ? (host.isEmpty ? url : host) : nameInput;
    final username = jenkinsUserNameTextController.text.trim();
    final password = jenkinsPasswordTextController.text;

    if (current == null) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final newServer = JenkinsServerConfig(
        id: id,
        name: name,
        jenkinsUrl: url,
        jenkinsUsername: username,
        jenkinsPassword: password,
      );
      jenkinsServers.add(newServer);
      selectedJenkinsServerId.value = id;
    } else {
      final idx = jenkinsServers.indexWhere((e) => e.id == current.id);
      if (idx >= 0) {
        jenkinsServers[idx] = current.copyWith(
          name: name,
          jenkinsUrl: url,
          jenkinsUsername: username,
          jenkinsPassword: password,
        );
      }
    }
  }

  void addServer() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newServer = JenkinsServerConfig(
      id: id,
      name: '',
      jenkinsUrl: '',
      jenkinsUsername: '',
      jenkinsPassword: '',
    );
    jenkinsServers.add(newServer);
    selectServer(id);
  }

//   // RSA公钥（PEM格式）
//   final String publicKeyPem = '''
// -----BEGIN PUBLIC KEY-----
// MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCZekIVXO6fY/4Ds/V3G9k/A/wBnSLdZNrhVh7QrLLMyMoJcQSRJP3SxIvQ7zm/1hTb5YXHTDgi6SWbK/293taX0liqtVZP5cJQ4bYQVTMoxn6wFrqgb+DVRuRUqnIlgXos1HZbYonQ5fNexuSzGaBw2yTJDbhNg5ZeXy0YUU3SaQIDAQAB
// -----END PUBLIC KEY-----
// ''';

  login() async {
    _normalizeLoginInputs();

    final gmallUrl = _normalizeSingleLineValue(gmallUrlController.text);
    final gmallKey = _normalizeSingleLineValue(gmallKeyController.text);
    final userName = _normalizeSingleLineValue(userNameTextController.text);
    final password = _normalizeSingleLineValue(passwordTextController.text);
    if (gmallUrl.isEmpty) {
      showErrorToast('请输入 Gmall 请求地址');
      return;
    }
    // 验证URL格式
    if (!_isValidUrl(gmallUrl)) {
      showErrorToast('Gmall 请求地址格式不正确');
      return;
    }

    if (gmallKey.isEmpty) {
      showErrorToast('请输入 Gmall 密钥');
      return;
    }

    if (userName.isEmpty) {
      showErrorToast('请输入 Gmall 用户名');
      return;
    }
    if (password.isEmpty) {
      showErrorToast('请输入 Gmall 密码');
      return;
    }

    // Jenkins 多服务器：必须先配置服务器
    if (jenkinsServers.isEmpty) {
      showErrorToast('请先配置服务器');
      return;
    }
    // 把当前输入同步回选中服务器（避免用户改了字段但没保存）
    upsertSelectedServerFromInputs();
    final server = selectedServer;
    if (server == null) {
      showErrorToast('请先配置服务器');
      return;
    }
    final jenkinsUrl = _normalizeSingleLineValue(server.jenkinsUrl);
    final jenkinsUserName = _normalizeSingleLineValue(server.jenkinsUsername);
    final jenkinsPassword = _normalizeSingleLineValue(server.jenkinsPassword);
    if (jenkinsUrl.isEmpty) {
      showErrorToast('请输入 Jenkins 请求地址');
      return;
    }
    // 验证Jenkins URL格式
    if (!_isValidUrl(jenkinsUrl)) {
      showErrorToast('Jenkins 请求地址格式不正确');
      return;
    }
    if (jenkinsUserName.isEmpty) {
      showErrorToast('请输入 Jenkins 用户名');
      return;
    }
    if (jenkinsPassword.isEmpty) {
      showErrorToast('请输入 Jenkins 密码');
      return;
    }

    final loginConfig = LoginConfig(
      environmentConfig: EnvironmentConfig(
        gmallUrl: gmallUrl,
        gmallKey: gmallKey,
        jenkinsUrl: jenkinsUrl,
      ),
      gmallUsername: userName,
      gmallPassword: password,
      jenkinsUsername: jenkinsUserName,
      jenkinsPassword: jenkinsPassword,
      jenkinsServers: jenkinsServers.toList(),
      selectedJenkinsServerId: selectedJenkinsServerId.value,
    );
    SharedPreferences sp = await SharedPreferences.getInstance();
    await sp.setString(
      curEnv.value.toString(),
      jsonEncode(loginConfig.toJson()),
    );
    await _saveSharedJenkinsSnapshot(
      servers: jenkinsServers.toList(),
      selectedId: selectedJenkinsServerId.value,
    );

    JenkinsApi jenkinsApi = JenkinsApi(
      jenkinsUrl: jenkinsUrl,
      jenkinsUserName: jenkinsUserName,
      jenkinsPassword: jenkinsPassword,
    );
    global.jenkinsApi = jenkinsApi;

    final publicKeyPem = '''
-----BEGIN PUBLIC KEY-----
$gmallKey
-----END PUBLIC KEY-----
''';

    // 执行加密
    final encryptedPassword = await encryptRSA(password, publicKeyPem);
    global.gmallUrl = gmallUrl;
    global.currentEnvironment = curEnv.value; // 设置当前环境
    await loginGmall(userName, encryptedPassword);

    bool isLogin = await jenkinsApi.verifyLogin();
    if (!isLogin) {
      throw 'Jenkins 账户登录失败';
    }

    Get.offAllNamed(Routes.HOME);
  }

  /// 进行登录
  Future<void> loginGmall(String gmallUserName, String gmallPassword) async {
    final res = await global.postData(path: '/login/portalLogin', data: {
      'username': gmallUserName,
      'password': gmallPassword,
    });
    final token = JSON(res)['token'].string;
    if (token == null) {
      throw 'Gmall 账户登录失败\nURL: ${global.gmallUrl}/login/portalLogin';
    }
    // 使用setToken方法设置token和过期时间
    global.setToken(token);
  }

  /// 初始化本地登录信息
  initLocalLoginInfo(Environment environment) async {
    SmartDialog.showLoading();
    try {
      final sp = await SharedPreferences.getInstance();

      /// 从本地获取登录配置
      final loginConfigStr = sp.getString(environment.toString());
      final shared = await _loadSharedJenkinsSnapshot();
      if (loginConfigStr != null) {
        final loginConfig = LoginConfig.fromJson(
          _decodeStoredJson(
            loginConfigStr,
            storageKey: environment.toString(),
          ),
        );
        gmallUrlController.text = loginConfig.environmentConfig.gmallUrl;
        gmallKeyController.text = loginConfig.environmentConfig.gmallKey;
        userNameTextController.text = loginConfig.gmallUsername;
        passwordTextController.text = loginConfig.gmallPassword;

        final envServers = loginConfig.jenkinsServers;
        final envSelected = loginConfig.selectedJenkinsServerId;
        final useServers = envServers.isNotEmpty ? envServers : shared.servers;
        final useSelected = envSelected ??
            shared.selectedId ??
            (useServers.isNotEmpty ? useServers.first.id : null);

        jenkinsServers.assignAll(useServers);
        selectedJenkinsServerId.value = useSelected;

        // 迁移后立刻把选中服务器的字段回填到输入框
        final server = selectedServer ??
            (jenkinsServers.isNotEmpty ? jenkinsServers.first : null);
        if (server != null) {
          selectedJenkinsServerId.value = server.id;
          jenkinsServerNameTextController.text = server.name;
          jenkinsUrlController.text = server.jenkinsUrl;
          jenkinsUserNameTextController.text = server.jenkinsUsername;
          jenkinsPasswordTextController.text = server.jenkinsPassword;

          // 如果是迁移出来的配置，这里顺手写回新结构，避免下次还要走迁移逻辑
          final migrated = LoginConfig(
            environmentConfig: loginConfig.environmentConfig,
            gmallUsername: loginConfig.gmallUsername,
            gmallPassword: loginConfig.gmallPassword,
            jenkinsUsername: loginConfig.jenkinsUsername,
            jenkinsPassword: loginConfig.jenkinsPassword,
            jenkinsServers: jenkinsServers.toList(),
            selectedJenkinsServerId: selectedJenkinsServerId.value,
          );
          await sp.setString(
            environment.toString(),
            jsonEncode(migrated.toJson()),
          );
          await _saveSharedJenkinsSnapshot(
            servers: jenkinsServers.toList(),
            selectedId: selectedJenkinsServerId.value,
          );
        } else {
          jenkinsServerNameTextController.clear();
          jenkinsUrlController.clear();
          jenkinsUserNameTextController.clear();
          jenkinsPasswordTextController.clear();
        }
      } else {
        gmallKeyController.clear();
        gmallUrlController.clear();
        jenkinsUrlController.clear();
        userNameTextController.clear();
        passwordTextController.clear();
        jenkinsUserNameTextController.clear();
        jenkinsPasswordTextController.clear();
        jenkinsServerNameTextController.clear();
        jenkinsServers.clear();
        selectedJenkinsServerId.value = null;
      }
    } on FormatException catch (e) {
      final sp = await SharedPreferences.getInstance();
      await _clearStoredConfig(sp, environment);
      _resetLoginInputs();
      showErrorToast('检测到本地配置已损坏，已自动清空，请重新填写配置。\n$e');
    } catch (e, stackTrace) {
      // 这里不要让 loading 卡死；同时给出可排查的错误信息
      print('初始化本地登录信息失败: $e');
      print(stackTrace);
      showErrorToast('读取本地配置失败，请重试或清理本地配置后再打开：$e');
    } finally {
      SmartDialog.dismiss();
    }
  }

  /// 仅存储共享的 Jenkins 配置（测试/生产共用）
  Future<void> _saveSharedJenkinsSnapshot({
    required List<JenkinsServerConfig> servers,
    required String? selectedId,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final data = {
      'jenkinsServers': servers.map((e) => e.toJson()).toList(),
      'selectedJenkinsServerId': selectedId,
    };
    await sp.setString(_sharedJenkinsKey, jsonEncode(data));
  }

  /// 读取共享 Jenkins 配置
  Future<_SharedJenkinsConfig> _loadSharedJenkinsSnapshot() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_sharedJenkinsKey);
    if (raw == null) return _SharedJenkinsConfig.empty();
    try {
      final json = _decodeStoredJson(
        raw,
        storageKey: _sharedJenkinsKey,
      );
      final rawServers = json['jenkinsServers'];
      List<JenkinsServerConfig> servers = [];
      if (rawServers is List) {
        servers = rawServers
            .whereType<Map>()
            .map((e) =>
                JenkinsServerConfig.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.id.trim().isNotEmpty)
            .toList();
      }
      final selectedId =
          (json['selectedJenkinsServerId'] as String?)?.toString();
      final normalizedSelected =
          (selectedId != null && servers.any((e) => e.id == selectedId))
              ? selectedId
              : (servers.isNotEmpty ? servers.first.id : null);
      return _SharedJenkinsConfig(
          servers: servers, selectedId: normalizedSelected);
    } on FormatException {
      await sp.remove(_sharedJenkinsKey);
      return _SharedJenkinsConfig.empty();
    } catch (_) {
      await sp.remove(_sharedJenkinsKey);
      return _SharedJenkinsConfig.empty();
    }
  }

  Future<void> _clearStoredConfig(
    SharedPreferences sp,
    Environment environment,
  ) async {
    await sp.remove(environment.toString());
    await sp.remove(_sharedJenkinsKey);
  }

  Map<String, dynamic> _decodeStoredJson(
    String raw, {
    required String storageKey,
  }) {
    final sanitized = _sanitizeStoredJson(raw);
    try {
      final decoded = jsonDecode(sanitized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw const FormatException('本地配置格式不正确，不是对象类型');
    } catch (e) {
      throw FormatException('本地配置解析失败（$storageKey）: $e');
    }
  }

  String _sanitizeStoredJson(String raw) {
    var value = raw.trim();
    if (value.isNotEmpty && value.codeUnitAt(0) == 0xFEFF) {
      value = value.substring(1);
    }

    final objectStart = value.indexOf('{');
    if (objectStart > 0) {
      value = value.substring(objectStart);
    }
    return value;
  }

  void _resetLoginInputs() {
    gmallKeyController.clear();
    gmallUrlController.clear();
    jenkinsUrlController.clear();
    userNameTextController.clear();
    passwordTextController.clear();
    jenkinsUserNameTextController.clear();
    jenkinsPasswordTextController.clear();
    jenkinsServerNameTextController.clear();
    jenkinsServers.clear();
    selectedJenkinsServerId.value = null;
  }

  /// 对外暴露：使用当前内存中的 Jenkins 配置写入共享存储
  Future<void> saveSharedJenkinsCurrent() async {
    await _saveSharedJenkinsSnapshot(
      servers: jenkinsServers.toList(),
      selectedId: selectedJenkinsServerId.value,
    );
  }

  /// 验证URL格式
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// 统一清理单行输入，兼容 Windows 粘贴时夹带的回车换行。
  String _normalizeSingleLineValue(String value) {
    return value.replaceAll(RegExp(r'[\r\n]+'), '').trim();
  }

  void _normalizeLoginInputs() {
    gmallUrlController.text =
        _normalizeSingleLineValue(gmallUrlController.text);
    gmallKeyController.text =
        _normalizeSingleLineValue(gmallKeyController.text);
    userNameTextController.text =
        _normalizeSingleLineValue(userNameTextController.text);
    passwordTextController.text =
        _normalizeSingleLineValue(passwordTextController.text);
    jenkinsServerNameTextController.text =
        _normalizeSingleLineValue(jenkinsServerNameTextController.text);
    jenkinsUrlController.text =
        _normalizeSingleLineValue(jenkinsUrlController.text);
    jenkinsUserNameTextController.text =
        _normalizeSingleLineValue(jenkinsUserNameTextController.text);
    jenkinsPasswordTextController.text =
        _normalizeSingleLineValue(jenkinsPasswordTextController.text);
  }
}

class _SharedJenkinsConfig {
  final List<JenkinsServerConfig> servers;
  final String? selectedId;
  const _SharedJenkinsConfig({
    required this.servers,
    required this.selectedId,
  });
  factory _SharedJenkinsConfig.empty() =>
      const _SharedJenkinsConfig(servers: [], selectedId: null);
}
