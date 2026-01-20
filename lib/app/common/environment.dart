enum Environment {
  test,
  prod;
}

class EnvironmentConfig {
  final String gmallUrl;
  final String gmallKey;
  final String jenkinsUrl;
  const EnvironmentConfig({
    required this.gmallUrl,
    required this.gmallKey,
    required this.jenkinsUrl,
  });

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      gmallUrl: json['gmallUrl'],
      gmallKey: json['gmallKey'],
      jenkinsUrl: json['jenkinsUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gmallUrl': gmallUrl,
      'gmallKey': gmallKey,
      'jenkinsUrl': jenkinsUrl,
    };
  }
}

class JenkinsServerConfig {
  /// 唯一ID（用于下拉选择/持久化选中项）
  final String id;

  /// 服务器名称（允许为空；为空时展示/使用 Jenkins URL 的 host 作为名称）
  final String name;

  /// Jenkins 请求地址
  final String jenkinsUrl;

  /// Jenkins 用户名
  final String jenkinsUsername;

  /// Jenkins 密码
  final String jenkinsPassword;

  const JenkinsServerConfig({
    required this.id,
    required this.name,
    required this.jenkinsUrl,
    required this.jenkinsUsername,
    required this.jenkinsPassword,
  });

  String get hostFromUrl {
    try {
      final host = Uri.parse(jenkinsUrl).host;
      return host.trim();
    } catch (_) {
      return '';
    }
  }

  /// 服务器名称为空时，回退为 Jenkins URL 的 host（解析不到则回退为 Jenkins URL）
  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final host = hostFromUrl;
    if (host.isNotEmpty) return host;
    return jenkinsUrl.trim();
  }

  factory JenkinsServerConfig.fromJson(Map<String, dynamic> json) {
    return JenkinsServerConfig(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      jenkinsUrl: (json['jenkinsUrl'] ?? '').toString(),
      jenkinsUsername: (json['jenkinsUsername'] ?? '').toString(),
      jenkinsPassword: (json['jenkinsPassword'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'jenkinsUrl': jenkinsUrl,
      'jenkinsUsername': jenkinsUsername,
      'jenkinsPassword': jenkinsPassword,
    };
  }

  JenkinsServerConfig copyWith({
    String? id,
    String? name,
    String? jenkinsUrl,
    String? jenkinsUsername,
    String? jenkinsPassword,
  }) {
    return JenkinsServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      jenkinsUrl: jenkinsUrl ?? this.jenkinsUrl,
      jenkinsUsername: jenkinsUsername ?? this.jenkinsUsername,
      jenkinsPassword: jenkinsPassword ?? this.jenkinsPassword,
    );
  }
}

class LoginConfig {
  final String gmallUsername;
  final String gmallPassword;
  final String jenkinsUsername;
  final String jenkinsPassword;
  final EnvironmentConfig environmentConfig;

  /// Jenkins 服务器列表（新结构）
  final List<JenkinsServerConfig> jenkinsServers;

  /// 当前选中的 Jenkins 服务器 ID
  final String? selectedJenkinsServerId;
  const LoginConfig({
    required this.gmallUsername,
    required this.gmallPassword,
    required this.jenkinsUsername,
    required this.jenkinsPassword,
    required this.environmentConfig,
    this.jenkinsServers = const [],
    this.selectedJenkinsServerId,
  });

  factory LoginConfig.fromJson(Map<String, dynamic> json) {
    final environmentConfig =
        EnvironmentConfig.fromJson((json['environmentConfig'] ?? {}) as Map<String, dynamic>);

    final legacyJenkinsUsername = (json['jenkinsUsername'] ?? '').toString();
    final legacyJenkinsPassword = (json['jenkinsPassword'] ?? '').toString();
    final legacyJenkinsUrl = environmentConfig.jenkinsUrl;

    final rawServers = json['jenkinsServers'];
    List<JenkinsServerConfig> servers = [];
    if (rawServers is List) {
      servers = rawServers
          .whereType<Map>()
          .map((e) => JenkinsServerConfig.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.trim().isNotEmpty)
          .toList();
    }

    // 旧配置迁移：如果没有 servers，则把旧的 Jenkins 配置转成默认新增的 1 台服务器
    if (servers.isEmpty &&
        (legacyJenkinsUrl.trim().isNotEmpty ||
            legacyJenkinsUsername.trim().isNotEmpty ||
            legacyJenkinsPassword.trim().isNotEmpty)) {
      String host = '';
      try {
        host = Uri.parse(legacyJenkinsUrl).host;
      } catch (_) {
        host = '';
      }
      final fallbackName = host.trim().isEmpty ? legacyJenkinsUrl : host;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      servers = [
        JenkinsServerConfig(
          id: id,
          name: fallbackName, // 服务器名称默认 host（或无法解析时用URL兜底）
          jenkinsUrl: legacyJenkinsUrl,
          jenkinsUsername: legacyJenkinsUsername,
          jenkinsPassword: legacyJenkinsPassword,
        ),
      ];
    }

    final selectedId = (json['selectedJenkinsServerId'] as String?)?.toString();
    final normalizedSelectedId =
        (selectedId != null && servers.any((e) => e.id == selectedId))
            ? selectedId
            : (servers.isNotEmpty ? servers.first.id : null);

    return LoginConfig(
      environmentConfig: environmentConfig,
      gmallUsername: (json['gmallUsername'] ?? '').toString(),
      gmallPassword: (json['gmallPassword'] ?? '').toString(),
      jenkinsUsername: legacyJenkinsUsername,
      jenkinsPassword: legacyJenkinsPassword,
      jenkinsServers: servers,
      selectedJenkinsServerId: normalizedSelectedId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gmallUsername': gmallUsername,
      'gmallPassword': gmallPassword,
      'jenkinsUsername': jenkinsUsername,
      'jenkinsPassword': jenkinsPassword,
      'environmentConfig': environmentConfig.toJson(),
      'jenkinsServers': jenkinsServers.map((e) => e.toJson()).toList(),
      'selectedJenkinsServerId': selectedJenkinsServerId,
    };
  }
}
