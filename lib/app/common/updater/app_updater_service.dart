import 'dart:io';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:archive/archive_io.dart';

/// 更新信息模型
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? releaseNotes;
  final bool isForceUpdate;
  final int fileSize;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.releaseNotes,
    this.isForceUpdate = false,
    required this.fileSize,
  });
}

/// 应用更新服务
class AppUpdaterService {
  /// 检查更新
  /// 返回 UpdateInfo 如果有新版本，否则返回 null
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      // 获取当前应用版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 根据平台选择不同的 channel_key
      final channelKey = Platform.isMacOS
          ? '45236b0154b76d9f3797c038344df982'
          : 'd55df3b09dea0494c9ad3e6a8766786c';

      final apiUrl =
          'https://app.winnermedical.com/api/apps/latest?channel_key=$channelKey';

      // 使用 dio 直接请求（不使用 global.post，因为这是外部 API）
      final response = await global.dio.get(apiUrl);

      // 解析响应数据
      final jsonData = JSON(response.data);
      final releases = jsonData['releases'].listValue;
      if (releases.isEmpty) {
        return null;
      }

      // 第一个 release 是最新版本
      final latestRelease = JSON(releases.first);
      final latestVersion = latestRelease['release_version'].stringValue;
      final downloadUrl = latestRelease['install_url'].stringValue;
      final fileSize = latestRelease['size'].intValue;

      // 解析 changelog
      final changelog = latestRelease['changelog'].listValue;
      final textChangelog = latestRelease['text_changelog'].stringValue;

      String releaseNotes = '';
      if (textChangelog.isNotEmpty) {
        releaseNotes = textChangelog;
      } else if (changelog.isNotEmpty) {
        // 如果有 changelog 数组，转换为文本
        releaseNotes = changelog
            .map((item) => JSON(item).toString())
            .where((item) => item.isNotEmpty)
            .join('\n');
      }

      // 比较版本号
      if (_compareVersions(currentVersion, latestVersion) < 0) {
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes.isNotEmpty ? releaseNotes : null,
          isForceUpdate: true, // 根据需求，只能点击安装，所以设置为强制更新
          fileSize: fileSize,
        );
      }

      return null;
    } catch (e, stackTrace) {
      print('检查更新失败: $e');
      print('堆栈跟踪: $stackTrace');
      return null;
    }
  }

  /// 下载更新文件
  /// [updateInfo] 更新信息
  /// [onProgress] 进度回调 (已下载字节数, 总字节数)
  Future<String> downloadUpdate(
    UpdateInfo updateInfo,
    void Function(int, int)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();

    // 先尝试获取最终 URL（可能经过重定向）
    String finalUrl = updateInfo.downloadUrl;
    String fileExtension = '';

    try {
      // 发送 HEAD 请求获取重定向后的最终 URL
      final headResponse = await global.dio.head(
        updateInfo.downloadUrl,
        options: Options(followRedirects: true),
      );
      final redirects = headResponse.redirects;
      if (redirects.isNotEmpty) {
        finalUrl = redirects.last.location.toString();
        print('下载 URL 重定向到: $finalUrl');
      }

      // 从最终 URL 获取扩展名
      final urlPath = Uri.parse(finalUrl).path;
      fileExtension = path.extension(urlPath);
      print('从最终 URL 获取扩展名: $fileExtension');

      // 同时获取 Content-Type
      final contentType = headResponse.headers.value('content-type');
      print('Content-Type: $contentType');

      if (fileExtension.isEmpty && contentType != null) {
        if (contentType.contains('application/zip')) {
          fileExtension = '.zip';
        } else if (contentType.contains('application/x-dmg') ||
            contentType.contains('application/x-apple-diskimage')) {
          fileExtension = '.dmg';
        } else if (contentType.contains('application/octet-stream')) {
          // 根据平台设置默认值
          fileExtension = Platform.isMacOS ? '.dmg' : '.zip';
        }
        print('从 Content-Type 推断扩展名: $fileExtension');
      }
    } catch (e) {
      print('获取 URL 信息失败: $e，使用原始 URL');
      // 从原始 URL 获取扩展名
      final urlPath = Uri.parse(updateInfo.downloadUrl).path;
      fileExtension = path.extension(urlPath);
    }

    // 如果还是没有扩展名，根据平台设置默认扩展名
    if (fileExtension.isEmpty) {
      fileExtension = Platform.isMacOS ? '.dmg' : '.zip';
      print('使用默认扩展名: $fileExtension');
    }

    // 生成文件名（使用时间戳确保唯一性）
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'update_$timestamp$fileExtension';
    final downloadPath = path.join(tempDir.path, fileName);

    print('下载 URL: ${updateInfo.downloadUrl}');
    print('最终 URL: $finalUrl');
    print('下载文件路径: $downloadPath');
    print('文件扩展名: $fileExtension');

    // 如果文件已存在，先删除
    final file = File(downloadPath);
    if (await file.exists()) {
      await file.delete();
    }

    try {
      // 下载文件
      await global.dio.downloadUri(
        Uri.parse(updateInfo.downloadUrl),
        downloadPath,
        onReceiveProgress: onProgress,
      );

      // 下载后验证文件扩展名
      final actualExtension = path.extension(downloadPath);
      print('下载完成: $downloadPath');
      print('实际文件扩展名: $actualExtension');

      // 如果下载后的文件扩展名不对，尝试重命名
      if (actualExtension != fileExtension) {
        print('文件扩展名不匹配，尝试重命名...');
        final correctPath =
            downloadPath.replaceAll(actualExtension, fileExtension);
        final correctFile = File(correctPath);

        if (await correctFile.exists()) {
          await correctFile.delete();
        }

        await file.rename(correctPath);
        print('文件已重命名为: $correctPath');
        return correctPath;
      }

      return downloadPath;
    } catch (e) {
      throw Exception('下载更新失败: $e');
    }
  }

  /// 安装更新
  /// [updateFilePath] 更新文件路径
  /// 返回新应用的路径（用于重启）
  Future<String?> installUpdate(String updateFilePath) async {
    try {
      print('开始安装更新，文件路径: $updateFilePath');
      print('文件扩展名: ${path.extension(updateFilePath)}');

      if (Platform.isMacOS) {
        final appPath = await _installMacOSUpdate(updateFilePath);
        return appPath;
      } else if (Platform.isWindows) {
        final appPath = await _installWindowsUpdate(updateFilePath);
        return appPath;
      } else {
        throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
      }
    } catch (e, stackTrace) {
      print('安装更新失败: $e');
      print('错误堆栈: $stackTrace');
      print('文件路径: $updateFilePath');
      print('文件是否存在: ${await File(updateFilePath).exists()}');
      throw Exception('安装更新失败: $e');
    }
  }

  /// macOS 安装更新
  /// 返回新应用的路径
  Future<String?> _installMacOSUpdate(String updateFilePath) async {
    final file = File(updateFilePath);
    if (!await file.exists()) {
      throw Exception('更新文件不存在: $updateFilePath');
    }

    print('开始安装 macOS 更新: $updateFilePath');
    final fileExtension = path.extension(updateFilePath).toLowerCase();
    print('文件扩展名: $fileExtension');
    print('文件大小: ${await file.length()} 字节');

    // 检查文件扩展名
    if (fileExtension == '.dmg') {
      return await _installFromDMG(updateFilePath);
    } else if (fileExtension == '.zip') {
      return await _installFromZIP(updateFilePath, isWindows: false);
    } else {
      // 如果扩展名为空或不识别，尝试通过文件内容判断
      print('扩展名未识别，尝试通过文件内容判断...');

      // 尝试读取文件头判断文件类型
      final fileBytes = await file.readAsBytes();
      if (fileBytes.length >= 4) {
        // ZIP 文件头: PK\x03\x04 或 PK\x05\x06
        if (fileBytes[0] == 0x50 &&
            fileBytes[1] == 0x4B &&
            (fileBytes[2] == 0x03 || fileBytes[2] == 0x05)) {
          print('通过文件头判断为 ZIP 文件');
          return await _installFromZIP(updateFilePath, isWindows: false);
        }
      }

      final errorMsg = '不支持的 macOS 更新文件格式: $fileExtension，仅支持 .dmg 或 .zip';
      print('错误: $errorMsg');
      print('文件路径: $updateFilePath');
      print('文件大小: ${await file.length()} 字节');
      throw Exception(errorMsg);
    }
  }

  /// 从 DMG 安装
  /// 返回新应用的路径
  Future<String?> _installFromDMG(String dmgPath) async {
    print('挂载 DMG: $dmgPath');

    // 挂载 DMG（使用 -nobrowse 避免 Finder 自动打开）
    final attachResult = await Process.run(
      'hdiutil',
      ['attach', '-nobrowse', '-readonly', dmgPath],
    );

    if (attachResult.exitCode != 0) {
      throw Exception('挂载 DMG 失败: ${attachResult.stderr}');
    }

    // 从输出中提取挂载点
    String? mountPoint;
    final output = attachResult.stdout.toString();
    final lines = output.split('\n');
    for (final line in lines) {
      if (line.contains('/Volumes/')) {
        final parts = line.split('\t');
        if (parts.isNotEmpty) {
          mountPoint = parts.last.trim();
          break;
        }
      }
    }

    // 如果无法从输出中提取，尝试查找
    if (mountPoint == null || !await Directory(mountPoint).exists()) {
      // 列出所有挂载点
      final listResult = await Process.run('hdiutil', ['info']);
      final listOutput = listResult.stdout.toString();
      final volumeMatch = RegExp(r'/Volumes/[^\s]+').firstMatch(listOutput);
      if (volumeMatch != null) {
        mountPoint = volumeMatch.group(0);
      }
    }

    if (mountPoint == null || !await Directory(mountPoint).exists()) {
      // 尝试卸载可能的挂载点
      try {
        await Process.run('hdiutil', ['detach', mountPoint ?? '']);
      } catch (_) {}
      throw Exception('无法找到 DMG 挂载点');
    }

    print('DMG 挂载点: $mountPoint');

    try {
      final mountDir = Directory(mountPoint);

      // 查找 .app 文件
      Directory? appFile;
      await for (final entity in mountDir.list()) {
        if (entity.path.endsWith('.app') && entity is Directory) {
          appFile = entity;
          print('找到应用: ${appFile.path}');
          break;
        }
      }

      if (appFile == null) {
        throw Exception('在 DMG 中未找到 .app 文件');
      }

      // 复制应用到 Applications 目录
      final applicationsDir = Directory('/Applications');
      final appName = path.basename(appFile.path);
      final targetApp = Directory(path.join(applicationsDir.path, appName));

      print('目标路径: ${targetApp.path}');

      // 如果应用已存在，先删除
      if (await targetApp.exists()) {
        print('删除旧应用: ${targetApp.path}');
        final rmResult = await Process.run('rm', ['-rf', targetApp.path]);
        if (rmResult.exitCode != 0) {
          throw Exception('删除旧应用失败: ${rmResult.stderr}');
        }
      }

      // 复制新应用（使用 ditto 命令，更可靠）
      print('复制应用到 /Applications...');
      final copyResult = await Process.run(
        'ditto',
        [appFile.path, targetApp.path],
      );

      if (copyResult.exitCode != 0) {
        throw Exception('复制应用失败: ${copyResult.stderr}');
      }

      print('应用安装成功: ${targetApp.path}');
      return targetApp.path;
    } finally {
      // 卸载 DMG
      print('卸载 DMG: $mountPoint');
      await Process.run('hdiutil', ['detach', mountPoint]);
    }
  }

  /// 从 ZIP 安装
  /// [isWindows] 是否为 Windows 平台
  /// 返回新应用的路径
  Future<String?> _installFromZIP(String zipPath,
      {bool isWindows = false}) async {
    print('开始解压 ZIP: $zipPath');

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('ZIP 文件不存在: $zipPath');
    }

    print('ZIP 文件大小: ${await zipFile.length()} 字节');

    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(path.join(tempDir.path,
        'update_extract_${DateTime.now().millisecondsSinceEpoch}'));

    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create();

    print('解压目录: ${extractDir.path}');

    try {
      // 根据平台选择解压方式
      if (Platform.isWindows) {
        // Windows 使用 archive 包解压
        print('开始解压 ZIP 文件（Windows）...');
        final inputStream = InputFileStream(zipPath);
        final archive = ZipDecoder().decodeStream(inputStream);
        extractArchiveToDisk(archive, extractDir.path);
        await inputStream.close();
        print('ZIP 解压完成: ${extractDir.path}');
      } else {
        // macOS 使用系统 unzip 命令解压（更可靠，能正确处理 macOS 的 ZIP 文件）
        print('开始解压 ZIP 文件（macOS）...');
        final unzipResult = await Process.run(
          'unzip',
          [
            '-q', // 静默模式
            '-o', // 覆盖已存在的文件
            zipPath,
            '-d', // 指定解压目录
            extractDir.path,
          ],
        );

        if (unzipResult.exitCode != 0) {
          print('unzip 命令失败: ${unzipResult.stderr}');
          throw Exception('解压 ZIP 文件失败: ${unzipResult.stderr}');
        }

        print('ZIP 解压完成: ${extractDir.path}');
      }

      // 列出解压后的所有文件和目录（用于调试）
      print('解压目录: ${extractDir.path}');
      print('顶层目录内容:');
      final topLevelEntities = <FileSystemEntity>[];
      await for (final entity in extractDir.list()) {
        topLevelEntities.add(entity);
        final entityType = entity is Directory ? '目录' : '文件';
        print('  - ${path.basename(entity.path)} ($entityType)');
      }

      if (Platform.isWindows) {
        // Windows: 查找 .exe 文件并复制整个目录
        return await _installWindowsFromZIP(extractDir, topLevelEntities);
      } else {
        // macOS: 查找 .app 文件
        return await _installMacOSFromZIP(extractDir, topLevelEntities);
      }
    } catch (e) {
      // 重新抛出异常，让上层处理
      rethrow;
    } finally {
      // 清理临时文件（延迟删除，确保文件操作完成）
      // 使用 try-catch 包裹，避免清理失败影响主流程
      try {
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            if (await extractDir.exists()) {
              // 尝试删除，如果失败则忽略（可能是文件正在使用）
              try {
                await extractDir.delete(recursive: true);
                print('临时目录已清理: ${extractDir.path}');
              } catch (e) {
                print('清理临时目录失败（可忽略）: $e');
              }
            }
          } catch (e) {
            print('清理临时目录失败（可忽略）: $e');
          }
        });
      } catch (e) {
        // 忽略清理错误
        print('清理临时目录失败（可忽略）: $e');
      }
    }
  }

  /// Windows 安装更新
  /// 返回应用安装目录路径
  Future<String?> _installWindowsUpdate(String updateFilePath) async {
    final file = File(updateFilePath);
    if (!await file.exists()) {
      throw Exception('更新文件不存在: $updateFilePath');
    }

    print('开始安装 Windows 更新: $updateFilePath');
    final fileExtension = path.extension(updateFilePath).toLowerCase();
    print('文件扩展名: $fileExtension');

    // Windows 通常是 .exe、.msi 或 .zip
    if (fileExtension == '.zip') {
      return await _installFromZIP(updateFilePath, isWindows: true);
    } else if (updateFilePath.endsWith('.exe')) {
      // 执行安装程序（静默安装）
      // 注意：.exe 和 .msi 安装程序通常会自动处理重启，返回 null
      final process = await Process.start(
        updateFilePath,
        ['/S'], // 静默安装参数
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
      await process.exitCode;
      return null; // 安装程序会自动处理重启
    } else if (updateFilePath.endsWith('.msi')) {
      // MSI 安装
      final process = await Process.start(
        'msiexec',
        ['/i', updateFilePath, '/quiet', '/norestart'],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
      await process.exitCode;
      return null; // 安装程序会自动处理重启
    } else {
      throw Exception('不支持的 Windows 更新文件格式: $fileExtension');
    }
  }

  /// Windows 从 ZIP 安装
  /// 返回应用安装目录路径
  Future<String?> _installWindowsFromZIP(
      Directory extractDir, List<FileSystemEntity> topLevelEntities) async {
    print('查找 Windows 应用文件...');

    // 查找 .exe 文件（主程序）
    File? exeFile;
    
    // 首先在顶层查找
    for (final entity in topLevelEntities) {
      if (entity is File && entity.path.endsWith('.exe')) {
        final fileName = path.basename(entity.path);
        // 查找主程序（通常是应用名称.exe）
        if (fileName.contains('publish_unity_hot_assets') ||
            !fileName.contains('flutter_')) {
          exeFile = entity;
          print('找到主程序: ${exeFile.path}');
          break;
        }
      }
    }

    if (exeFile == null) {
      // 如果没找到，尝试查找任何 .exe 文件（顶层）
      for (final entity in topLevelEntities) {
        if (entity is File && entity.path.endsWith('.exe')) {
          exeFile = entity;
          print('找到可执行文件: ${exeFile.path}');
          break;
        }
      }
    }

    // 如果顶层没找到，递归查找子目录
    if (exeFile == null) {
      print('顶层未找到，递归查找子目录...');
      File? foundExe; // 用于存储找到的第一个 .exe 文件（如果不是主程序）
      await for (final entity in extractDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.exe')) {
          final fileName = path.basename(entity.path);
          // 优先查找主程序
          if (fileName.contains('publish_unity_hot_assets') ||
              !fileName.contains('flutter_')) {
            exeFile = entity;
            print('✅ 在子目录中找到主程序: ${exeFile.path}');
            break;
          } else if (foundExe == null) {
            // 保存找到的第一个 .exe 文件（作为备选）
            foundExe = entity;
          }
        }
      }
      // 如果没找到主程序，但找到了其他 .exe 文件，使用它
      if (exeFile == null && foundExe != null) {
        exeFile = foundExe;
        print('✅ 在子目录中找到可执行文件: ${exeFile.path}');
      }
    }

    if (exeFile == null) {
      print('错误: 在 ZIP 中未找到 .exe 文件');
      print('解压目录内容（顶层）:');
      for (final entity in topLevelEntities) {
        final entityType = entity is Directory ? '目录' : '文件';
        print('  - ${entity.path} ($entityType)');
      }
      print('解压目录内容（递归）:');
      await for (final entity in extractDir.list(recursive: true)) {
        final entityType = entity is Directory ? '目录' : '文件';
        print('  - ${entity.path} ($entityType)');
      }
      throw Exception('在 ZIP 中未找到 .exe 文件');
    }

    // 验证 .exe 文件是否存在
    if (!await exeFile.exists()) {
      throw Exception('找到的 .exe 文件不存在: ${exeFile.path}');
    }

    // 打印找到的文件详细信息
    print('✅ 找到 .exe 文件:');
    print('  完整路径: ${exeFile.path}');
    print('  文件名: ${path.basename(exeFile.path)}');
    print('  文件扩展名: ${path.extension(exeFile.path)}');
    print('  文件是否存在: ${await exeFile.exists()}');
    print('  文件大小: ${await exeFile.length()} 字节');

    // 获取应用安装目录（通常是用户目录下的 AppData/Local）
    final appDataDir = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        'C:\\Users\\${Platform.environment['USERNAME']}\\AppData\\Local';
    final appName = path.basenameWithoutExtension(exeFile.path);
    final targetDir = Directory(path.join(appDataDir, appName));

    print('目标安装目录: ${targetDir.path}');

    // 如果目录已存在，先删除
    if (await targetDir.exists()) {
      print('删除旧应用目录: ${targetDir.path}');
      try {
        await targetDir.delete(recursive: true);
      } catch (e) {
        print('删除旧目录失败，尝试强制删除: $e');
        // Windows 下可能需要强制删除
        final deleteResult = await Process.run(
          'cmd',
          ['/c', 'rmdir', '/s', '/q', targetDir.path],
          runInShell: true,
        );
        if (deleteResult.exitCode != 0) {
          throw Exception('删除旧应用目录失败: ${deleteResult.stderr}');
        }
      }
    }

    // 创建目标目录
    await targetDir.create(recursive: true);

    // 复制整个解压目录到目标目录
    print('复制应用到安装目录...');
    for (final entity in topLevelEntities) {
      final fileName = path.basename(entity.path);
      final targetPath = path.join(targetDir.path, fileName);

      if (entity is File) {
        // 复制文件
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        // 复制目录 - Windows 下使用 xcopy 命令更可靠
        final targetEntity = Directory(targetPath);
        if (await targetEntity.exists()) {
          await targetEntity.delete(recursive: true);
        }

        // 使用 xcopy 复制目录
        final copyResult = await Process.run(
          'xcopy',
          ['/E', '/I', '/Y', entity.path, targetPath],
          runInShell: true,
        );
        if (copyResult.exitCode != 0) {
          print('xcopy 失败，尝试递归复制: ${copyResult.stderr}');
          // 如果 xcopy 失败，使用递归复制
          await _copyDirectoryWindows(entity, Directory(targetPath));
        }
      }
    }

    print('应用安装成功: ${targetDir.path}');
    return targetDir.path;
  }

  /// Windows 递归复制目录
  Future<void> _copyDirectoryWindows(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      final targetPath = path.join(target.path, path.basename(entity.path));
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectoryWindows(entity, Directory(targetPath));
      }
    }
  }

  /// macOS 从 ZIP 安装
  /// 返回新应用的路径
  Future<String?> _installMacOSFromZIP(
      Directory extractDir, List<FileSystemEntity> topLevelEntities) async {
    print('查找 macOS 应用文件...');

    // 查找 .app 文件
    Directory? appFile;

    // 先检查顶层目录
    print('检查顶层目录中的 .app 文件...');
    for (final entity in topLevelEntities) {
      final entityPath = entity.path;

      // 忽略 __MACOSX 目录
      if (entityPath.contains('__MACOSX')) {
        continue;
      }

      // 检查是否是 .app 目录
      if (entityPath.endsWith('.app') && entity is Directory) {
        print('找到 .app 文件: $entityPath');

        // 验证是否是有效的 .app bundle
        final contentsDir = Directory(path.join(entityPath, 'Contents'));
        final hasContents = await contentsDir.exists();

        if (hasContents) {
          appFile = entity;
          print('✅ 找到有效的应用（包含 Contents）: ${appFile.path}');
          break;
        } else {
          // 即使没有 Contents 目录也使用
          if (appFile == null) {
            appFile = entity;
            print('⚠️ 使用找到的 .app（缺少 Contents 验证）: ${appFile.path}');
          }
        }
      }
    }

    // 如果顶层没找到，递归查找子目录
    if (appFile == null) {
      print('顶层未找到，递归查找子目录...');
      await for (final entity in extractDir.list(recursive: true)) {
        final entityPath = entity.path;

        // 忽略 __MACOSX 目录和以 ._ 开头的文件
        if (entityPath.contains('__MACOSX') ||
            entityPath.contains('/._') ||
            path.basename(entityPath).startsWith('._')) {
          continue;
        }

        // 检查是否是 .app 目录
        if (entityPath.endsWith('.app') && entity is Directory) {
          print('找到 .app 文件: $entityPath');

          // 验证是否是有效的 .app bundle
          final contentsDir = Directory(path.join(entityPath, 'Contents'));
          final hasContents = await contentsDir.exists();

          if (hasContents) {
            appFile = entity;
            print('✅ 找到有效的应用（包含 Contents）: ${appFile.path}');
            break;
          } else {
            // 如果没有 Contents 目录，仍然使用
            if (appFile == null) {
              appFile = entity;
              print('⚠️ 使用找到的 .app（缺少 Contents 验证）: ${appFile.path}');
            }
          }
        }
      }
    }

    if (appFile == null) {
      print('错误: 在 ZIP 中未找到 .app 文件');
      print('解压目录内容（顶层）:');
      for (final entity in topLevelEntities) {
        final entityType = entity is Directory ? '目录' : '文件';
        print('  - ${entity.path} ($entityType)');
      }
      throw Exception('在 ZIP 中未找到 .app 文件，请检查 ZIP 文件格式');
    }

    // 复制应用到 Applications 目录
    final applicationsDir = Directory('/Applications');
    final appName = path.basename(appFile.path);
    final targetApp = Directory(path.join(applicationsDir.path, appName));

    print('目标路径: ${targetApp.path}');

    // 如果应用已存在，先删除
    if (await targetApp.exists()) {
      print('删除旧应用: ${targetApp.path}');
      final rmResult = await Process.run('rm', ['-rf', targetApp.path]);
      if (rmResult.exitCode != 0) {
        throw Exception('删除旧应用失败: ${rmResult.stderr}');
      }
    }

    // 复制新应用（使用 ditto 命令）
    print('复制应用到 /Applications...');
    final copyResult = await Process.run(
      'ditto',
      [appFile.path, targetApp.path],
    );

    if (copyResult.exitCode != 0) {
      throw Exception('复制应用失败: ${copyResult.stderr}');
    }

    print('应用安装成功: ${targetApp.path}');

    // 返回新应用的路径，用于重启
    return targetApp.path;
  }

  /// 比较版本号
  /// 返回负数表示 v1 < v2，返回 0 表示 v1 == v2，返回正数表示 v1 > v2
  int _compareVersions(String v1, String v2) {
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
}
