import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:asn1lib/asn1lib.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/r_s_a_encryptor.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';

class LoginController extends GetxController {
  final userNameTextController = TextEditingController();
  final passwordTextController = TextEditingController();

  // RSA公钥（PEM格式）
  final String publicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCZekIVXO6fY/4Ds/V3G9k/A/wBnSLdZNrhVh7QrLLMyMoJcQSRJP3SxIvQ7zm/1hTb5YXHTDgi6SWbK/293taX0liqtVZP5cJQ4bYQVTMoxn6wFrqgb+DVRuRUqnIlgXos1HZbYonQ5fNexuSzGaBw2yTJDbhNg5ZeXy0YUU3SaQIDAQAB
-----END PUBLIC KEY-----
''';

  login() async {
    final userName = userNameTextController.text;
    final password = passwordTextController.text;

    // 执行加密
    final encryptedPassword = await encryptRSA(password, publicKeyPem);
    if (userName.isEmpty || password.isEmpty) {
      Get.snackbar('提示', '用户名或密码不能为空');
      return;
    }
    final res = await global.post(path: '/login/portalLogin', data: {
      'username': userName,
      'password': encryptedPassword,
    });
    global.token = res.data['data']['token'];
    Get.offAllNamed(Routes.HOME);
  }
}
