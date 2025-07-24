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

  @override
  void onInit() {
    super.onInit();
    setDate(DateTime.now());
    setTime(TimeOfDay.now());
    Future.sync(() async {
      final branch = await global.jenkinsApi?.queryDefaultBranch();
      unityBranchController.text = branch ?? '';
      await loadMinVersion();
    });
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
        throw message;
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

  /// 切换平台
  Future<void> switchPlatform(String platform) async {
    curPlatform.value = platform;
    SmartDialog.showLoading();
    await loadMinVersion();
    SmartDialog.dismiss();
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

    /// 版本号必须是 vx.x.x 格式的
    final versionReg = RegExp(r'^v\d+\.\d+\.\d+$');
    if (!versionReg.hasMatch(version)) {
      throw const ToastException('版本号必须是 vx.x.x 格式的');
    }

    final minVersion = minVersionController.text;
    if (minVersion.isEmpty) {
      throw const ToastException('请输入最低兼容版本');
    }

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
    }

    /// 下载资源
    final downloadTask = DownloadZipUrlTask(
      platform: curPlatform.value,
      buildConfiguration: curBuildConfiguration.value.name,
      isSkipDownload: isSkipDownload.value,
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
      UploadResourceTask(patchXmlFile),
      UploadResourceTask(patchBytesFile),
    ];
    List<UploadResourceTask> uploadABTaskList = [];
    final assetBundleFiles = assetBundleDir.listSync().whereType<File>();
    for (final file in assetBundleFiles) {
      final fileExtension = extension(file.path);
      if (fileExtension == '.bytes' || fileExtension == '.xml') {
        uploadABTaskList.add(UploadResourceTask(file));
      } else if (fileExtension == '.zip') {
        final fileName = basenameWithoutExtension(file.path);
        final md5 = patchABList
            .map((e) => JSON(e)['Md5'].string)
            .whereType<String>()
            .firstOrNull;
        if (md5 == null) {
          throw 'Patch.xml 文件中没有 $fileName 的 md5 值';
        }
        uploadABTaskList.add(UploadResourceTask(file, md5: md5));
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
}

/// 打包资源任务
class PackResourceTask extends Task<void> {
  final String platform;
  final String buildConfiguration;
  final String branch;
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
    print(lastBuildNumber);
    await jenkinsApi.startBuild(
      platform: platform,
      buildConfiguration: buildConfiguration,
      branch: branch,
    );
    final result = await queryBuildResult(lastBuildNumber + 1);
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
    }
  }

  /// 查询构建结果
  Future<bool> queryBuildResult(int buildNumber) async {
    Completer<bool> completer = Completer<bool>();
    DateTime startTime = DateTime.now();
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      status.value = TaskStatus.fromCode(
        TaskStatusCode.processing,
        '正在查询构建结果...已等待${DateTime.now().difference(startTime).inSeconds}秒',
      );
      final result = await global.jenkinsApi?.queryBuildResult(
        buildNumber: buildNumber,
      );
      if (result == 'SUCCESS') {
        timer.cancel();
        completer.complete(true);
      } else if (result == 'FAILURE') {
        timer.cancel();
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

  UploadResourceTask(this.file, {this.md5})
      : super(name: '上传资源文件 ${basename(file.path)}');

  @override
  Future<UploadResourceResonse> execute() async {
    print(file.path);
    return _start().then((e) {
      status.value = TaskStatus.fromCode(
          TaskStatusCode.success, '[${basename(file.path)}]上传成功');
      return e;
    }).catchError((e) {
      status.value = TaskStatus.fromCode(
          TaskStatusCode.error, '[${basename(file.path)}]上传失败:${e.toString()}');
      throw e;
    });
  }

  Future<UploadResourceResonse> _start() async {
    status.value = TaskStatus.fromCode(
        TaskStatusCode.processing, '[${basename(file.path)}]正在上传资源文件');
    final fileLength = await file.length();
    final fileName = basename(file.path);

    /// 先查询当前文件是否已经上传过
    final md5 = this.md5 ?? await computeMd5();
    final url = await queryNetworkImageUrl(md5);
    if (url != null) {
      return UploadResourceResonse(
        packageName: fileName,
        packageUrl: url,
        packageSize: fileLength,
        md5: md5,
      );
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
        fileName: 'part_$partNumber',
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
    final content = file.openRead();
    final digest = await crypto.md5.bind(content).first;
    return digest.toString();
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
      throw message;
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
      throw message;
    }
    final uploadId = JSON(response.data)['data']['uploadId'].string;
    if (uploadId == null) {
      throw '上传 Id 不能为空';
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
      throw message;
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
      throw message;
    }
    final url = JSON(response.data)['data']['fileUrl'].string;
    if (url == null) {
      throw '合并切片失败';
    }
    return url;
  }
}

/// 下载 zip 包任务
class DownloadZipUrlTask extends Task<String> {
  final String platform;
  final String buildConfiguration;
  final bool isSkipDownload;

  DownloadZipUrlTask({
    required this.platform,
    required this.buildConfiguration,
    required this.isSkipDownload,
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
    if (await File(zipPath).exists()) {
      await File(zipPath).delete();
    }
    final hotUpdateAssetDir = Directory(join(hotUpdateDir, 'Assets'));

    if (!isSkipDownload) {
      await global.jenkinsApi?.downloadZipUrl(
        platform: platform,
        buildConfiguration: buildConfiguration,
        zipPath: zipPath,
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
      throw message;
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
