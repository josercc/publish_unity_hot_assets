/// Jenkins Active Choices 热更版本选项上的环境标签（由 Groovy 根据 API `tags` 写入）。
///
/// 约定前缀：`【生产】` / `【测试】`。提交 Jenkins 前必须剥离，避免污染真实 version。
abstract final class ReleaseChoiceTag {
  static const prodPrefix = '【生产】';
  static const testPrefix = '【测试】';

  static final _prefixPattern = RegExp(r'^【(?:生产|测试)】');

  /// 选项是否标记为生产 release。
  static bool isProd(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return false;
    return text.startsWith(prodPrefix);
  }

  /// 去掉环境前缀，得到 Jenkins / 流水线需要的版本字符串。
  static String strip(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return '';
    return text.replaceFirst(_prefixPattern, '').trim();
  }

  /// 用于下拉展示的短标签；无环境前缀时返回 null。
  static String? envLabel(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.startsWith(prodPrefix)) return '生产';
    if (text.startsWith(testPrefix)) return '测试';
    return null;
  }
}
