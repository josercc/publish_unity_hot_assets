import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_historical_task.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_params_service.dart';
import 'package:publish_unity_hot_assets/app/modules/task_history/jenkins_task_history_args.dart';

class TaskHistoryController extends GetxController {
  final tasks = <JenkinsHistoricalTask>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  final _paramsService = JenkinsJobParamsService();

  String? jobNameFilter;
  PackagingServer? server;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is JenkinsTaskHistoryArgs) {
      jobNameFilter = args.jobName;
      server = args.server;
    } else if (args is String && args.isNotEmpty) {
      jobNameFilter = args;
    }
    loadHistory();
  }

  @override
  void onClose() {
    _paramsService.close();
    super.onClose();
  }

  String get title {
    final job = jobNameFilter;
    if (job == null || job.isEmpty) return '任务列表';
    final base = '${JenkinsHistoricalTask.jobTitleFor(job)} · 历史';
    final srv = server;
    if (srv == null) return base;
    return '$base · ${srv.displayName}';
  }

  Future<void> loadHistory() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final job = jobNameFilter?.trim() ?? '';
      final srv = server;
      if (job.isEmpty) {
        throw StateError('未指定 Job，无法查询打包机构建历史');
      }
      if (srv == null) {
        throw StateError('未指定打包机，无法查询构建历史');
      }
      final list = await _paramsService.fetchJobBuildHistory(
        jobName: job,
        server: srv,
        limit: 10,
      );
      tasks.assignAll(list);
    } catch (e) {
      errorMessage.value = e.toString();
      tasks.clear();
    } finally {
      isLoading.value = false;
    }
  }

  /// 把该任务参数带回任务页表单。
  void retryTask(JenkinsHistoricalTask task) {
    Get.back(result: Map<String, String>.from(task.parameters));
  }
}
