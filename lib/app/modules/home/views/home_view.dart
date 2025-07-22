import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布Unity热更包'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: Form(
            child: Column(
              children: [
                ListTile(
                  title: const Text('平台'),
                  subtitle: Obx(
                    () => SegmentedButton(
                      segments: controller.platformList
                          .map((e) => ButtonSegment(value: e, label: Text(e)))
                          .toList(),
                      selected: {controller.curPlatform.value},
                      onSelectionChanged: (value) {
                        controller.switchPlatform(value.first);
                      },
                    ),
                  ),
                ),

                /// 输入资源包更新描述
                ListTile(
                  title: const Text('资源包更新描述'),
                  subtitle: SizedBox(
                    height: 100,
                    child: CupertinoTextField(
                      placeholder: '请输入资源包更新描述',
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                    ),
                  ),
                ),

                /// 发布时间
                ListTile(
                  title: const Text('发布时间'),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          readOnly: true,
                          decoration: const InputDecoration(
                            hintText: '请输入发布日期',
                          ),
                          onTap: () {
                            _selectDate(context);
                          },
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          readOnly: true,
                          decoration: const InputDecoration(
                            hintText: '请输入发布时间',
                          ),
                          onTap: () {
                            _selectTime(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                /// 状态 启动还是禁用
                ListTile(
                  title: const Text('发布状态'),
                  trailing: Obx(
                    () => Switch(
                      value: controller.curStatus.value,
                      onChanged: (value) {
                        controller.curStatus.value = value;
                      },
                    ),
                  ),
                ),

                /// 版本号
                ListTile(
                  title: const Text('版本号'),
                  subtitle: TextField(
                    decoration: const InputDecoration(
                      hintText: '请输入版本号',
                    ),
                  ),
                ),

                /// 最低兼容版本
                ListTile(
                  title: const Text('最低兼容版本'),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          placeholder: '请输入最低兼容版本',
                        ),
                      ),
                      ElevatedButton(
                          onPressed: () => _pickMinVersion(context),
                          child: Text('选择最低兼容版本'))
                    ],
                  ),
                ),

                /// 发布
                ElevatedButton(
                  child: const Text('发布'),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _pickMinVersion(BuildContext context) {
    Get.bottomSheet(
      PickMinVersionWidget(),
    );
  }

  /// 允许选择日期和时间
  void _selectDate(BuildContext context) {
    showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 1000)),
    );
  }

  void _selectTime(BuildContext context) {
    showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
  }
}

class PickMinVersionWidget extends GetWidget<HomeController> {
  const PickMinVersionWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        height: 300,
        child: Column(
          children: [
            Text('最低兼容版本'),
            Expanded(
              child: ListView.builder(
                itemCount: controller.minVersionList.length,
                itemBuilder: (context, index) {
                  return Obx(
                    () => RadioListTile(
                      title: Text(controller.minVersionList[index]),
                      value: controller.minVersionList[index],
                      groupValue: controller.curMinVersion.value,
                      onChanged: (value) {
                        controller.curMinVersion.value = value;
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
