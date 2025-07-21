import 'package:flutter/material.dart';

import 'package:get/get.dart';

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: '用户名',
                ),
                controller: controller.userNameTextController,
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: '密码',
                ),
                controller: controller.passwordTextController,
              ),
              ElevatedButton(
                onPressed: () {
                  controller.login();
                },
                child: const Text('登陆'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
