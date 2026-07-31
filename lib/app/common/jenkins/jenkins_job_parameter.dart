/// Jenkins Job 参数类型（用于 UI 组件选型）。
enum JenkinsParamWidgetType {
  choice,
  boolean,
  text,
  password,
  multiLine,
}

/// 从 Jenkins `parameterDefinitions` 解析出的参数定义。
class JenkinsJobParameter {
  final String name;
  final String description;
  final String typeClass;
  final JenkinsParamWidgetType widgetType;
  final List<String> choices;
  final dynamic defaultValue;

  /// Active Choices Reactive 依赖的其它参数名。
  final List<String> referencedParameters;

  const JenkinsJobParameter({
    required this.name,
    required this.description,
    required this.typeClass,
    required this.widgetType,
    this.choices = const [],
    this.defaultValue,
    this.referencedParameters = const [],
  });

  /// Active Choices / Cascade Choice（Groovy Script 动态选项）。
  bool get isActiveChoices {
    final lower = typeClass.toLowerCase();
    return lower.contains('unochoice') ||
        lower.contains('biouno') ||
        lower.contains('cascadechoice') ||
        (lower.contains('choiceparameter') &&
            !lower.contains('choiceparameterdefinition'));
  }

  factory JenkinsJobParameter.fromJson(Map<String, dynamic> json) {
    final typeClass = (json['_class'] ?? '').toString();
    final name = (json['name'] ?? '').toString();
    final description = (json['description'] ?? '').toString();
    final widgetType = _widgetTypeFor(typeClass);
    final choices = _parseChoices(json['choices']);
    final defaultValue =
        _parseDefault(json['defaultParameterValue'], widgetType);
    final referenced = _parseReferenced(json['referencedParameters']);

    return JenkinsJobParameter(
      name: name,
      description: description,
      typeClass: typeClass,
      widgetType: widgetType,
      choices: choices,
      defaultValue: defaultValue,
      referencedParameters: referenced,
    );
  }

  JenkinsJobParameter copyWith({
    List<String>? choices,
    dynamic defaultValue,
  }) {
    return JenkinsJobParameter(
      name: name,
      description: description,
      typeClass: typeClass,
      widgetType: widgetType,
      choices: choices ?? this.choices,
      defaultValue: defaultValue ?? this.defaultValue,
      referencedParameters: referencedParameters,
    );
  }

  dynamic get initialValue {
    if (defaultValue != null) return defaultValue;
    switch (widgetType) {
      case JenkinsParamWidgetType.boolean:
        return false;
      case JenkinsParamWidgetType.choice:
        return choices.isNotEmpty ? choices.first : '';
      case JenkinsParamWidgetType.text:
      case JenkinsParamWidgetType.password:
      case JenkinsParamWidgetType.multiLine:
        return '';
    }
  }

  static JenkinsParamWidgetType _widgetTypeFor(String typeClass) {
    final lower = typeClass.toLowerCase();
    if (lower.contains('boolean')) {
      return JenkinsParamWidgetType.boolean;
    }
    if (lower.contains('password')) {
      return JenkinsParamWidgetType.password;
    }
    if (lower.contains('textparameter') || lower.contains('multilinetext')) {
      return JenkinsParamWidgetType.multiLine;
    }
    // Active Choices / Cascade / 普通 Choice / Git Parameter 等
    if (lower.contains('choice') ||
        lower.contains('unochoice') ||
        lower.contains('gitparameter') ||
        lower.contains('editablechoice') ||
        lower.contains('extendedchoice')) {
      return JenkinsParamWidgetType.choice;
    }
    return JenkinsParamWidgetType.text;
  }

  static List<String> _parseChoices(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => _normalizeChoiceLabel(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    // Active Choices getChoices() 返回 Map<entry, display>
    if (raw is Map) {
      return raw.keys
          .map((e) => _normalizeChoiceLabel(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'[\r\n,]+'))
          .map((e) => _normalizeChoiceLabel(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static List<String> _parseReferenced(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// 去掉 Active Choices 的 `:selected` / `:disabled` 后缀。
  static String _normalizeChoiceLabel(dynamic raw) {
    var text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r':selected$', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r':disabled$', caseSensitive: false), '');
    return text.trim();
  }

  static dynamic _parseDefault(
    dynamic raw,
    JenkinsParamWidgetType widgetType,
  ) {
    if (raw is! Map) return null;
    final value = raw['value'];
    if (widgetType == JenkinsParamWidgetType.boolean) {
      if (value is bool) return value;
      if (value is String) {
        final lower = value.toLowerCase();
        return lower == 'true' || lower == '1' || lower == 'yes';
      }
      return value == true;
    }
    if (value == null) return null;
    return _normalizeChoiceLabel(value);
  }
}
