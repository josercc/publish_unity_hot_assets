import 'package:get/get.dart';

import '../controllers/log_viewer_controller.dart';

class LogViewerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LogViewerController>(() => LogViewerController());
  }
}
