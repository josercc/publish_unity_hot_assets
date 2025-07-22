import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';

class HomeController extends GetxController {
  /// 支持的平台类型
  List<String> platformList = ['iOS', 'Android'];

  /// 当前选中的平台
  final curPlatform = 'iOS'.obs;

  /// 当前是否启用
  final curStatus = true.obs;

  /// 支持最低的版本列表
  final minVersionList = <String>[].obs;

  /// 当前选中最低的版本号
  final curMinVersion = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    Future.sync(() async {
      await loadMinVersion();
    });
  }

  /// 加载最低兼容版本
  Future<void> loadMinVersion() async {
    SmartDialog.showLoading();
    final versions = await global.post(
      path: '/api/platformservice/appManager/queryAppVersionList',
      data: {
        'client': curPlatform.value,
        'page': {
          'pageNo': 1,
          'pageSize': 1000,
          'status': 1,
        },
      },
    ).then((e) {
      final success = JSON(e.data)['success'].boolValue;
      final message = JSON(e.data)['message'].string ?? '未知错误';
      if (!success) {
        throw message;
      }
      final dataList = JSON(e.data)['data']['list'].listValue;
      return dataList.map((e) => JSON(e)['version'].stringValue).toList();
    }).catchError((e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
      throw e;
    });
    SmartDialog.dismiss();
    minVersionList.value = versions;
  }

  /// 切换平台
  Future<void> switchPlatform(String platform) async {
    curPlatform.value = platform;
    SmartDialog.showLoading();
    await loadMinVersion();
    SmartDialog.dismiss();
  }
}
