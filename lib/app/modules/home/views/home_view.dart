import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/modules/home/datas/task.dart';
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';
import 'package:quickalert/quickalert.dart';

import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布Unity热更包'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              // 取消所有正在执行的任务
              controller.cancelAllTasks();
              Get.offAllNamed(Routes.LOGIN);
            },
            child: const Text('退出'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: Form(child: Obx(
            () {
              final taskList = controller.taskList;
              return Column(
                children: [
                  ListTile(
                    title: _buildTitle('当前环境'),
                    subtitle: Obx(
                      () {
                        String environmentName =
                            switch (controller.curEnvironment.value) {
                          Environment.test => '测试环境',
                          Environment.prod => '生产环境',
                        };
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: controller.curEnvironment.value ==
                                    Environment.prod
                                ? Colors.red.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: controller.curEnvironment.value ==
                                      Environment.prod
                                  ? Colors.red
                                  : Colors.green,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                controller.curEnvironment.value ==
                                        Environment.prod
                                    ? Icons.warning
                                    : Icons.check_circle,
                                color: controller.curEnvironment.value ==
                                        Environment.prod
                                    ? Colors.red
                                    : Colors.green,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                environmentName,
                                style: TextStyle(
                                  color: controller.curEnvironment.value ==
                                          Environment.prod
                                      ? Colors.red
                                      : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  ListTile(
                    title: _buildTitle('平台'),
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

                  ListTile(
                    title: const Text('打包配置'),
                    subtitle: Obx(
                      () => SegmentedButton(
                        segments: HotBuildConfiguration.values
                            .map((e) =>
                                ButtonSegment(value: e, label: Text(e.name)))
                            .toList(),
                        selected: {controller.curBuildConfiguration.value},
                        onSelectionChanged: (value) {
                          controller.curBuildConfiguration.value = value.first;
                          controller.updateLocalResourcePath();
                        },
                      ),
                    ),
                  ),

                  ListTile(
                    title: const Text('unity 分支'),
                    subtitle: Obx(
                      () => DropdownButtonFormField<String>(
                        value: controller.curUnityBranch.value.isEmpty
                            ? null
                            : controller.curUnityBranch.value,
                        decoration: const InputDecoration(
                          hintText: '请选择unity分支',
                          border: OutlineInputBorder(),
                        ),
                        items: controller.unityBranchList.map((String branch) {
                          return DropdownMenuItem<String>(
                            value: branch,
                            child: Text(branch),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            controller.selectUnityBranch(newValue);
                          }
                        },
                      ),
                    ),
                  ),

                  /// 是否跳过构建
                  ListTile(
                    title: const Text('是否跳过构建（针对于不需要构建的情况）'),
                    trailing: Switch(
                      value: controller.isSkipBuild.value,
                      onChanged: (value) {
                        controller.isSkipBuild.value = value;
                      },
                    ),
                  ),

                  /// 是否跳过下载
                  ListTile(
                    title: const Text('是否跳过下载（针对于不需要下载的情况）'),
                    trailing: Switch(
                      value: controller.isSkipDownload.value,
                      onChanged: (value) {
                        controller.isSkipDownload.value = value;
                      },
                    ),
                  ),

                  /// 本地资源路径地址
                  ListTile(
                    title: _buildTitle('本地资源路径地址'),
                    subtitle: CupertinoTextField(
                      placeholder: '请输入本地资源路径地址',
                      controller: controller.localResourcePathController,
                      readOnly: true,
                    ),
                  ),

                  /// 输入资源包更新描述
                  ListTile(
                    title: _buildTitle('资源包更新描述'),
                    subtitle: SizedBox(
                      height: 100,
                      child: CupertinoTextField(
                        placeholder: '请输入资源包更新描述',
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        controller: controller.descController,
                      ),
                    ),
                  ),

                  /// 发布时间
                  ListTile(
                    title: _buildTitle('发布时间'),
                    subtitle: Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            readOnly: true,
                            placeholder: '请输入发布日期',
                            controller: controller.dateController,
                            onTap: () {
                              _selectDate(context);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoTextField(
                            readOnly: true,
                            placeholder: '请输入发布时间',
                            controller: controller.timeController,
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
                    title: _buildTitle('发布状态'),
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
                    title: _buildTitle('版本号'),
                    subtitle: Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: '请输入版本号',
                            controller: controller.versionController,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => controller.autoFillVersion(),
                          child: const Text('自动填充'),
                        ),
                      ],
                    ),
                  ),

                  /// 最低兼容版本
                  ListTile(
                    title: _buildTitle('最低兼容版本'),
                    subtitle: Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: '请输入最低兼容版本',
                            controller: controller.minVersionController,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _pickMinVersion(context),
                          child: const Text('选择最低兼容版本'),
                        )
                      ],
                    ),
                  ),

                  /// 最高兼容版本
                  ListTile(
                    title: _buildTitle('最高兼容版本', isRequired: false),
                    subtitle: Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: '请输入最高兼容版本',
                            controller: controller.maxVersionController,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _pickMaxVersion(context),
                          child: const Text('选择最高兼容版本'),
                        )
                      ],
                    ),
                  ),

                  /// 是否强制上传
                  ListTile(
                    title: const Text('是否强制上传'),
                    trailing: Switch(
                      value: controller.isForceUpload.value,
                      onChanged: (value) {
                        controller.isForceUpload.value = value;
                      },
                    ),
                  ),

                  /// 发布
                  SizedBox(
                    width: double.infinity,
                    child: Obx(() {
                      final curTask = controller.curTask.value;
                      Widget title = const Text('发布');
                      if (curTask != null) {
                        title = Obx(() {
                          final status = curTask.status.value;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatusIcon(status),
                              Text(status.title)
                            ],
                          );
                        });
                      }
                      return ElevatedButton(
                        onPressed: curTask == null ? _publishHotVersion : null,
                        child: title,
                      );
                    }),
                  ),
                  ...taskList.map(
                    (e) {
                      // 如果是打包任务，显示构建号或UID信息
                      String subtitleText = e.status.value.title;
                      // PackResourceTask 定义在 home_controller.dart 中，通过导入可以访问
                      if (e is PackResourceTask) {
                        final packTask = e;
                        if (packTask.buildNumber != null) {
                          subtitleText =
                              '${e.status.value.title}\n构建号: ${packTask.buildNumber}';
                        } else if (packTask.waitingUid != null) {
                          subtitleText =
                              '${e.status.value.title}\n等待ID (UID: ${packTask.waitingUid})';
                        }
                      }

                      return ListTile(
                        title: Row(
                          children: [
                            /// access_time 等待
                            /// error 错误
                            /// timelapse 进行中
                            /// check_circle 成功
                            Obx(() {
                              return _buildStatusIcon(e.status.value);
                            }),
                            Text(e.name),
                          ],
                        ),
                        subtitle: Text(subtitleText),
                      );
                    },
                  )
                ],
              );
            },
          )),
        ),
      ),
    );
  }

  _publishHotVersion() async {
    try {
      final success =
          await controller.releaseHotUpdateVersionWithConfirmation();
      // 如果返回 false，说明用户取消了发布，不显示任何提示
      if (success) {
        QuickAlert.show(
          context: Get.context!,
          type: QuickAlertType.success,
          title: '发布成功',
        );
      }
      // 如果返回 false，什么都不做，静默取消
    } on ToastException catch (e) {
      QuickAlert.show(
        context: Get.context!,
        type: QuickAlertType.error,
        title: e.message,
      );
    } catch (e, s) {
      print(e.toString());
      print(s);
      QuickAlert.show(
        context: Get.context!,
        type: QuickAlertType.confirm,
        title: '发布失败，是否需要重新发布？',
        text: e.toString(),
        confirmBtnText: '重新发布',
        cancelBtnText: '取消',
        confirmBtnColor: Colors.green,
        barrierDismissible: false,
        onConfirmBtnTap: () {
          Get.back();
          _publishHotVersion();
        },
        onCancelBtnTap: () {
          // 取消当前任务
          controller.curTask.value?.cancel();
          Get.back();
        },
      ).then((e) {
        controller.curTask.value = null;
      });
    }
  }

  _pickMinVersion(BuildContext context) async {
    final result = await Get.bottomSheet<String>(
      const PickMinVersionWidget(),
    );
    controller.minVersionController.text = result ?? '';
  }

  /// 允许选择日期和时间
  Future<void> _selectDate(BuildContext context) async {
    final dataTime = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 1000)),
    );
    controller.setDate(dataTime);
  }

  Future<void> _selectTime(BuildContext context) async {
    final dataTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    controller.setTime(dataTime);
  }

  _pickMaxVersion(BuildContext context) async {
    final result = await Get.bottomSheet<String>(
      const PickMinVersionWidget(),
    );
    controller.maxVersionController.text = result ?? '';
  }

  /// 构建标题
  /// [data] 内容
  /// [isRequired] 是否必须字段
  Widget _buildTitle(String data, {bool isRequired = true}) {
    return Row(
      children: [
        Text(data),
        if (isRequired)
          const Text(
            '*',
            style: TextStyle(color: Colors.red),
          ),
      ],
    );
  }

  /// 根据状态返回对应图标
  Widget _buildStatusIcon(TaskStatus status) {
    switch (status.code) {
      case TaskStatusCode.waiting:
        return const Icon(
          Icons.access_time,
          color: Colors.grey,
        );
      case TaskStatusCode.error:
        return const Icon(
          Icons.error,
          color: Colors.red,
        );
      case TaskStatusCode.processing:
        return const Icon(
          Icons.timelapse,
          color: Colors.yellow,
        );
      case TaskStatusCode.success:
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
        );
      default:
        throw Exception('未知任务状态');
    }
  }

  // Widget _buildSe
}

class PickMinVersionWidget extends GetWidget<HomeController> {
  const PickMinVersionWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SizedBox(
        height: 500,
        child: Column(
          children: [
            const Text('最低兼容版本'),
            Expanded(
              child: ListView.builder(
                itemCount: controller.minVersionList.length,
                itemBuilder: (context, index) {
                  return Obx(
                    () => ListTile(
                      title: Text(controller.minVersionList[index]),
                      onTap: () {
                        Get.back(result: controller.minVersionList[index]);
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
