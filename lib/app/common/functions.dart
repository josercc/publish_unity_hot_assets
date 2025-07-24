import 'package:get/get.dart';
import 'package:quickalert/quickalert.dart';

void showErrorToast(String msg) {
  QuickAlert.show(
    context: Get.context!,
    type: QuickAlertType.error,
    title: msg,
  );
}

void showSuccessToast(String msg) {
  QuickAlert.show(
    context: Get.context!,
    type: QuickAlertType.success,
    title: msg,
  );
}
