import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_auth_service.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server_service.dart';
import 'package:publish_unity_hot_assets/app/common/business_session_bootstrap.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/functions.dart';
import 'package:publish_unity_hot_assets/app/common/legacy_prefs_store.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginController extends GetxController {
  static const String _sharedJenkinsKey =
      BusinessSessionBootstrap.sharedJenkinsKey;

  final userNameTextController = TextEditingController();
  final passwordTextController = TextEditingController();
  final jenkinsUserNameTextController = TextEditingController();
  final jenkinsPasswordTextController = TextEditingController();
  final jenkinsServerNameTextController = TextEditingController();

  /// Gmall 请求地址（服务器配置页使用，登录页不再展示）
  TextEditingController gmallUrlController = TextEditingController();

  /// Gmall 密钥（服务器配置页使用，登录页不再展示）
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
    _loadSavedAppwriteCredentials();
    initLocalLoginInfo(curEnv.value);
  }

  @override
  void onClose() {
    userNameTextController.dispose();
    passwordTextController.dispose();
    jenkinsUserNameTextController.dispose();
    jenkinsPasswordTextController.dispose();
    jenkinsServerNameTextController.dispose();
    gmallUrlController.dispose();
    gmallKeyController.dispose();
    jenkinsUrlController.dispose();
    super.onClose();
  }

  Future<void> _loadSavedAppwriteCredentials() async {
    final saved = await appwriteAuth.credentialStore.load();
    if (saved == null) return;
    userNameTextController.text = saved.username;
    passwordTextController.text = saved.password;
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

  /// Appwrite 登录；成功后查询激活的打包服务器，有则进入首页。
  Future<void> login() async {
    _normalizeLoginInputs();

    final userName = _normalizeSingleLineValue(userNameTextController.text);
    final password = _normalizeSingleLineValue(passwordTextController.text);

    if (userName.isEmpty) {
      showErrorToast('请输入用户名');
      return;
    }
    if (password.isEmpty) {
      showErrorToast('请输入密码');
      return;
    }

    try {
      await appwriteAuth.login(email: userName, password: password);
    } on AppwriteException catch (e, stackTrace) {
      // ignore: avoid_print
      print('[Login] AppwriteException: ${e.message ?? e}\n$stackTrace');
      rethrow;
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[Login] $e\n$stackTrace');
      rethrow;
    }

    final activeServers = await packagingServers.fetchActiveServers();
    if (activeServers.isEmpty) {
      throw '当前无可用打包服务器';
    }

    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      BusinessSessionBootstrap.lastEnvironmentKey,
      curEnv.value.toString(),
    );

    // 同步业务侧本地配置；Gmall 账号默认复用 Appwrite 登录账号
    await _persistBusinessConfigSnapshot(
      appwriteUsername: userName,
      appwritePassword: password,
    );
    await BusinessSessionBootstrap.restore();

    Get.offAllNamed(Routes.HOME);
  }

  Future<void> _persistBusinessConfigSnapshot({
    required String appwriteUsername,
    required String appwritePassword,
  }) async {
    final gmallUrl = _normalizeSingleLineValue(gmallUrlController.text);
    final gmallKey = _normalizeSingleLineValue(gmallKeyController.text);
    final server = selectedServer;
    final jenkinsUrl =
        _normalizeSingleLineValue(server?.jenkinsUrl ?? jenkinsUrlController.text);
    final jenkinsUserName = _normalizeSingleLineValue(
        server?.jenkinsUsername ?? jenkinsUserNameTextController.text);
    final jenkinsPassword = _normalizeSingleLineValue(
        server?.jenkinsPassword ?? jenkinsPasswordTextController.text);

    final sp = await SharedPreferences.getInstance();
    await LegacyPrefsStore.migrateMissingKeys(sp);
    final existingRaw =
        await LegacyPrefsStore.getString(sp, curEnv.value.toString());
    LoginConfig? existing;
    if (existingRaw != null) {
      try {
        existing = LoginConfig.fromJson(
          _decodeStoredJson(
            existingRaw,
            storageKey: curEnv.value.toString(),
          ),
        );
      } catch (_) {}
    }

    final resolvedGmallUrl = gmallUrl.isNotEmpty
        ? gmallUrl
        : (existing?.environmentConfig.gmallUrl ?? '');
    final resolvedGmallKey = gmallKey.isNotEmpty
        ? gmallKey
        : (existing?.environmentConfig.gmallKey ?? '');

    // 没有任何业务配置时不覆盖写入
    if (resolvedGmallUrl.isEmpty &&
        resolvedGmallKey.isEmpty &&
        jenkinsServers.isEmpty &&
        jenkinsUrl.isEmpty &&
        (existing == null)) {
      return;
    }

    final existingGmallUser = existing?.gmallUsername.trim() ?? '';
    final existingGmallPass = existing?.gmallPassword ?? '';

    final loginConfig = LoginConfig(
      environmentConfig: EnvironmentConfig(
        gmallUrl: resolvedGmallUrl,
        gmallKey: resolvedGmallKey,
        jenkinsUrl: jenkinsUrl.isNotEmpty
            ? jenkinsUrl
            : (existing?.environmentConfig.jenkinsUrl ?? ''),
      ),
      gmallUsername:
          existingGmallUser.isNotEmpty ? existingGmallUser : appwriteUsername,
      gmallPassword:
          existingGmallPass.isNotEmpty ? existingGmallPass : appwritePassword,
      jenkinsUsername: jenkinsUserName,
      jenkinsPassword: jenkinsPassword,
      jenkinsServers: jenkinsServers.isNotEmpty
          ? jenkinsServers.toList()
          : (existing?.jenkinsServers ?? const []),
      selectedJenkinsServerId:
          selectedJenkinsServerId.value ?? existing?.selectedJenkinsServerId,
    );

    await sp.setString(
      curEnv.value.toString(),
      jsonEncode(loginConfig.toJson()),
    );
    await _saveSharedJenkinsSnapshot(
      servers: loginConfig.jenkinsServers,
      selectedId: loginConfig.selectedJenkinsServerId,
    );
  }

  /// 初始化本地登录信息（业务配置 + Jenkins）
  initLocalLoginInfo(Environment environment) async {
    SmartDialog.showLoading();
    try {
      final sp = await SharedPreferences.getInstance();
      await LegacyPrefsStore.migrateMissingKeys(sp);

      final loginConfigStr =
          await LegacyPrefsStore.getString(sp, environment.toString());
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

        final envServers = loginConfig.jenkinsServers;
        final envSelected = loginConfig.selectedJenkinsServerId;
        final useServers = envServers.isNotEmpty ? envServers : shared.servers;
        final useSelected = envSelected ??
            shared.selectedId ??
            (useServers.isNotEmpty ? useServers.first.id : null);

        jenkinsServers.assignAll(useServers);
        selectedJenkinsServerId.value = useSelected;

        final server = selectedServer ??
            (jenkinsServers.isNotEmpty ? jenkinsServers.first : null);
        if (server != null) {
          selectedJenkinsServerId.value = server.id;
          jenkinsServerNameTextController.text = server.name;
          jenkinsUrlController.text = server.jenkinsUrl;
          jenkinsUserNameTextController.text = server.jenkinsUsername;
          jenkinsPasswordTextController.text = server.jenkinsPassword;

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
      print('初始化本地登录信息失败: $e');
      print(stackTrace);
      showErrorToast('读取本地配置失败，请重试或清理本地配置后再打开：$e');
    } finally {
      SmartDialog.dismiss();
    }
  }

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

  Future<_SharedJenkinsConfig> _loadSharedJenkinsSnapshot() async {
    final sp = await SharedPreferences.getInstance();
    final raw = await LegacyPrefsStore.getString(sp, _sharedJenkinsKey);
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
    jenkinsUserNameTextController.clear();
    jenkinsPasswordTextController.clear();
    jenkinsServerNameTextController.clear();
    jenkinsServers.clear();
    selectedJenkinsServerId.value = null;
  }

  Future<void> saveSharedJenkinsCurrent() async {
    await _saveSharedJenkinsSnapshot(
      servers: jenkinsServers.toList(),
      selectedId: selectedJenkinsServerId.value,
    );
  }

  String _normalizeSingleLineValue(String value) {
    return value.replaceAll(RegExp(r'[\r\n]+'), '').trim();
  }

  void _normalizeLoginInputs() {
    userNameTextController.text =
        _normalizeSingleLineValue(userNameTextController.text);
    passwordTextController.text =
        _normalizeSingleLineValue(passwordTextController.text);
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
