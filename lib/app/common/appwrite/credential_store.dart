import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:shared_preferences/shared_preferences.dart';

/// 本地保存 Appwrite 登录账号；密码以 AES 密文存储。
class CredentialStore {
  static const _usernameKey = 'appwrite_login_username';
  static const _passwordCipherKey = 'appwrite_login_password_cipher';

  static final _aesKey =
      encrypt.Key.fromUtf8('publish_hot_assets_aes_key_v1!!!');
  static final _aesIv = encrypt.IV.fromUtf8('PuHaIV16Bytes!!!');

  Future<void> save({
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypter = encrypt.Encrypter(encrypt.AES(_aesKey));
    final cipher = encrypter.encrypt(password, iv: _aesIv).base64;
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_passwordCipherKey, cipher);
  }

  Future<SavedCredentials?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_usernameKey);
    final cipher = prefs.getString(_passwordCipherKey);
    if (username == null || username.isEmpty || cipher == null || cipher.isEmpty) {
      return null;
    }
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_aesKey));
      final password = encrypter.decrypt64(cipher, iv: _aesIv);
      return SavedCredentials(username: username, password: password);
    } catch (_) {
      await prefs.remove(_passwordCipherKey);
      return SavedCredentials(username: username, password: '');
    }
  }
}

class SavedCredentials {
  final String username;
  final String password;
  const SavedCredentials({
    required this.username,
    required this.password,
  });
}
