import 'package:get/get.dart';

import '../controllers/task_history_controller.dart';

class TaskHistoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<TaskHistoryController>(() => TaskHistoryController());
  }
}
