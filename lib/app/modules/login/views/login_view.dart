import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
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
                ListTile(
                  title: const Text('选择环境'),
                  subtitle: Obx(
                    () => SegmentedButton<Environment>(
                      segments: Environment.values.map((e) {
                        String environmentName = switch (e) {
                          Environment.test => '测试环境',
                          Environment.prod => '生产环境',
                        };
                        return ButtonSegment(
                            value: e, label: Text(environmentName));
                      }).toList(),
                      selected: {controller.curEnv.value},
                      onSelectionChanged: (value) {
                        controller.switchEnv(value.first);
                      },
                    ),
                  ),
                ),
                _buildListInput(
                  title: 'Gmall请求地址',
                  placeholder: '请输入请求地址',
                  controller: controller.gmallUrlController,
                ),
                _buildListInput(
                  title: 'Gmall密钥',
                  placeholder: '请输入密钥',
                  controller: controller.gmallKeyController,
                ),
                _buildListInput(
                  title: 'Jenkins请求地址',
                  placeholder: '请输入请求地址',
                  controller: controller.jenkinsUrlController,
                ),
                _buildListInput(
                  title: 'Gmall用户名',
                  placeholder: '请输入用户名',
                  controller: controller.userNameTextController,
                ),
                _buildListInput(
                  title: 'Gmall密码',
                  placeholder: '请输入密码',
                  controller: controller.passwordTextController,
                  isPassword: true,
                ),
                _buildListInput(
                  title: 'Jenkins用户名',
                  placeholder: '请输入用户名',
                  controller: controller.jenkinsUserNameTextController,
                ),
                _buildListInput(
                  title: 'Jenkins密码',
                  placeholder: '请输入密码',
                  controller: controller.jenkinsPasswordTextController,
                  isPassword: true,
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      SmartDialog.showLoading();
                      await controller.login();
                      SmartDialog.dismiss();
                    } catch (e) {
                      showErrorToast(e.toString());
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
