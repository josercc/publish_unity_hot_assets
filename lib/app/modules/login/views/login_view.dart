import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/functions.dart';

import '../controllers/login_controller.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登陆页面'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Form(
            child: Column(
              children: [
                _buildListInput(
                  title: '用户名',
                  placeholder: '请输入用户名（邮箱）',
                  controller: controller.userNameTextController,
                ),
                _buildListInput(
                  title: '密码',
                  placeholder: '请输入密码',
                  controller: controller.passwordTextController,
                  isPassword: true,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      SmartDialog.showLoading();
                      await controller.login();
                      SmartDialog.dismiss();
                    } catch (e, stackTrace) {
                      SmartDialog.dismiss();
                      // ignore: avoid_print
                      print('[LoginError] $e\n$stackTrace');
                      if (e is AppwriteException) {
                        showErrorToast(e.message ?? e.toString());
                      } else {
                        showErrorToast('$e');
                      }
                    }
                  },
                  child: const Text('登陆'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListInput({
    required String title,
    required String placeholder,
    required TextEditingController controller,
    bool isPassword = false,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: CupertinoTextField(
        placeholder: placeholder,
        controller: controller,
        obscureText: isPassword,
      ),
    );
  }
}
