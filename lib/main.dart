import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/updater/update_helper.dart';

import 'app/routes/app_pages.dart';

void main() {
  Get.lazyPut(() => GlobalServer());
  runApp(
    GetMaterialApp(
      title: "Application",
      initialRoute: Routes.LOGIN,
      getPages: AppPages.routes,
      builder: FlutterSmartDialog.init(),
      theme: ThemeData(
        fontFamily: 'Barlow',
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Barlow'),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(fontFamily: 'Barlow'),
          labelStyle: TextStyle(fontFamily: 'Barlow'),
          helperStyle: TextStyle(fontFamily: 'Barlow'),
        ),
        snackBarTheme: const SnackBarThemeData(
          contentTextStyle: TextStyle(fontFamily: 'Barlow'),
        ),
      ),
    ),
  );

  // 应用启动后检查更新
  UpdateHelper.checkUpdateOnStartup();
}
