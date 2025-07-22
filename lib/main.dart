import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';

import 'app/routes/app_pages.dart';

void main() {
  Get.lazyPut(() => GlobalServer());
  runApp(
    GetMaterialApp(
      title: "Application",
      initialRoute: Routes.LOGIN,
      getPages: AppPages.routes,
      builder: FlutterSmartDialog.init(),
    ),
  );
}
