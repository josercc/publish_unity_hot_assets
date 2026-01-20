import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/functions.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';

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
                // Jenkins 服务器选择：放在登录按钮前最后一项
                Obx(() {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('选择 Jenkins 服务器'),
                            subtitle: controller.jenkinsServers.isEmpty
                                ? const Text('未配置服务器，请先配置服务器')
                                : DropdownButton<String>(
                                    isExpanded: true,
                                    value: controller.selectedJenkinsServerId.value,
                                    items: controller.jenkinsServers
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e.id,
                                            child: Text(e.displayName),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (id) {
                                      controller.selectServer(id);
                                    },
                                  ),
                            trailing: TextButton(
                              onPressed: () {
                                Get.toNamed(Routes.JENKINS_SERVERS);
                              },
                              child: const Text('配置'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      SmartDialog.showLoading();

                      await controller.login();
                      SmartDialog.dismiss();
                    } catch (e) {
                      SmartDialog.dismiss();
                      if (e is DioException) {
                        // 显示包含URL信息的错误
                        final errorMessage = e.error?.toString() ??
                            e.response?.statusMessage ??
                            e.toString();
                        showErrorToast(errorMessage);
                      } else {
                        showErrorToast(e.toString());
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
