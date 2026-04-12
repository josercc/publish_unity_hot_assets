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
import 'package:publish_unity_hot_assets/app/routes/app_pages.dart';
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

  /// Token检测定时任务
  Timer? _tokenCheckTimer;

  /// 取消所有任务
  void cancelAllTasks() {
    for (final task in taskList) {
      task.cancel();
    }
    if (curTask.value != null) {
      curTask.value!.cancel();
    }
  }

  @override
  void onInit() {
    super.onInit();
    setDate(DateTime.now());
    setTime(TimeOfDay.now());
    _initializeData();
    // 启动token检测定时任务
    _startTokenCheckTimer();
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
    // 取消token检测定时任务
    _tokenCheckTimer?.cancel();
    _tokenCheckTimer = null;
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

  /// 启动token检测定时任务
  void _startTokenCheckTimer() {
    // 每分钟检测一次token有效期
    _tokenCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkTokenValidity();
    });
  }

  /// 检查token有效性
  void _checkTokenValidity() {
    // 如果本地没有token，自动退出到登录页面
    if (global.token == null || global.token!.isEmpty) {
      print('Token不存在，自动退出到登录页面');
      _logoutToLogin();
      return;
    }

    // 获取token剩余有效时间（小时）
    final remainingHours = global.getTokenRemainingHours();

    // 如果token已过期或剩余有效期小于1小时，自动退出到登录页面
    if (remainingHours == null || remainingHours < 1.0) {
      print('Token已过期或剩余有效期小于1小时（剩余: $remainingHours 小时），自动退出到登录页面');
      _logoutToLogin();
      return;
    }

    print('Token检查通过，剩余有效期: ${remainingHours.toStringAsFixed(2)} 小时');
  }

  /// 退出到登录页面
  void _logoutToLogin() {
    // 取消定时任务
    _tokenCheckTimer?.cancel();
    _tokenCheckTimer = null;
    // 取消所有任务
    cancelAllTasks();
    // 跳转到登录页面
    Get.offAllNamed(Routes.LOGIN);
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
      // 如果资源包描述为空，设置默认值：当前分支 + 当前时间点
      _updateDefaultDescription();
    } catch (e) {
      print('加载Unity分支列表失败: $e');
      SmartDialog.showToast('加载Unity分支列表失败: $e');
    }
  }

  /// 选择Unity分支
  void selectUnityBranch(String branch) {
    curUnityBranch.value = branch;
    unityBranchController.text = branch;
    // 切换分支时强制更新资源包描述的默认值
    _updateDefaultDescription(forceUpdate: true);
  }

  /// 更新资源包描述的默认值（当前分支 + 当前时间点）
  /// [forceUpdate] 为 true 时，即使描述已有内容也会更新；为 false 时，只在描述为空时设置默认值
  void _updateDefaultDescription({bool forceUpdate = false}) {
    // 如果用户已经手动填写了描述，且不是强制更新，则不覆盖
    if (!forceUpdate && descController.text.isNotEmpty) {
      return;
    }

    // 获取当前分支（如果有的话）
    final branch = curUnityBranch.value.isNotEmpty
        ? curUnityBranch.value
        : unityBranchController.text.isNotEmpty
            ? unityBranchController.text
            : '';

    // 获取当前时间点（格式：YYYY-MM-DD HH:mm:ss）
    final now = DateTime.now();
    final timeStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    // 组合默认描述
    if (branch.isNotEmpty) {
      descController.text = '$branch $timeStr';
    } else {
      descController.text = timeStr;
    }
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
  /// 返回 true 表示发布成功，false 表示用户取消，抛出异常表示发布失败
  Future<bool> releaseHotUpdateVersionWithConfirmation() async {
    // 在弹框前进行校验
    final version = versionController.text.trim();
    final minVersion = minVersionController.text.trim();
    final maxVersion = maxVersionController.text.trim();

    // 1. 检查版本号是否已被使用（如果填写了版本号）
    if (version.isNotEmpty) {
      await _checkVersionExists(version);
    }

    // 2. 校验最低版本和最高版本的大小关系
    if (minVersion.isNotEmpty && maxVersion.isNotEmpty) {
      final comparisonResult = _compareVersions(minVersion, maxVersion);
      if (comparisonResult >= 0) {
        throw const ToastException('最低兼容版本必须小于最高兼容版本');
      }
    }

    // 校验通过后，显示确认弹框
    final confirmed = await _showPublishConfirmationDialog();
    if (!confirmed) {
      return false; // 用户取消发布
    }

    // 用户确认后，执行发布
    await releaseHotUpdateVersion();
    return true; // 发布成功
  }

  /// 显示发布确认弹框
  Future<bool> _showPublishConfirmationDialog() async {
    // 获取当前环境名称
    String environmentName = switch (curEnvironment.value) {
      Environment.test => '测试环境',
      Environment.prod => '生产环境',
    };

    // 构建确认信息
    final version =
        versionController.text.isEmpty ? '未填写' : versionController.text;
    final minVersion =
        minVersionController.text.isEmpty ? '未填写' : minVersionController.text;
    final maxVersion =
        maxVersionController.text.isEmpty ? '未填写' : maxVersionController.text;
    final desc = descController.text.isEmpty ? '未填写' : descController.text;
    final publishTime =
        dateController.text.isEmpty || timeController.text.isEmpty
            ? '未填写'
            : '${dateController.text} ${timeController.text}';

    // 根据环境设置标题和颜色
    final isProd = curEnvironment.value == Environment.prod;
    final title = isProd ? '⚠️ 生产环境发布确认' : '📦 发布确认';
    final confirmColor = isProd ? Colors.red : Colors.blue;

    // 构建确认信息文本
    final descDisplay = desc.isEmpty
        ? '未填写'
        : (desc.length > 50 ? '${desc.substring(0, 50)}...' : desc);
    final warningText = isProd ? '\n⚠️ 您即将发布到生产环境，此操作将影响线上用户！' : '\n确定要继续发布吗？';

    final confirmContent = '当前环境：$environmentName\n\n'
        '请确认以下发布信息：\n'
        '平台：${curPlatform.value}\n'
        '版本号：$version\n'
        '最低兼容版本：$minVersion\n'
        '最高兼容版本：$maxVersion\n'
        '发布时间：$publishTime\n'
        '资源包描述：$descDisplay$warningText';

    return await Get.dialog<bool>(
          AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Text(confirmContent),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Get.back(result: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
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

    /// 版本号格式验证（支持 vx.y.z 格式，z 必须是5位数）
    final versionReg = RegExp(r'^(v)?\d+\.\d+\.\d{5}$');
    if (!versionReg.hasMatch(version)) {
      throw const ToastException('版本号格式不正确，请使用 vx.y.zzzzz 格式，其中 zzzzz 必须是5位数字');
    }

    final minVersion = minVersionController.text;
    if (minVersion.isEmpty) {
      throw const ToastException('请输入最低兼容版本');
    }

    final maxVersion = maxVersionController.text;
    if (maxVersion.isNotEmpty) {
      // // 验证最高版本格式
      // if (!versionReg.hasMatch(maxVersion)) {
      //   throw const ToastException('最高兼容版本格式不正确，请使用 x.x.x 或 vx.x.x 格式');
      // }

      // 验证版本号大小关系
      final comparisonResult = _compareVersions(minVersion, maxVersion);
      if (comparisonResult >= 0) {
        throw const ToastException('最低兼容版本必须小于最高兼容版本');
      }
    }

    // 版本号检查已在弹框前完成，这里不需要再次检查

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

    // 检查并添加 ABEditorManifests.xml 和 ABEditorManifests.bytes 文件（如果存在）
    final abEditorManifestsXmlFile =
        File(join(packPath, 'ABEditorManifests.xml'));
    if (await abEditorManifestsXmlFile.exists()) {
      uploadResTaskList.add(UploadResourceTask(
        abEditorManifestsXmlFile,
        await abEditorManifestsXmlFile.length(),
        isForceUpload: isForceUpload.value,
      ));
    }

    final abEditorManifestsBytesFile =
        File(join(packPath, 'ABEditorManifests.bytes'));
    if (await abEditorManifestsBytesFile.exists()) {
      uploadResTaskList.add(UploadResourceTask(
        abEditorManifestsBytesFile,
        await abEditorManifestsBytesFile.length(),
        isForceUpload: isForceUpload.value,
      ));
    }
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

  /// 解析版本号和 build 号
  /// 支持的格式：
  /// - "2.0.8" -> version: "2.0.8", build: 0
  /// - "2.0.8 (0)" -> version: "2.0.8", build: 0
  /// - "2.0.9 (1)" -> version: "2.0.9", build: 1
  _VersionParts _parseVersion(String version) {
    // 移除可能的 'v' 前缀
    String cleanVersion = version.replaceFirst(RegExp(r'^v'), '').trim();

    // 提取 build 号
    int build = 0;
    final buildMatch = RegExp(r'\(\s*(\d+)\s*\)').firstMatch(cleanVersion);
    if (buildMatch != null) {
      build = int.parse(buildMatch.group(1)!);
    }

    // 移除 build 号部分
    cleanVersion = cleanVersion.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

    return _VersionParts(cleanVersion, build);
  }

  /// 比较两个版本
  /// 返回负数表示 v1 < v2，返回 0 表示 v1 == v2，返回正数表示 v1 > v2
  /// 先比较版本号，如果版本号相等则比较 build 号
  int _compareVersions(String v1, String v2) {
    final parts1 = _parseVersion(v1);
    final parts2 = _parseVersion(v2);

    // 先比较版本号
    final versionComparison =
        _compareVersionNumbers(parts1.version, parts2.version);
    if (versionComparison != 0) {
      return versionComparison;
    }

    // 版本号相等，比较 build 号
    return parts1.build - parts2.build;
  }

  /// 比较版本号（不含 build 号）
  /// 返回负数表示 v1 < v2，返回 0 表示 v1 == v2，返回正数表示 v1 > v2
  int _compareVersionNumbers(String v1, String v2) {
    final parts1 =
        v1.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final parts2 =
        v2.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();

    // 补齐到相同长度
    final maxLength =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    while (parts1.length < maxLength) parts1.add(0);
    while (parts2.length < maxLength) parts2.add(0);

    // 逐段比较
    for (int i = 0; i < maxLength; i++) {
      if (parts1[i] != parts2[i]) {
        return parts1[i] - parts2[i];
      }
    }

    return 0;
  }

  /// 查询场景资源列表并自动填充版本号
  Future<void> autoFillVersion() async {
    try {
      // 检查最低兼容版本是否已填写
      final minVersion = minVersionController.text.trim();
      if (minVersion.isEmpty) {
        throw const ToastException('请先填写最低兼容版本');
      }

      // 检查最高兼容版本是否已填写
      final maxVersion = maxVersionController.text.trim();
      if (maxVersion.isEmpty) {
        throw const ToastException('请先填写最高兼容版本');
      }

      // 校验最低版本必须小于最高版本
      final comparisonResult = _compareVersions(minVersion, maxVersion);
      if (comparisonResult >= 0) {
        throw const ToastException('最低兼容版本必须小于最高兼容版本');
      }

      SmartDialog.showLoading(msg: '正在查询场景资源列表...');

      // 只查询最新的100条数据
      const pageSize = 100;
      final response = await global.post(
        path:
            '/api/platformservice/sceneResourceManager/querySceneSourceList',
        data: {
          'page': {
            'pageSize': pageSize,
            'pageNo': 1,
          },
        },
      );

      final success = JSON(response.data)['success'].boolValue;
      final message = JSON(response.data)['message'].string ?? '未知错误';
      if (!success) {
        SmartDialog.dismiss();
        throw ToastException('查询场景资源列表失败\n错误: $message');
      }

      final pageData = JSON(response.data)['data'];
      final allDataList = pageData['list'].listValue;

      SmartDialog.dismiss();

      // 筛选数据
      // 1. 根据平台（client）筛选
      // 2. status = 1
      // 3. minCompatibleVersion 和当前最低版本一致（需要提取版本号部分进行比较）
      // 4. highCompatibleVersion 和当前最高版本一致（需要提取版本号部分进行比较）
      final filteredList = allDataList.where((item) {
        final jsonItem = JSON(item);
        final client = jsonItem['client'].stringValue;
        final status = jsonItem['status'].intValue;
        final minCompatibleVersion =
            jsonItem['minCompatibleVersion'].stringValue;
        final highCompatibleVersion =
            jsonItem['highCompatibleVersion'].stringValue;

        // 提取版本号部分（移除 v 前缀和 build 号）
        final parsedMinVersion = _extractVersionNumber(minCompatibleVersion);
        final parsedHighVersion = _extractVersionNumber(highCompatibleVersion);
        final parsedInputMinVersion = _extractVersionNumber(minVersion);
        final parsedInputMaxVersion = _extractVersionNumber(maxVersion);

        return client == curPlatform.value &&
            status == 1 &&
            parsedMinVersion == parsedInputMinVersion &&
            parsedHighVersion == parsedInputMaxVersion;
      }).toList();

      String nextVersion;

      if (filteredList.isEmpty) {
        // 如果未找到符合条件的场景资源，基于最低版本号生成初始版本号
        // 例如：2.0.5 (0) -> 2.0.50000
        nextVersion = _generateInitialVersion(minVersion);
        versionController.text = nextVersion;
        SmartDialog.showToast('未找到符合条件的场景资源，已生成初始版本号: $nextVersion');
        return;
      }

      // 找到版本最高的
      String? maxVersionStr;
      for (final item in filteredList) {
        final version = JSON(item)['version'].stringValue;
        if (version.isEmpty) continue;

        if (maxVersionStr == null) {
          maxVersionStr = version;
        } else {
          // 比较版本号，找到最高的
          if (_compareVersions(version, maxVersionStr) > 0) {
            maxVersionStr = version;
          }
        }
      }

      if (maxVersionStr == null || maxVersionStr.isEmpty) {
        // 如果没有找到有效的版本号，也基于最低版本号生成初始版本号
        nextVersion = _generateInitialVersion(minVersion);
      } else {
        // 版本号自动+1
        // 例如：v2.0.50001 -> v2.0.50002
        nextVersion = _incrementVersion(maxVersionStr);
      }

      // 验证生成的版本号格式是否符合规范（vx.y.z 格式，z 必须是5位数）
      final versionReg = RegExp(r'^(v)?\d+\.\d+\.\d{5}$');
      if (!versionReg.hasMatch(nextVersion)) {
        SmartDialog.dismiss();
        throw ToastException(
            '自动生成的版本号格式不正确: $nextVersion，版本号格式应为 vx.y.zzzzz（其中 zzzzz 必须是5位数字），请手动输入版本号');
      }

      versionController.text = nextVersion;

      if (maxVersionStr == null || maxVersionStr.isEmpty) {
        SmartDialog.showToast('未找到有效的版本号，已生成初始版本号: $nextVersion');
      } else {
        SmartDialog.showToast('已自动填充版本号: $nextVersion');
      }
    } catch (e) {
      SmartDialog.dismiss();
      if (e is ToastException) {
        SmartDialog.showToast(e.message);
      } else {
        SmartDialog.showToast('自动填充版本号失败: $e');
      }
    }
  }

  /// 检查版本号是否已被使用
  /// 如果已被使用，抛出异常提示用户重新生成
  Future<void> _checkVersionExists(String version) async {
    try {
      SmartDialog.showLoading(msg: '正在检查版本号是否已被使用...');

      // 只查询最新的100条数据
      const pageSize = 100;
      final response = await global.post(
        path:
            '/api/platformservice/sceneResourceManager/querySceneSourceList',
        data: {
          'page': {
            'pageSize': pageSize,
            'pageNo': 1,
          },
        },
      );

      final success = JSON(response.data)['success'].boolValue;
      final message = JSON(response.data)['message'].string ?? '未知错误';
      if (!success) {
        SmartDialog.dismiss();
        throw ToastException('查询场景资源列表失败\n错误: $message');
      }

      final pageData = JSON(response.data)['data'];
      final allDataList = pageData['list'].listValue;

      SmartDialog.dismiss();

      // 提取当前版本号的纯版本号部分（用于比较）
      final parsedVersion = _extractVersionNumber(version);

      // 检查是否有相同平台和相同版本号的记录
      final exists = allDataList.any((item) {
        final jsonItem = JSON(item);
        final client = jsonItem['client'].stringValue;
        final itemVersion = jsonItem['version'].stringValue;

        // 比较平台和版本号（提取版本号部分进行比较）
        return client == curPlatform.value &&
            _extractVersionNumber(itemVersion) == parsedVersion;
      });

      if (exists) {
        throw ToastException('版本号 $version 已被使用，请点击"自动填充"按钮重新生成版本号');
      }
    } catch (e) {
      SmartDialog.dismiss();
      if (e is ToastException) {
        rethrow;
      } else {
        // 如果查询失败，只记录日志但不阻止发布（避免因网络问题阻止正常发布）
        print('检查版本号时出错: $e');
        // 可以选择是否抛出异常，这里选择不抛出，允许继续发布
        // throw ToastException('检查版本号失败，请稍后重试: $e');
      }
    }
  }

  /// 提取版本号（移除 v 前缀和 build 号）
  /// 例如：v2.0.5 (0) -> 2.0.5，v2.0.50001 -> 2.0.50001
  String _extractVersionNumber(String versionWithBuild) {
    // 移除可能的 'v' 或 'V' 前缀（大小写不敏感）
    String cleanVersion =
        versionWithBuild.replaceFirst(RegExp(r'^[vV]'), '').trim();

    // 移除 build 号部分（如果有）
    cleanVersion = cleanVersion.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

    return cleanVersion;
  }

  /// 生成初始版本号（基于最低版本号）
  /// 例如：2.0.5 (0) -> 2.0.50000，v2.0.5 -> v2.0.50000
  String _generateInitialVersion(String minVersion) {
    // 检查是否有 v 前缀
    final hasVPrefix = minVersion.startsWith('v') || minVersion.startsWith('V');

    // 提取版本号（移除 v 前缀和 build 号）
    String cleanVersion = _extractVersionNumber(minVersion);

    // 分割版本号
    final parts = cleanVersion.split('.');
    if (parts.isEmpty) {
      return minVersion;
    }

    // 将最后一部分补零到5位数，例如：5 -> 50000, 100 -> 100001, 99 -> 99001
    // 确保最后一部分最大是5位数
    final lastPart = int.tryParse(parts.last) ?? 0;
    final lastPartStr = lastPart.toString();
    
    if (lastPartStr.length >= 5) {
      // 如果已经是5位或更多，取后5位（确保最大是5位）
      parts[parts.length - 1] = lastPartStr.length > 5 
          ? lastPartStr.substring(lastPartStr.length - 5)
          : lastPartStr;
    } else {
      // 小于5位的，乘以10000变成5位数
      // 例如：5 -> 50000, 99 -> 99001, 100 -> 100001
      final multiplied = lastPart * 10000;
      final multipliedStr = multiplied.toString();
      // 如果乘以10000后超过5位，取前5位
      if (multipliedStr.length > 5) {
        parts[parts.length - 1] = multipliedStr.substring(0, 5);
      } else {
        parts[parts.length - 1] = multipliedStr.padLeft(5, '0');
      }
    }

    final initialVersion = parts.join('.');

    // 如果原版本有 v 前缀，则保留
    return hasVPrefix ? 'v$initialVersion' : initialVersion;
  }

  /// 版本号自动+1
  /// 例如：v2.0.40000 -> v2.0.40001，2.0.40000 -> 2.0.40001
  /// 确保最后一部分保持5位数
  String _incrementVersion(String version) {
    // 检查是否有 v 前缀
    final hasVPrefix = version.startsWith('v') || version.startsWith('V');

    // 提取版本号（移除 v 前缀）
    String cleanVersion = version.replaceFirst(RegExp(r'^[vV]'), '').trim();

    // 分割版本号
    final parts = cleanVersion.split('.');
    if (parts.isEmpty) {
      return version;
    }

    // 将最后一部分+1，并确保最大是5位数
    final lastPart = int.tryParse(parts.last) ?? 0;
    final incremented = lastPart + 1;

    // 确保递增后的第三段始终是 5 位数字（与 versionReg / _generateInitialVersion 一致）
    final incrementedStr = incremented.toString();
    if (incrementedStr.length > 5) {
      // 如果超过5位，取后5位
      parts[parts.length - 1] =
          incrementedStr.substring(incrementedStr.length - 5);
    } else {
      parts[parts.length - 1] = incrementedStr.padLeft(5, '0');
    }

    final incrementedVersion = parts.join('.');

    // 如果原版本有 v 前缀，则保留
    return hasVPrefix ? 'v$incrementedVersion' : incrementedVersion;
  }
}

/// 版本号解析结果
class _VersionParts {
  final String version;
  final int build;

  _VersionParts(this.version, this.build);
}

/// 打包资源任务
class PackResourceTask extends Task<void> {
  final String platform;
  final String buildConfiguration;
  final String branch;
  int? buildNumber; // 构建号，在构建完成后设置
  String? waitingUid; // 等待获取构建号时的UID

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

    status.value = TaskStatus.fromCode(
      TaskStatusCode.processing,
      '正在启动Jenkins构建...',
    );

    // 启动构建并获取构建号
    String? currentUid;
    final newBuildNumber = await jenkinsApi.startBuild(
      platform: platform,
      buildConfiguration: buildConfiguration,
      branch: branch,
      shouldCancel: () => isCancelled, // 检查任务是否已取消
      onProgress: (message) {
        // 从消息中提取UID（如果消息包含UID）
        // 匹配格式：UID: xxx 或 (UID: xxx) 或 UID: xxx,
        if (message.contains('UID')) {
          // 尝试多种可能的格式
          RegExpMatch? uidMatch = RegExp(r'UID:\s*(\d+)').firstMatch(message);
          if (uidMatch == null) {
            uidMatch = RegExp(r'\(UID:\s*(\d+)\)').firstMatch(message);
          }
          if (uidMatch == null) {
            uidMatch = RegExp(r'UID\s*[=:]\s*(\d+)').firstMatch(message);
          }
          if (uidMatch != null) {
            final extractedUid = uidMatch.group(1);
            if (extractedUid != null) {
              currentUid = extractedUid;
              waitingUid = currentUid;
            }
          }
        }
        // 更新任务状态，显示等待获取构建号的进度
        status.value = TaskStatus.fromCode(
          TaskStatusCode.processing,
          message,
        );
      },
    );

    // 获取到构建号后，清除等待的UID
    waitingUid = null;

    buildNumber = newBuildNumber; // 保存构建号
    print('获取到构建号: $buildNumber');

    status.value = TaskStatus.fromCode(
      TaskStatusCode.processing,
      '构建已启动（构建号: $buildNumber），开始监控构建进度...',
    );

    // 开始监控构建结果
    final result = await queryBuildResult(buildNumber!);
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
      throw Exception('Jenkins构建失败，构建号: $buildNumber');
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

        // Jenkins构建结果状态：
        // null - 构建还在进行中
        // SUCCESS - 构建成功
        // FAILURE - 构建失败
        // ABORTED - 构建已中止
        // UNSTABLE - 构建不稳定（有测试失败但构建成功）
        // 任何非null的状态都表示构建已结束，应该停止查询
        if (result == 'SUCCESS') {
          timer?.cancel();
          completer.complete(true);
        } else if (result != null) {
          // 构建已结束，但结果不是SUCCESS（可能是FAILURE、ABORTED、UNSTABLE等）
          timer?.cancel();
          status.value = TaskStatus.fromCode(
            TaskStatusCode.error,
            'Jenkins构建已结束，结果: $result',
          );
          completer.complete(false);
        }
        // 如果result为null，表示构建还在进行中，继续等待
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
