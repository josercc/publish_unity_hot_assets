import 'dart:convert';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins_api.dart';
import 'package:publish_unity_hot_assets/app/common/legacy_prefs_store.dart';
import 'package:publish_unity_hot_assets/app/common/r_s_a_encryptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 从本地恢复 Gmall / Jenkins 业务会话（登录页已改为 Appwrite 鉴权）。
class BusinessSessionBootstrap {
  static const lastEnvironmentKey = 'last_environment';
  static const sharedJenkinsKey = 'shared_jenkins_servers';

  /// 尝试用本地保存的业务配置恢复 Gmall token 与 Jenkins API。
  /// 返回 true 表示至少 Jenkins 或 Gmall 之一恢复成功。
  static Future<bool> restore() async {
    final sp = await SharedPreferences.getInstance();
    await LegacyPrefsStore.migrateMissingKeys(sp);
    final env = await _resolveEnvironment(sp);
    return restoreFor(env, persistSelection: false);
  }

  /// 切换业务环境（测试 / 生产），并重新登录对应 Gmall 配置。
  /// 目标环境未配置时抛出 [GmallConfigMissingException]。
  static Future<void> switchEnvironment(Environment env) async {
    final sp = await SharedPreferences.getInstance();
    final loginConfig = await _loadLoginConfig(sp, env);
    if (!_hasCompleteGmall(loginConfig)) {
      throw GmallConfigMissingException(env);
    }

    final envLabel = env == Environment.prod ? '生产' : '测试';
    final ok = await restoreFor(env, persistSelection: true);
    if (!ok ||
        global.gmallUrl == null ||
        global.gmallUrl!.trim().isEmpty ||
        !global.isTokenValid()) {
      throw StateError('切换到${envLabel}环境失败：Gmall 登录未成功');
    }
  }

  /// 是否已完整配置指定环境的 Gmall。
  static Future<bool> isGmallConfigured(Environment env) async {
    final sp = await SharedPreferences.getInstance();
    final loginConfig = await _loadLoginConfig(sp, env);
    return _hasCompleteGmall(loginConfig);
  }

  /// 读取指定环境已保存的 Gmall 配置（可能字段为空）。
  static Future<GmallConfigDraft> loadGmallDraft(Environment env) async {
    final sp = await SharedPreferences.getInstance();
    final loginConfig = await _loadLoginConfig(sp, env);
    return GmallConfigDraft(
      gmallUrl: loginConfig?.environmentConfig.gmallUrl ?? '',
      gmallKey: loginConfig?.environmentConfig.gmallKey ?? '',
      username: loginConfig?.gmallUsername ?? '',
      password: loginConfig?.gmallPassword ?? '',
    );
  }

  /// 保存并校验 Gmall 配置：登录成功后写入本地并切换会话。
  static Future<void> saveAndValidateGmall({
    required Environment env,
    required String gmallUrl,
    required String gmallKey,
    required String username,
    required String password,
  }) async {
    final url = gmallUrl.trim();
    final key = gmallKey.trim();
    final user = username.trim();
    final pass = password;
    final envLabel = env == Environment.prod ? '生产' : '测试';

    if (url.isEmpty) throw StateError('请填写 Gmall 请求地址');
    if (key.isEmpty) throw StateError('请填写 Gmall 公钥');
    if (user.isEmpty) throw StateError('请填写 Gmall 用户名');
    if (pass.isEmpty) throw StateError('请填写 Gmall 密码');

    // 先用填写的配置尝试登录，校验正确性
    final previousUrl = global.gmallUrl;
    final previousToken = global.token;
    final previousExpire = global.tokenExpireTime;
    try {
      global.gmallUrl = url;
      global.token = null;
      global.tokenExpireTime = null;
      final publicKeyPem = '''
-----BEGIN PUBLIC KEY-----
$key
-----END PUBLIC KEY-----
''';
      final encryptedPassword = await encryptRSA(pass, publicKeyPem);
      final res = await global.postData(
        path: '/login/portalLogin',
        data: {
          'username': user,
          'password': encryptedPassword,
        },
      );
      final token = JSON(res)['token'].string;
      if (token == null || token.isEmpty) {
        throw StateError('Gmall 登录成功但未返回 token');
      }
      global.setToken(token);
    } catch (e) {
      // 校验失败则恢复原会话
      global.gmallUrl = previousUrl;
      global.token = previousToken;
      global.tokenExpireTime = previousExpire;
      throw StateError('$envLabel环境 Gmall 校验失败: $e');
    }

    // 校验通过后持久化，并完整恢复该环境会话（含 Jenkins）
    await _persistGmallConfig(
      env: env,
      gmallUrl: url,
      gmallKey: key,
      username: user,
      password: pass,
    );
    await spSetLastEnvironment(env);
    global.currentEnvironment = env;

    final ok = await restoreFor(env, persistSelection: true);
    if (!ok || !global.isTokenValid()) {
      throw StateError('配置已保存，但切换$envLabel环境会话失败');
    }
  }

  static Future<void> spSetLastEnvironment(Environment env) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(lastEnvironmentKey, env.toString());
  }

  static bool _hasCompleteGmall(LoginConfig? loginConfig) {
    if (loginConfig == null) return false;
    return loginConfig.environmentConfig.gmallUrl.trim().isNotEmpty &&
        loginConfig.environmentConfig.gmallKey.trim().isNotEmpty &&
        loginConfig.gmallUsername.trim().isNotEmpty &&
        loginConfig.gmallPassword.isNotEmpty;
  }

  static Future<void> _persistGmallConfig({
    required Environment env,
    required String gmallUrl,
    required String gmallKey,
    required String username,
    required String password,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final existing = await _loadLoginConfig(sp, env);
    final shared = await _loadSharedJenkins(sp);

    final servers = (existing?.jenkinsServers.isNotEmpty ?? false)
        ? existing!.jenkinsServers
        : shared.servers;
    final selectedId = existing?.selectedJenkinsServerId ??
        shared.selectedId ??
        (servers.isNotEmpty ? servers.first.id : null);

    JenkinsServerConfig? selected;
    if (selectedId != null) {
      try {
        selected = servers.firstWhere((e) => e.id == selectedId);
      } catch (_) {
        selected = servers.isNotEmpty ? servers.first : null;
      }
    } else if (servers.isNotEmpty) {
      selected = servers.first;
    }

    final loginConfig = LoginConfig(
      environmentConfig: EnvironmentConfig(
        gmallUrl: gmallUrl,
        gmallKey: gmallKey,
        jenkinsUrl: selected?.jenkinsUrl ??
            existing?.environmentConfig.jenkinsUrl ??
            '',
      ),
      gmallUsername: username,
      gmallPassword: password,
      jenkinsUsername:
          selected?.jenkinsUsername ?? existing?.jenkinsUsername ?? '',
      jenkinsPassword:
          selected?.jenkinsPassword ?? existing?.jenkinsPassword ?? '',
      jenkinsServers: servers,
      selectedJenkinsServerId: selectedId,
      isIntranetJenkinsMode: existing?.isIntranetJenkinsMode ?? true,
    );

    await sp.setString(env.toString(), jsonEncode(loginConfig.toJson()));
  }

  /// 按指定环境恢复会话；[persistSelection] 为 true 时写入 last_environment。
  static Future<bool> restoreFor(
    Environment env, {
    bool persistSelection = true,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await LegacyPrefsStore.migrateMissingKeys(sp);
    if (persistSelection) {
      await sp.setString(lastEnvironmentKey, env.toString());
    }
    global.currentEnvironment = env;

    final loginConfig = await _loadLoginConfig(sp, env);
    final shared = await _loadSharedJenkins(sp);

    final servers = (loginConfig?.jenkinsServers.isNotEmpty ?? false)
        ? loginConfig!.jenkinsServers
        : shared.servers;
    final selectedId = loginConfig?.selectedJenkinsServerId ??
        shared.selectedId ??
        (servers.isNotEmpty ? servers.first.id : null);

    JenkinsServerConfig? selected;
    if (selectedId != null) {
      try {
        selected = servers.firstWhere((e) => e.id == selectedId);
      } catch (_) {
        selected = servers.isNotEmpty ? servers.first : null;
      }
    } else if (servers.isNotEmpty) {
      selected = servers.first;
    }

    var restored = false;

    if (selected != null &&
        selected.jenkinsUrl.trim().isNotEmpty &&
        selected.jenkinsUsername.trim().isNotEmpty &&
        selected.jenkinsPassword.trim().isNotEmpty) {
      global.jenkinsApi = JenkinsApi(
        jenkinsUrl: selected.jenkinsUrl.trim(),
        jenkinsUserName: selected.jenkinsUsername.trim(),
        jenkinsPassword: selected.jenkinsPassword.trim(),
      );
      restored = true;
    }
    global.isIntranetJenkinsMode =
        loginConfig?.isIntranetJenkinsMode ?? true;

    // 切换环境前清空旧 Gmall 会话，避免串用
    global.gmallUrl = null;
    global.token = null;
    global.tokenExpireTime = null;

    if (loginConfig != null) {
      final gmallUrl = loginConfig.environmentConfig.gmallUrl.trim();
      final gmallKey = loginConfig.environmentConfig.gmallKey.trim();
      final gmallUser = loginConfig.gmallUsername.trim();
      final gmallPass = loginConfig.gmallPassword;
      if (gmallUrl.isNotEmpty &&
          gmallKey.isNotEmpty &&
          gmallUser.isNotEmpty &&
          gmallPass.isNotEmpty) {
        try {
          global.gmallUrl = gmallUrl;
          final publicKeyPem = '''
-----BEGIN PUBLIC KEY-----
$gmallKey
-----END PUBLIC KEY-----
''';
          final encryptedPassword = await encryptRSA(gmallPass, publicKeyPem);
          final res = await global.postData(
            path: '/login/portalLogin',
            data: {
              'username': gmallUser,
              'password': encryptedPassword,
            },
          );
          final token = JSON(res)['token'].string;
          if (token != null && token.isNotEmpty) {
            global.setToken(token);
            restored = true;
          }
        } catch (e) {
          print('恢复 Gmall 登录失败: $e');
        }
      }
    }

    return restored;
  }

  static Future<Environment> _resolveEnvironment(SharedPreferences sp) async {
    final raw = await LegacyPrefsStore.getString(sp, lastEnvironmentKey);
    if (raw == null || raw.isEmpty) return Environment.test;
    return Environment.values.firstWhere(
      (e) => e.toString() == raw,
      orElse: () => Environment.test,
    );
  }

  static Future<LoginConfig?> _loadLoginConfig(
    SharedPreferences sp,
    Environment env,
  ) async {
    final raw = await LegacyPrefsStore.getString(sp, env.toString());
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map<String, dynamic>) {
        return LoginConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return LoginConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      print('解析业务登录配置失败: $e');
    }
    return null;
  }

  static Future<({List<JenkinsServerConfig> servers, String? selectedId})>
      _loadSharedJenkins(SharedPreferences sp) async {
    final raw = await LegacyPrefsStore.getString(sp, sharedJenkinsKey);
    if (raw == null) {
      return (servers: <JenkinsServerConfig>[], selectedId: null);
    }
    try {
      final json = jsonDecode(raw.trim());
      if (json is! Map) {
        return (servers: <JenkinsServerConfig>[], selectedId: null);
      }
      final map = Map<String, dynamic>.from(json);
      final rawServers = map['jenkinsServers'];
      final servers = <JenkinsServerConfig>[];
      if (rawServers is List) {
        for (final e in rawServers.whereType<Map>()) {
          final server =
              JenkinsServerConfig.fromJson(Map<String, dynamic>.from(e));
          if (server.id.trim().isNotEmpty) {
            servers.add(server);
          }
        }
      }
      final selectedId = map['selectedJenkinsServerId']?.toString();
      final normalized = (selectedId != null &&
              servers.any((e) => e.id == selectedId))
          ? selectedId
          : (servers.isNotEmpty ? servers.first.id : null);
      return (servers: servers, selectedId: normalized);
    } catch (_) {
      return (servers: <JenkinsServerConfig>[], selectedId: null);
    }
  }
}

/// 指定环境缺少完整 Gmall 配置。
class GmallConfigMissingException implements Exception {
  final Environment environment;

  const GmallConfigMissingException(this.environment);

  String get environmentLabel =>
      environment == Environment.prod ? '生产' : '测试';

  @override
  String toString() => '未配置${environmentLabel}环境的 Gmall';
}

/// Gmall 配置草稿（用于表单回填）。
class GmallConfigDraft {
  final String gmallUrl;
  final String gmallKey;
  final String username;
  final String password;

  const GmallConfigDraft({
    required this.gmallUrl,
    required this.gmallKey,
    required this.username,
    required this.password,
  });
}
