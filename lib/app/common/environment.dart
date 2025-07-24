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

class LoginConfig {
  final String gmallUsername;
  final String gmallPassword;
  final String jenkinsUsername;
  final String jenkinsPassword;
  final EnvironmentConfig environmentConfig;
  const LoginConfig({
    required this.gmallUsername,
    required this.gmallPassword,
    required this.jenkinsUsername,
    required this.jenkinsPassword,
    required this.environmentConfig,
  });

  factory LoginConfig.fromJson(Map<String, dynamic> json) {
    return LoginConfig(
      environmentConfig: EnvironmentConfig.fromJson(json['environmentConfig']),
      gmallUsername: json['gmallUsername'],
      gmallPassword: json['gmallPassword'],
      jenkinsUsername: json['jenkinsUsername'],
      jenkinsPassword: json['jenkinsPassword'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gmallUsername': gmallUsername,
      'gmallPassword': gmallPassword,
      'jenkinsUsername': jenkinsUsername,
      'jenkinsPassword': jenkinsPassword,
      'environmentConfig': environmentConfig.toJson(),
    };
  }
}
