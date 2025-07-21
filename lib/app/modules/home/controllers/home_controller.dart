import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';

class HomeController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    global.post(
      path: '/api/platformservice/appManager/queryAppVersionList ',
      data: {
        'client': 'Android',
        'page': {
          'pageNo': 1,
          'pageSize': 1000,
          'status': 1,
        },
      },
    );
  }
}
