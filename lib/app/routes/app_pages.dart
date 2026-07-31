import 'package:get/get.dart';

import '../modules/app_packaging/bindings/app_packaging_binding.dart';
import '../modules/app_packaging/views/app_packaging_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/jenkins_servers/bindings/jenkins_servers_binding.dart';
import '../modules/jenkins_servers/views/jenkins_servers_view.dart';
import '../modules/jenkins_workspace/bindings/jenkins_workspace_binding.dart';
import '../modules/jenkins_workspace/views/jenkins_workspace_view.dart';
import '../modules/login/bindings/login_binding.dart';
import '../modules/login/views/login_view.dart';
import '../modules/task_history/bindings/task_history_binding.dart';
import '../modules/task_history/views/task_history_view.dart';
import '../modules/unity_first_package/bindings/unity_first_package_binding.dart';
import '../modules/unity_first_package/views/unity_first_package_view.dart';
import '../modules/unity_hot_update/bindings/unity_hot_update_binding.dart';
import '../modules/unity_hot_update/views/unity_hot_update_view.dart';
import '../modules/unity_import/bindings/unity_import_binding.dart';
import '../modules/unity_import/views/unity_import_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.LOGIN;

  static final routes = [
    GetPage(
      name: _Paths.HOME,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: _Paths.LOGIN,
      page: () => const LoginView(),
      binding: LoginBinding(),
    ),
    GetPage(
      name: _Paths.JENKINS_SERVERS,
      page: () => const JenkinsServersView(),
      binding: JenkinsServersBinding(),
    ),
    GetPage(
      name: _Paths.UNITY_IMPORT,
      page: () => const UnityImportView(),
      binding: UnityImportBinding(),
    ),
    GetPage(
      name: _Paths.UNITY_FIRST_PACKAGE,
      page: () => const UnityFirstPackageView(),
      binding: UnityFirstPackageBinding(),
    ),
    GetPage(
      name: _Paths.UNITY_HOT_UPDATE,
      page: () => const UnityHotUpdateView(),
      binding: UnityHotUpdateBinding(),
    ),
    GetPage(
      name: _Paths.APP_PACKAGING,
      page: () => const AppPackagingView(),
      binding: AppPackagingBinding(),
    ),
    GetPage(
      name: _Paths.JENKINS_WORKSPACE,
      page: () => const JenkinsWorkspaceView(),
      binding: JenkinsWorkspaceBinding(),
    ),
    GetPage(
      name: _Paths.TASK_HISTORY,
      page: () => const TaskHistoryView(),
      binding: TaskHistoryBinding(),
    ),
  ];
}
