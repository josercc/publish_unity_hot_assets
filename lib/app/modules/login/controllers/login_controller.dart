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
  final userNameTextController = TextEditingController();
  final passwordTextController = TextEditingController();
  final jenkinsUserNameTextController = TextEditingController();
  final jenkinsPasswordTextController = TextEditingController();

  /// Gmall 请求地址
  TextEditingController gmallUrlController = TextEditingController();

  /// Gmall 密钥
  TextEditingController gmallKeyController = TextEditingController();

  /// Jenkins 请求地址
  TextEditingController jenkinsUrlController = TextEditingController();

  /// 当前环境
  final curEnv = Environment.test.obs;

  @override
  void onInit() {
    super.onInit();
    initLocalLoginInfo(curEnv.value);
  }

  switchEnv(Environment env) {
    curEnv.value = env;
    initLocalLoginInfo(curEnv.value);
  }

//   // RSA公钥（PEM格式）
//   final String publicKeyPem = '''
// -----BEGIN PUBLIC KEY-----
// MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCZekIVXO6fY/4Ds/V3G9k/A/wBnSLdZNrhVh7QrLLMyMoJcQSRJP3SxIvQ7zm/1hTb5YXHTDgi6SWbK/293taX0liqtVZP5cJQ4bYQVTMoxn6wFrqgb+DVRuRUqnIlgXos1HZbYonQ5fNexuSzGaBw2yTJDbhNg5ZeXy0YUU3SaQIDAQAB
// -----END PUBLIC KEY-----
// ''';

  login() async {
    final gmallUrl = gmallUrlController.text;
    final gmallKey = gmallKeyController.text;
    final jenkinsUrl = jenkinsUrlController.text;
    final userName = userNameTextController.text;
    final password = passwordTextController.text;
    final jenkinsUserName = jenkinsUserNameTextController.text;
    final jenkinsPassword = jenkinsPasswordTextController.text;
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

    if (jenkinsUrl.isEmpty) {
      showErrorToast('请输入 Jenkins 请求地址');
      return;
    }
    // 验证Jenkins URL格式
    if (!_isValidUrl(jenkinsUrl)) {
      showErrorToast('Jenkins 请求地址格式不正确');
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
    );
    SharedPreferences sp = await SharedPreferences.getInstance();
    await sp.setString(
      curEnv.value.toString(),
      jsonEncode(loginConfig.toJson()),
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
    global.token = token;
  }

  /// 初始化本地登录信息
  initLocalLoginInfo(Environment environment) async {
    SmartDialog.showLoading();
    SharedPreferences sp = await SharedPreferences.getInstance();

    /// 从本地获取登录配置
    String? loginConfigStr = sp.getString(environment.toString());
    if (loginConfigStr != null) {
      LoginConfig loginConfig =
          LoginConfig.fromJson(jsonDecode(loginConfigStr));
      gmallUrlController.text = loginConfig.environmentConfig.gmallUrl;
      gmallKeyController.text = loginConfig.environmentConfig.gmallKey;
      jenkinsUrlController.text = loginConfig.environmentConfig.jenkinsUrl;
      userNameTextController.text = loginConfig.gmallUsername;
      passwordTextController.text = loginConfig.gmallPassword;
      jenkinsUserNameTextController.text = loginConfig.jenkinsUsername;
      jenkinsPasswordTextController.text = loginConfig.jenkinsPassword;
    } else {
      gmallKeyController.clear();
      gmallUrlController.clear();
      jenkinsUrlController.clear();
      userNameTextController.clear();
      passwordTextController.clear();
      jenkinsUserNameTextController.clear();
      jenkinsPasswordTextController.clear();
    }
    SmartDialog.dismiss();
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
}
