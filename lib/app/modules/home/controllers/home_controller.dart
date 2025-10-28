import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/modules/home/datas/task.dart';
import 'package:xml2json/xml2json.dart';
import 'package:crypto/crypto.dart' as crypto;

class HomeController extends GetxController {
  /// 支持的平台类型
  List<String> platformList = ['iOS', 'Android'];

  /// 当前选中的平台
  final curPlatform = 'iOS'.obs;

  /// 当前是否启用
  final curStatus = true.obs;

  /// 支持最低的版本列表
  final minVersionList = <String>[].obs;

  /// Unity分支列表
  final unityBranchList = <String>[].obs;

  /// 当前选中的Unity分支
  final curUnityBranch = ''.obs;

  ///资源包描述
  TextEditingController descController = TextEditingController();

  /// 发布日期
  TextEditingController dateController = TextEditingController();

  /// 发布时间
  TextEditingController timeController = TextEditingController();

  /// 版本号
  TextEditingController versionController = TextEditingController();

  /// 最低兼容版本
  TextEditingController minVersionController = TextEditingController();

  /// 最高兼容版本
  TextEditingController maxVersionController = TextEditingController();

  /// unity 分支
  TextEditingController unityBranchController = TextEditingController();

  /// 本地资源路径地址
  TextEditingController localResourcePathController = TextEditingController();

  /// 当前进行的任务列表
  final taskList = <Task>[].obs;

  /// 当前正在执行的任务
  final curTask = Rxn<Task>();

  /// 当前打包配置
  final curBuildConfiguration = HotBuildConfiguration.debug.obs;

  /// 是否跳过构建
  final isSkipBuild = false.obs;

  /// 是否跳过下载
  final isSkipDownload = false.obs;

  /// 是否强制上传
  final isForceUpload = false.obs;

  /// 当前环境
  final curEnvironment = Environment.test.obs;

  @override
  void onInit() {
    super.onInit();
    setDate(DateTime.now());
    setTime(TimeOfDay.now());
    _initializeData();
  }

  /// 初始化数据，带错误处理
  Future<void> _initializeData() async {
    try {
      await loadCurrentEnvironment();
    } catch (e) {
      print('加载当前环境失败: $e');
    }

    try {
      await loadUnityBranchList();
    } catch (e) {
      print('加载Unity分支列表失败: $e');
    }

    try {
      await updateLocalResourcePath();
    } catch (e) {
      print('更新本地资源路径失败: $e');
    }

    try {
      await loadMinVersion();
    } catch (e) {
      print('加载最低版本失败: $e');
    }
  }

  @override
  void onClose() {
    // 释放所有TextEditingController资源
    descController.dispose();
    dateController.dispose();
    timeController.dispose();
    versionController.dispose();
    minVersionController.dispose();
    maxVersionController.dispose();
    unityBranchController.dispose();
    localResourcePathController.dispose();
    super.onClose();
  }

  /// 加载当前环境
  Future<void> loadCurrentEnvironment() async {
    try {
      // 直接使用GlobalServer中存储的环境信息
      curEnvironment.value = global.currentEnvironment ?? Environment.test;
    } catch (e) {
      print('加载当前环境失败: $e');
      curEnvironment.value = Environment.test;
    }
  }

  /// 加载最低兼容版本
  Future<void> loadMinVersion() async {
    SmartDialog.showLoading();
    final versions = await global.post(
      path: '/api/platformservice/appManager/queryAppVersionList',
      data: {
        'client': curPlatform.value,
        'page': {
          'pageNo': 1,
          'pageSize': 1000,
          'status': 1,
        },
      },
    ).then((e) {
      final success = JSON(e.data)['success'].boolValue;
      final message = JSON(e.data)['message'].string ?? '未知错误';
      if (!success) {
        throw '查询应用版本列表失败\nURL: ${global.gmallUrl}/api/platformservice/appManager/queryAppVersionList\n错误: $message';
      }
      final dataList = JSON(e.data)['data']['list'].listValue;
      return dataList.map((e) => JSON(e)['version'].stringValue).toList();
    }).catchError((e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
      throw e;
    });
    SmartDialog.dismiss();
    minVersionList.value = versions;
  }

  /// 加载Unity分支列表
  Future<void> loadUnityBranchList() async {
    try {
      final branches = await global.jenkinsApi?.getBranchList() ?? [];
      unityBranchList.value = branches;
      if (branches.isNotEmpty && curUnityBranch.value.isEmpty) {
        curUnityBranch.value = branches.first;
        unityBranchController.text = branches.first;
      }
    } catch (e) {
      print('加载Unity分支列表失败: $e');
      SmartDialog.showToast('加载Unity分支列表失败: $e');
    }
  }

  /// 选择Unity分支
  void selectUnityBranch(String branch) {
    curUnityBranch.value = branch;
    unityBranchController.text = branch;
  }

  /// 切换平台
  Future<void> switchPlatform(String platform) async {
    curPlatform.value = platform;
    SmartDialog.showLoading();
    await loadMinVersion();
    await updateLocalResourcePath();
    SmartDialog.dismiss();
  }

  /// 更新本地地址
  Future<void> updateLocalResourcePath() async {
    final documentDir = await getApplicationDocumentsDirectory();

    final hotUpdateDir = join(
      documentDir.path,
      '.publish_unity_hot_assets',
      curPlatform.value,
      curBuildConfiguration.value.name,
    );
    localResourcePathController.text = hotUpdateDir;
  }

  /// 发布热更新版本（带确认弹框）
  Future<void> releaseHotUpdateVersionWithConfirmation() async {
    // 如果是生产环境，显示确认弹框
    if (curEnvironment.value == Environment.prod) {
      final confirmed = await _showProductionConfirmationDialog();
      if (!confirmed) {
        return; // 用户取消发布
      }
    }

    // 执行发布
    await releaseHotUpdateVersion();
  }

  /// 显示生产环境确认弹框
  Future<bool> _showProductionConfirmationDialog() async {
    return await Get.dialog<bool>(
          AlertDialog(
            title: const Text('⚠️ 生产环境发布确认'),
            content: const Text(
              '您即将发布到生产环境，此操作将影响线上用户。\n\n'
              '请确认以下信息：\n'
              '• 版本号是否正确\n'
              '• 资源包描述是否准确\n'
              '• 发布时间是否合适\n'
              '• 兼容版本范围是否正确\n\n'
              '确定要继续发布吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Get.back(result: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('确认发布'),
              ),
            ],
          ),
          barrierDismissible: false,
        ) ??
        false;
  }

  releaseHotUpdateVersion() async {
    final branch = unityBranchController.text;
    if (branch.isEmpty) {
      throw const ToastException('请输入unity分支');
    }
    final desc = descController.text;
    if (desc.isEmpty) {
      throw const ToastException('请输入资源包描述');
    }

    final date = dateController.text;
    if (date.isEmpty) {
      throw const ToastException('请输入发布日期');
    }

    final time = timeController.text;
    if (time.isEmpty) {
      throw const ToastException('请输入发布时间');
    }

    final version = versionController.text;
    if (version.isEmpty) {
      throw const ToastException('请输入版本号');
    }

    /// 版本号格式验证（支持多种格式）
    final versionReg = RegExp(r'^(v)?\d+\.\d+\.\d+$');
    if (!versionReg.hasMatch(version)) {
      throw const ToastException('版本号格式不正确，请使用 x.x.x 或 vx.x.x 格式');
    }

    final minVersion = minVersionController.text;
    if (minVersion.isEmpty) {
      throw const ToastException('请输入最低兼容版本');
    }

    final maxVersion = maxVersionController.text;
    if (maxVersion.isNotEmpty) {
      // 验证最高版本格式
      if (!versionReg.hasMatch(maxVersion)) {
        throw const ToastException('最高兼容版本格式不正确，请使用 x.x.x 或 vx.x.x 格式');
      }

      // 验证版本号大小关系
      final minVersionNum = _parseVersionNumber(minVersion);
      final maxVersionNum = _parseVersionNumber(maxVersion);
      if (minVersionNum >= maxVersionNum) {
        throw const ToastException('最低兼容版本必须小于最高兼容版本');
      }
    }

    int buildNumber;
    if (!isSkipBuild.value) {
      /// 打资源
      final packTask = PackResourceTask(
        platform: curPlatform.value,
        buildConfiguration: curBuildConfiguration.value.name,
        branch: branch,
      );
      taskList.value = [packTask];
      curTask.value = packTask;
      await packTask.execute();
      if (packTask.buildNumber == null) {
        throw Exception('构建号不能为空，构建任务未成功完成');
      }
      buildNumber = packTask.buildNumber!;
    } else {
      // 如果跳过构建，获取最后一个构建号
      final jenkinsApi = global.jenkinsApi;
      if (jenkinsApi == null) {
        throw Exception('Jenkins API 未初始化');
      }
      buildNumber = await jenkinsApi.getLastBuildNumber();
    }

    /// 下载资源
    final downloadTask = DownloadZipUrlTask(
      platform: curPlatform.value,
      buildConfiguration: curBuildConfiguration.value.name,
      isSkipDownload: isSkipDownload.value,
      buildNumber: buildNumber,
    );
    taskList.value = [downloadTask];
    curTask.value = downloadTask;
    final packPath = await downloadTask.execute();

    final patchXmlFile = File(join(packPath, 'Patch.xml'));
    if (!await patchXmlFile.exists()) {
      throw 'Patch.xml 文件不存在';
    }
    final patchBytesFile = File(join(packPath, 'Patch.bytes'));
    if (!await patchBytesFile.exists()) {
      throw 'Patch.bytes 文件不存在';
    }
    final assetBundleDir = Directory(join(packPath, 'AssetBundles'));
    if (!await assetBundleDir.exists()) {
      throw 'AssetBundles 目录不存在';
    }
    final patchXmlString = await patchXmlFile.readAsString();
    final xml2Json = Xml2Json();
    xml2Json.parse(patchXmlString);
    final patchJson = xml2Json.toOpenRally();
    final patchABList = JSON(patchJson)['Patch']['ABList']['PatchAB'].listValue;
    List<UploadResourceTask> uploadResTaskList = [
      UploadResourceTask(
        patchXmlFile,
        await patchXmlFile.length(),
        isForceUpload: isForceUpload.value,
      ),
      UploadResourceTask(
        patchBytesFile,
        await patchBytesFile.length(),
        isForceUpload: isForceUpload.value,
      ),
    ];
    List<UploadResourceTask> uploadABTaskList = [];
    final assetBundleFiles = assetBundleDir.listSync().whereType<File>();
    for (final file in assetBundleFiles) {
      final fileExtension = extension(file.path);
      if (fileExtension == '.bytes' || fileExtension == '.xml') {
        uploadABTaskList.add(UploadResourceTask(
          file,
          await file.length(),
          isForceUpload: isForceUpload.value,
        ));
      } else if (fileExtension == '.zip') {
        final fileName = basenameWithoutExtension(file.path);
        final md5s = patchABList
            .where((e) => JSON(e)['ABName'].string == fileName)
            .map((e) => JSON(e)['Md5'].string)
            .whereType<String>()
            .toList();
        print('fileName: $fileName md5s: $md5s');

        if (md5s.isEmpty) {
          throw 'Patch.xml 文件中没有 $fileName 的 md5 值';
        }
        uploadABTaskList.add(UploadResourceTask(
          file,
          await file.length(),
          md5: md5s.firstOrNull,
          isForceUpload: isForceUpload.value,
        ));
      } else {
        continue;
      }
    }
    taskList.addAll(uploadResTaskList);
    List<UploadResourceResonse> resInfo = [];
    for (final task in uploadResTaskList) {
      curTask.value = task;
      resInfo.add(await task.execute());
    }

    List<UploadResourceResonse> packageInfo = [];
    taskList.addAll(uploadABTaskList);
    for (final task in uploadABTaskList) {
      curTask.value = task;
      packageInfo.add(await task.execute());
    }

    final uploadHotVersionTask = ReleaseHotUpdateVersionTask(
      client: curPlatform.value,
      description: descController.text,
      highCompatibleVersion: maxVersionController.text,
      minCompatibleVersion: minVersionController.text,
      publishTime: '${dateController.text} ${timeController.text}',
      publishStatus: curStatus.value,
      version: versionController.text,
      resInfo: resInfo,
      packageInfo: packageInfo,
    );
    taskList.add(uploadHotVersionTask);
    curTask.value = uploadHotVersionTask;
    await uploadHotVersionTask.execute();
    curTask.value = null;
  }

  void setDate(DateTime? dataTime) {
    if (dataTime != null) {
      dateController.text = dataTime.toString().substring(0, 10);
    } else {
      dateController.text = '';
    }
  }

  void setTime(TimeOfDay? time) {
    if (time != null) {
      timeController.text = '${time.hour}:${time.minute}:00';
    } else {
      timeController.text = '';
    }
  }

  /// 解析版本号为数字，用于比较
  int _parseVersionNumber(String version) {
    // 移除可能的 'v' 前缀
    final cleanVersion = version.replaceFirst(RegExp(r'^v'), '');
    final parts = cleanVersion.split('.');
    if (parts.length != 3) return 0;

    try {
      final major = int.parse(parts[0]);
      final minor = int.parse(parts[1]);
      final patch = int.parse(parts[2]);
      return major * 10000 + minor * 100 + patch;
    } catch (e) {
      return 0;
    }
  }
}

/// 打包资源任务
class PackResourceTask extends Task<void> {
  final String platform;
  final String buildConfiguration;
  final String branch;
  int? buildNumber; // 构建号，在构建完成后设置

  PackResourceTask({
    required this.platform,
    required this.buildConfiguration,
    required this.branch,
  }) : super(name: '打包Unity 热更新资源');

  @override
  Future<void> execute() async {
    status.value =
        TaskStatus.fromCode(TaskStatusCode.processing, '正在打包Unity 热更新资源...');
    progressText.value = '正在打包Unity 热更新资源...';
    await pack().catchError((e) {
      status.value =
          TaskStatus.fromCode(TaskStatusCode.error, '打包失败:${e.toString()}');
      progressText.value = '打包失败:${e.toString()}';
      SmartDialog.showToast(e.toString());
      throw e;
    });
    status.value = TaskStatus.fromCode(TaskStatusCode.success, '打包成功');
  }

  /// 进行打包
  Future<void> pack() async {
    final jenkinsApi = global.jenkinsApi;
    if (jenkinsApi == null) {
      throw 'jenkinsApi 不能为空';
    }

    final lastBuildNumber = await jenkinsApi.getLastBuildNumber();
    print('当前最新构建号: $lastBuildNumber');

    status.value = TaskStatus.fromCode(
      TaskStatusCode.processing,
      '正在启动Jenkins构建...',
    );

    await jenkinsApi.startBuild(
      platform: platform,
      buildConfiguration: buildConfiguration,
      branch: branch,
    );

    final newBuildNumber = lastBuildNumber + 1;
    buildNumber = newBuildNumber; // 保存构建号
    print('新构建号: $newBuildNumber');

    status.value = TaskStatus.fromCode(
      TaskStatusCode.processing,
      '构建已启动（构建号: $newBuildNumber），正在等待Jenkins开始执行...',
    );

    // 等待Jenkins开始执行新构建
    await waitForBuildToStart(newBuildNumber);

    // 开始监控构建结果
    final result = await queryBuildResult(newBuildNumber);
    if (result) {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.success,
        '打包成功',
      );
    } else {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.error,
        '打包失败',
      );
      throw Exception('Jenkins构建失败，构建号: $newBuildNumber');
    }
  }

  /// 等待Jenkins开始执行新构建
  Future<void> waitForBuildToStart(int expectedBuildNumber) async {
    final jenkinsApi = global.jenkinsApi;
    if (jenkinsApi == null) {
      throw 'jenkinsApi 不能为空';
    }

    DateTime startTime = DateTime.now();
    int waitSeconds = 0;

    while (true) {
      try {
        final currentLastBuildNumber = await jenkinsApi.getLastBuildNumber();

        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          '等待Jenkins开始执行构建（期望: $expectedBuildNumber，当前最新: $currentLastBuildNumber）...已等待${waitSeconds}秒',
        );

        if (currentLastBuildNumber >= expectedBuildNumber) {
          print('Jenkins已开始执行构建 $expectedBuildNumber');
          status.value = TaskStatus.fromCode(
            TaskStatusCode.processing,
            'Jenkins已开始执行构建 $expectedBuildNumber，开始监控构建进度...',
          );
          return;
        }

        // 等待1秒后重试
        await Future.delayed(const Duration(seconds: 1));
        waitSeconds = DateTime.now().difference(startTime).inSeconds;
      } catch (e) {
        print('等待构建开始时发生错误: $e');
        // 如果获取构建号失败，继续等待
        await Future.delayed(const Duration(seconds: 1));
        waitSeconds = DateTime.now().difference(startTime).inSeconds;
      }
    }
  }

  /// 查询构建结果
  Future<bool> queryBuildResult(int buildNumber) async {
    Completer<bool> completer = Completer<bool>();
    DateTime startTime = DateTime.now();
    Timer? timer;

    // 设置超时时间（3小时，适合大型Unity项目）
    const timeoutSeconds = 10800; // 3小时
    const timeoutHours = 3;

    timer = Timer.periodic(const Duration(seconds: 3), (periodicTimer) async {
      try {
        final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;

        // 设置超时时间
        if (elapsedSeconds > timeoutSeconds) {
          timer?.cancel();
          status.value = TaskStatus.fromCode(
            TaskStatusCode.error,
            '查询构建结果超时（${timeoutHours}小时）',
          );
          completer.complete(false);
          return;
        }

        // 显示构建执行状态
        String statusMessage;
        if (elapsedSeconds < 60) {
          statusMessage =
              'Jenkins构建执行中（构建号: $buildNumber）...已等待${elapsedSeconds}秒';
        } else {
          statusMessage =
              'Jenkins构建执行中（构建号: $buildNumber）...已等待${(elapsedSeconds / 60).toStringAsFixed(1)}分钟';
        }

        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          statusMessage,
        );

        final result = await global.jenkinsApi?.queryBuildResult(
          buildNumber: buildNumber,
        );

        if (result == 'SUCCESS') {
          timer?.cancel();
          completer.complete(true);
        } else if (result == 'FAILURE') {
          timer?.cancel();
          completer.complete(false);
        }
        // 如果result为null或其他值，继续等待
      } catch (e) {
        timer?.cancel();
        status.value = TaskStatus.fromCode(
          TaskStatusCode.error,
          '查询构建结果失败: $e',
        );
        completer.complete(false);
      }
    });

    return completer.future;
  }
}

/// 上传资源任务
class UploadResourceTask extends Task<UploadResourceResonse> {
  /// 本地文件路径
  final File file;
  final String? md5;
  final int fileSize;
  final bool isForceUpload;

  UploadResourceTask(this.file, this.fileSize,
      {this.md5, this.isForceUpload = false})
      : super(
            name:
                '上传资源文件 ${basename(file.path)}(${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB)');

  @override
  Future<UploadResourceResonse> execute() async {
    /// 先查询当前文件是否已经上传过
    final md5 = this.md5 ?? await computeMd5();
    print(file.path);
    return _start(md5).then((e) {
      status.value = TaskStatus.fromCode(
          TaskStatusCode.success, '[$md5][${basename(file.path)}]上传成功');
      return e;
    }).catchError((e) {
      status.value = TaskStatus.fromCode(TaskStatusCode.error,
          '[$md5][${basename(file.path)}]上传失败:${e.toString()}');
      throw e;
    });
  }

  Future<UploadResourceResonse> _start(String md5) async {
    status.value = TaskStatus.fromCode(
        TaskStatusCode.processing, '[${basename(file.path)}]正在上传资源文件');
    final fileLength = await file.length();
    final fileName = basename(file.path);

    if (!isForceUpload) {
      final url = await queryNetworkImageUrl(md5);
      if (url != null) {
        return UploadResourceResonse(
          packageName: fileName,
          packageUrl: url,
          packageSize: fileLength,
          md5: md5,
        );
      }
    }

    final uploadId = await getUploadId(
      fileName: fileName,
      fileHash: md5,
      fileSize: fileLength,
    );

    int totalPartNumber = 0;
    const partSize = 1024 * 1024 * 10;
    final totalBytes = await file.readAsBytes();
    for (int i = 0; i < fileLength; i += partSize) {
      final partNumber = i ~/ partSize + 1;
      int count = i + partSize;
      int start = i;
      int end = min(count, fileLength);
      print('[$start-$end][$fileLength]');
      final partBytes = totalBytes.sublist(start, end);
      totalPartNumber = await uploadPartFile(
        uploadId: uploadId,
        partNumber: partNumber,
        bytes: partBytes,
        fileName: fileName,
      );
    }

    /// 合并切片
    final uploadUrl = await mergePartFile(
      uploadId: uploadId,
      partTotal: totalPartNumber,
    );
    return UploadResourceResonse(
      packageName: fileName,
      packageUrl: uploadUrl,
      packageSize: fileLength,
      md5: md5,
    );
  }

  /// 计算文件的 md5
  Future<String> computeMd5() async {
    print('正在计算${file.path}的 md5');
    try {
      final content = file.openRead();
      final digest = await crypto.md5.bind(content).first;
      // Stream会自动关闭，不需要手动调用close
      return digest.toString();
    } catch (e) {
      print('计算MD5失败: $e');
      rethrow;
    }
  }

  /// 根据 md5 查询网络图片地址
  Future<String?> queryNetworkImageUrl(String md5) async {
    final response = await global.post(
      path: '/api/platformservice/md5/find',
      data: {
        'md5': [md5],
      },
      onSendProgress: (p0, p1) {
        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          '[${p0 / p1 * 100}%]正在根据 md5 查询[${basename(file.path)}]是否上传过资源文件',
        );
      },
    );
    final success = JSON(response.data)['success'].boolValue;
    final message = JSON(response.data)['message'].string ?? '未知错误';
    if (!success) {
      throw '查询MD5失败\nURL: ${global.gmallUrl}/api/platformservice/md5/find\n错误: $message';
    }
    final data = JSON(response.data)['data'].listValue;
    return JSON(data)[0]['url'].string;
  }

  /// 获取切片上传的唯一 Id
  Future<String> getUploadId({
    required String fileName,
    required String fileHash,
    required int fileSize,
  }) async {
    final response = await global.post(
      path: '/api/platformservice/file/initiatePartFileUpload',
      data: {
        'fileName': fileName,
        'fileHash': fileHash,
        'fileSize': fileSize,
      },
      onSendProgress: (p0, p1) {
        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          '[${p0 / p1 * 100}%]正在获取切片上传的唯一 Id',
        );
      },
    );
    final success = JSON(response.data)['success'].boolValue;
    final message = JSON(response.data)['message'].string ?? '未知错误';
    if (!success) {
      throw '获取上传ID失败\nURL: ${global.gmallUrl}/api/platformservice/file/initiatePartFileUpload\n错误: $message';
    }
    final uploadId = JSON(response.data)['data']['uploadId'].string;
    if (uploadId == null) {
      throw '上传 Id 不能为空\nURL: ${global.gmallUrl}/api/platformservice/file/initiatePartFileUpload';
    }
    return uploadId;
  }

  /// 上传切片
  Future<int> uploadPartFile({
    required String uploadId,
    required int partNumber,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final response = await global.post(
      path: '/api/platformservice/file/uploadPart',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName, // 可选：指定切片文件名
        ),
        'partNumber': partNumber,
        'uploadId': uploadId,
      }),
      onSendProgress: (p0, p1) {
        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          '[${p0 / p1 * 100}%]正在上传切片$partNumber',
        );
      },
    );
    final success = JSON(response.data)['success'].boolValue;
    final message = JSON(response.data)['message'].string ?? '未知错误';
    if (!success) {
      throw '上传切片失败\nURL: ${global.gmallUrl}/api/platformservice/file/uploadPart\n错误: $message';
    }
    return JSON(response.data)['data']['totalPartNumber'].intValue;
  }

  /// 合并切片
  Future<String> mergePartFile({
    required String uploadId,
    required int partTotal,
  }) async {
    final response = await global.post(
      path: '/api/platformservice/file/completeUpload',
      data: {
        'uploadId': uploadId,
        'partTotal': partTotal,
      },
      onSendProgress: (p0, p1) {
        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          '[${p0 / p1 * 100}%]正在合并切片',
        );
      },
    );
    final success = JSON(response.data)['success'].boolValue;
    final message = JSON(response.data)['message'].string ?? '未知错误';
    if (!success) {
      throw '合并切片失败\nURL: ${global.gmallUrl}/api/platformservice/file/completeUpload\n错误: $message';
    }
    final url = JSON(response.data)['data']['fileUrl'].string;
    if (url == null) {
      throw '合并切片失败\nURL: ${global.gmallUrl}/api/platformservice/file/completeUpload';
    }
    return url;
  }
}

/// 下载 zip 包任务
class DownloadZipUrlTask extends Task<String> {
  final String platform;
  final String buildConfiguration;
  final bool isSkipDownload;
  final int buildNumber;

  DownloadZipUrlTask({
    required this.platform,
    required this.buildConfiguration,
    required this.isSkipDownload,
    required this.buildNumber,
  }) : super(name: '从 Jenkins 下载热更新资源 Zip 包');

  @override
  Future<String> execute() async {
    final documentDir = await getApplicationDocumentsDirectory();

    final hotUpdateDir = join(
      documentDir.path,
      '.publish_unity_hot_assets',
      platform,
      buildConfiguration,
    );
    print(hotUpdateDir);
    final zipPath = join(hotUpdateDir, 'hot_update.zip');
    final hotUpdateAssetDir = Directory(join(hotUpdateDir, 'Assets'));

    // 始终在下载前删除本地已存在的路径
    status.value = TaskStatus.fromCode(
      TaskStatusCode.processing,
      '正在清理本地已存在的资源路径...',
    );

    // 删除整个目录（包括zip包和所有子文件）
    if (await Directory(hotUpdateDir).exists()) {
      await Directory(hotUpdateDir).delete(recursive: true);
    }

    if (!isSkipDownload) {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.processing,
        '开始下载热更新资源...',
      );

      await global.jenkinsApi?.downloadZipUrl(
        platform: platform,
        buildConfiguration: buildConfiguration,
        zipPath: zipPath,
        buildNumber: buildNumber,
        onReceiveProgress: (p0, p1) {
          status.value = TaskStatus.fromCode(
            TaskStatusCode.processing,
            '[${(p0 / 1024 / 1024).toStringAsFixed(2)}MB]正在下载热更新资源 Zip 包',
          );
        },
      );
      status.value = TaskStatus.fromCode(
        TaskStatusCode.processing,
        '正在解压热更新资源 Zip 包',
      );

      /// 解压 zip
      await extractFileToDisk(zipPath, hotUpdateAssetDir.path);
      status.value = TaskStatus.fromCode(
        TaskStatusCode.success,
        '解压热更新资源 Zip 包成功',
      );
      await File(zipPath).delete();
    } else {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.success,
        '热更新资源 Zip 包已存在',
      );
    }
    return join(hotUpdateAssetDir.path, 'UploadAssets');
  }
}

/// 发布热更新版本任务
class ReleaseHotUpdateVersionTask extends Task<void> {
  final String client;
  final String description;
  final String highCompatibleVersion;
  final String minCompatibleVersion;
  final String publishTime;
  final bool publishStatus;
  final String version;
  final List<UploadResourceResonse> resInfo;
  final List<UploadResourceResonse> packageInfo;

  ReleaseHotUpdateVersionTask({
    required this.client,
    required this.description,
    required this.highCompatibleVersion,
    required this.minCompatibleVersion,
    required this.publishTime,
    required this.publishStatus,
    required this.version,
    required this.resInfo,
    required this.packageInfo,
  }) : super(name: '发布热更新版本');

  @override
  Future<void> execute() async {
    return _start().then((e) {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.success,
        '发布热更新版本成功',
      );
    }).catchError((e) {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.error,
        '发布热更新版本失败: $e',
      );
      throw e;
    });
  }

  Future<void> _start() async {
    final response = await global.post(
      path: '/api/platformservice/sceneResourceManager/saveSceneResource',
      data: {
        'client': client,
        'description': description,
        'highCompatibleVersion': highCompatibleVersion,
        'minCompatibleVersion': minCompatibleVersion,
        'publishTime': publishTime,
        'status': publishStatus ? 1 : 2,
        'version': version,
        'extendMap': {
          'resInfo': resInfo.map((e) => e.toJson()).toList(),
          'packageInfo': packageInfo.map((e) => e.toJson()).toList(),
        }
      },
    );
    final success = JSON(response.data)['success'].boolValue;
    final message = JSON(response.data)['message'].string ?? '未知错误';
    if (!success) {
      throw '发布热更新版本失败\nURL: ${global.gmallUrl}/api/platformservice/sceneResourceManager/saveSceneResource\n错误: $message';
    }
  }
}

class UploadResourceResonse {
  final String packageName;
  final String packageUrl;
  final int packageSize;
  final String md5;

  const UploadResourceResonse({
    required this.packageName,
    required this.packageUrl,
    required this.packageSize,
    required this.md5,
  });

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'packageUrl': packageUrl,
      'packageSize': packageSize,
      'md5': md5,
    };
  }
}

class ToastException implements Exception {
  final String message;

  const ToastException(this.message);
}

enum HotBuildConfiguration {
  debug('Debug'),
  release('Release');

  final String name;

  const HotBuildConfiguration(this.name);
}
