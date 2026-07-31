import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/widgets/jenkins_job_params_form.dart';
import 'package:publish_unity_hot_assets/app/modules/home/datas/task.dart';
import 'package:quickalert/quickalert.dart';

import '../controllers/unity_hot_update_controller.dart';

class UnityHotUpdateView extends GetView<UnityHotUpdateController> {
  const UnityHotUpdateView({super.key});
  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.stopJobRunPolling();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Unity打热更'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '刷新当前参数',
              onPressed: controller.loadJenkinsJobParams,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        // 不用大外层 Obx 包住 JenkinsJobParamsForm，避免嵌套 Obx 导致
        //「执行任务」状态/按钮不刷新。
        body: Form(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: _buildTitle('当前环境'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Obx(
                        () => SegmentedButton<Environment>(
                          segments: const [
                            ButtonSegment(
                              value: Environment.test,
                              label: Text('测试'),
                              icon: Icon(Icons.science_outlined, size: 16),
                            ),
                            ButtonSegment(
                              value: Environment.prod,
                              label: Text('生产'),
                              icon: Icon(Icons.warning_amber, size: 16),
                            ),
                          ],
                          selected: {controller.curEnvironment.value},
                          onSelectionChanged:
                              controller.isSwitchingEnvironment.value
                                  ? null
                                  : (value) {
                                      controller.switchEnvironment(value.first);
                                    },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Obx(() {
                        final isProd =
                            controller.curEnvironment.value == Environment.prod;
                        final url = controller.gmallUrlDisplay.value;
                        final expanded = controller.isEnvConfigExpanded.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isProd
                                ? Colors.red.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isProd ? Colors.red : Colors.green,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isProd ? Icons.warning : Icons.check_circle,
                                color: isProd ? Colors.red : Colors.green,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  url.isEmpty
                                      ? (isProd
                                          ? '生产环境 · 请配置 Gmall'
                                          : '测试环境 · 请配置 Gmall')
                                      : (isProd
                                          ? '生产 Gmall：$url'
                                          : '测试 Gmall：$url'),
                                  style: TextStyle(
                                    color: isProd ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed:
                                    controller.isSwitchingEnvironment.value
                                        ? null
                                        : controller.toggleEnvConfigExpanded,
                                icon: Icon(
                                  expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                ),
                                label: Text(expanded ? '收起' : '展开配置'),
                              ),
                            ],
                          ),
                        );
                      }),
                      Obx(() {
                        if (!controller.isEnvConfigExpanded.value) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Gmall ${controller.curEnvironment.value == Environment.prod ? '生产' : '测试'}配置',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('请求地址'),
                                  const SizedBox(height: 4),
                                  CupertinoTextField(
                                    placeholder: '例如 https://xxx/api',
                                    controller: controller.gmallUrlController,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('公钥（不含 BEGIN/END 头尾）'),
                                  const SizedBox(height: 4),
                                  CupertinoTextField(
                                    placeholder: '请输入 Gmall 公钥',
                                    controller: controller.gmallKeyController,
                                    maxLines: 4,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('用户名'),
                                  const SizedBox(height: 4),
                                  CupertinoTextField(
                                    placeholder: '请输入用户名',
                                    controller: controller.gmallUserController,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('密码'),
                                  const SizedBox(height: 4),
                                  CupertinoTextField(
                                    placeholder: '请输入密码',
                                    controller:
                                        controller.gmallPasswordController,
                                    obscureText: true,
                                  ),
                                  const SizedBox(height: 12),
                                  Obx(
                                    () => FilledButton.icon(
                                      onPressed: controller
                                              .isSwitchingEnvironment.value
                                          ? null
                                          : controller.saveEnvironmentConfig,
                                      icon: controller
                                              .isSwitchingEnvironment.value
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.save, size: 18),
                                      label: const Text('保存并校验'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: JenkinsJobParamsForm(
                    controller: controller,
                    title: 'build_unity_hot_asset 参数',
                    hiddenParamNames: const {'tag', 'UID'},
                    shrinkWrap: true,
                  ),
                ),

                /// 是否跳过构建
                Obx(
                  () => ListTile(
                    title: const Text('是否跳过构建（针对于不需要构建的情况）'),
                    trailing: Switch(
                      value: controller.isSkipBuild.value,
                      onChanged: (value) {
                        controller.isSkipBuild.value = value;
                      },
                    ),
                  ),
                ),

                Obx(() {
                  if (!controller.isSkipBuild.value) {
                    return const SizedBox.shrink();
                  }
                  return ListTile(
                    title: _buildTitle('构建ID'),
                    subtitle: CupertinoTextField(
                      placeholder: '请输入Jenkins构建ID，用于下载对应产物',
                      controller: controller.buildIdController,
                      keyboardType: TextInputType.number,
                    ),
                  );
                }),

                /// 是否跳过下载
                Obx(
                  () => ListTile(
                    title: const Text('是否跳过下载（针对于不需要下载的情况）'),
                    trailing: Switch(
                      value: controller.isSkipDownload.value,
                      onChanged: (value) {
                        controller.isSkipDownload.value = value;
                      },
                    ),
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
                Obx(
                  () => ListTile(
                    title: const Text('是否强制上传'),
                    trailing: Switch(
                      value: controller.isForceUpload.value,
                      onChanged: (value) {
                        controller.isForceUpload.value = value;
                      },
                    ),
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
                          children: [
                            _buildStatusIcon(status),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                status.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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
                Obx(() {
                  final taskList = controller.taskList.toList();
                  return Column(
                    children: taskList.map((e) {
                      return ListTile(
                        title: Row(
                          children: [
                            Obx(() => _buildStatusIcon(e.status.value)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Obx(() {
                          var subtitleText = e.status.value.title;
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
                          return Text(subtitleText);
                        }),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
          ),
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

class PickMinVersionWidget extends GetWidget<UnityHotUpdateController> {
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
