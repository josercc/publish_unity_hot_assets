import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:quickalert/quickalert.dart';

Widget _buildAlertMessage(String msg) {
  return SizedBox(
    width: double.infinity,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Text(
          msg,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );
}

void showErrorToast(String msg) {
  QuickAlert.show(
    context: Get.context!,
    type: QuickAlertType.error,
    // title: msg,
    widget: _buildAlertMessage(msg),
  );
}

void showSuccessToast(String msg) {
  QuickAlert.show(
    context: Get.context!,
    type: QuickAlertType.success,
    // title: msg,
    widget: _buildAlertMessage(msg),
  );
}
