/// Appwrite 中的打包服务器文档。
class PackagingServer {
  final String id;
  final String url;
  final String userName;
  final String password;
  final bool active;
  final String tag;
  final bool online;

  const PackagingServer({
    required this.id,
    required this.url,
    required this.userName,
    required this.password,
    required this.active,
    required this.tag,
    required this.online,
  });

  /// `test` → 测试打包机；`release` → 生产打包机。
  String get displayName {
    switch (tag.trim().toLowerCase()) {
      case 'test':
        return '测试打包机';
      case 'release':
        return '生产打包机';
      default:
        final host = Uri.tryParse(url)?.host;
        if (host != null && host.isNotEmpty) return host;
        return tag.isNotEmpty ? tag : '打包机';
    }
  }

  /// 从文档 `url` 取 host，生成 ntfy topic（与 ip_ntfy_agent 一致）。
  String? get ntfyTopic {
    final host = Uri.tryParse(url)?.host.trim();
    if (host == null || host.isEmpty) return null;
    return 'topic_${host.replaceAll('.', '_')}';
  }

  factory PackagingServer.fromDocument(Map<String, dynamic> data, String id) {
    return PackagingServer(
      id: id,
      url: (data['url'] ?? '').toString().trim(),
      userName: (data['userName'] ?? '').toString().trim(),
      password: (data['password'] ?? '').toString(),
      active: data['active'] == true,
      tag: (data['tag'] ?? '').toString().trim(),
      online: data['online'] == true,
    );
  }
}
