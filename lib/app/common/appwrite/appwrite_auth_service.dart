import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_config.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/credential_store.dart';

AppwriteAuthService get appwriteAuth => Get.find<AppwriteAuthService>();

class AppwriteAuthService extends GetxService {
  late final Client client;
  late final Account account;
  final CredentialStore credentialStore = CredentialStore();

  models.User? currentUser;

  @override
  void onInit() {
    super.onInit();
    client = Client()
      ..setEndpoint(AppwriteConfig.endpoint)
      ..setProject(AppwriteConfig.projectId)
      ..setSelfSigned(status: false);
    account = Account(client);
  }

  /// 供 dio 直连 Storage 下载用的鉴权头。
  ///
  /// Flutter 桌面端会话在 cookie jar 里，`getSession().secret` 通常为空，
  /// 只带 `X-Appwrite-Session` 会 401；须转发 SDK 的 Cookie。
  Future<Map<String, String>> storageDownloadHeaders(Uri downloadUri) async {
    final headers = <String, String>{
      'X-Appwrite-Project': AppwriteConfig.projectId,
    };

    try {
      // ClientIO.cookieJar（桌面端会话 cookie）；避免依赖 appwrite/src 实现导入。
      final jar = (client as dynamic).cookieJar;
      final cookies = await jar.loadForRequest(
        Uri(scheme: downloadUri.scheme, host: downloadUri.host),
      ) as List<dynamic>;
      final cookieHeader = cookies
          .map((c) => '${c.name}=${c.value}')
          .where((e) => e != '=')
          .join('; ');
      if (cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }
    } catch (e) {
      // ignore: avoid_print
      print('读取 Appwrite cookie 失败: $e');
    }

    final configured = client.config['session'];
    if (configured is String && configured.isNotEmpty) {
      headers['X-Appwrite-Session'] = configured;
    }

    return headers;
  }

  /// 查询当前 Appwrite 会话是否仍然有效。
  Future<bool> hasValidSession() async {
    try {
      final session = await account.getSession(sessionId: 'current');
      final expire = DateTime.tryParse(session.expire);
      if (expire != null && !expire.isAfter(DateTime.now())) {
        await logout();
        return false;
      }
      currentUser = await account.get();
      return true;
    } catch (_) {
      currentUser = null;
      return false;
    }
  }

  /// 使用邮箱/用户名 + 密码登录。
  /// 同账号已有有效会话则复用；否则先清掉残留会话再创建。
  Future<models.User> login({
    required String email,
    required String password,
  }) async {
    if (await hasValidSession()) {
      final existing = currentUser;
      final sameUser = existing != null &&
          (existing.email.toLowerCase() == email.toLowerCase() ||
              existing.name.toLowerCase() == email.toLowerCase());
      if (sameUser) {
        await credentialStore.save(username: email, password: password);
        return existing;
      }
      await logout();
    } else {
      // hasValidSession 为 false 时客户端仍可能残留 session cookie
      await logout();
    }

    try {
      await account.createEmailPasswordSession(
        email: email,
        password: password,
      );
    } on AppwriteException catch (e) {
      // 并发登录或残留会话：清掉后再试一次
      if (_isSessionAlreadyActive(e)) {
        await logout();
        await account.createEmailPasswordSession(
          email: email,
          password: password,
        );
      } else {
        rethrow;
      }
    }

    currentUser = await account.get();
    await credentialStore.save(username: email, password: password);
    return currentUser!;
  }

  bool _isSessionAlreadyActive(AppwriteException e) {
    final type = e.type ?? '';
    final message = (e.message ?? '').toLowerCase();
    return type == 'user_session_already_exists' ||
        message.contains('session is active') ||
        message.contains('session already');
  }

  /// 退出当前 Appwrite 会话（本地保存的用户名/密文密码保留）。
  Future<void> logout() async {
    try {
      await account.deleteSession(sessionId: 'current');
    } catch (_) {
      // 会话已失效时忽略
    }
    currentUser = null;
  }
}
