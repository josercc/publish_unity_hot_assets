import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_auth_service.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server_service.dart';
import 'package:publish_unity_hot_assets/app/common/business_session_bootstrap.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/updater/update_helper.dart';

import 'app/routes/app_pages.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // desktop_webview_window 独立标题栏进程入口
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  Get.put(GlobalServer());
  Get.put(AppwriteAuthService());
  Get.put(PackagingServerService());

  var initialRoute = Routes.LOGIN;
  try {
    final loggedIn = await appwriteAuth.hasValidSession();
    if (loggedIn) {
      final servers = await packagingServers.fetchActiveServers();
      if (servers.isNotEmpty) {
        await BusinessSessionBootstrap.restore();
        initialRoute = Routes.HOME;
      }
    }
  } catch (e) {
    print('启动时检查 Appwrite 会话失败: $e');
    initialRoute = Routes.LOGIN;
  }

  runApp(
    GetMaterialApp(
      title: "Application",
      initialRoute: initialRoute,
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
