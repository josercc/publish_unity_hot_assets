import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:package_info_plus/package_info_plus.dart';

/// 日志导出工具类
class LogExporter {
  /// 导出更新错误日志
  /// [error] 错误信息
  /// [stackTrace] 堆栈跟踪
  /// [additionalInfo] 额外信息（可选）
  /// 返回保存的文件路径
  static Future<String> exportUpdateErrorLog({
    required dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? additionalInfo,
  }) async {
    try {
      // 获取应用信息
      final packageInfo = await PackageInfo.fromPlatform();

      // 获取文档目录
      final documentsDir = await getApplicationDocumentsDirectory();

      // 创建日志目录
      final logDir = Directory(path.join(documentsDir.path, 'logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      // 生成日志文件名（带时间戳）
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final logFileName = 'update_error_$timestamp.txt';
      final logFilePath = path.join(logDir.path, logFileName);

      // 构建日志内容
      final logContent = StringBuffer();

      // 标题
      logContent.writeln('=' * 60);
      logContent.writeln('应用更新错误日志');
      logContent.writeln('=' * 60);
      logContent.writeln('');

      // 时间戳
      logContent.writeln('生成时间: ${now.toString()}');
      logContent.writeln('');

      // 应用信息
      logContent.writeln('应用信息:');
      logContent.writeln('  应用名称: ${packageInfo.appName}');
      logContent.writeln('  版本: ${packageInfo.version}');
      logContent.writeln('  构建号: ${packageInfo.buildNumber}');
      logContent.writeln('  包名: ${packageInfo.packageName}');
      logContent.writeln('');

      // 系统信息
      logContent.writeln('系统信息:');
      logContent.writeln('  操作系统: ${Platform.operatingSystem}');
      logContent.writeln('  系统版本: ${Platform.operatingSystemVersion}');
      logContent.writeln('  本地化: ${Platform.localeName}');
      logContent.writeln('');

      // 错误信息
      logContent.writeln('错误信息:');
      logContent.writeln('  ${error.toString()}');
      logContent.writeln('');

      // 堆栈跟踪
      if (stackTrace != null) {
        logContent.writeln('堆栈跟踪:');
        logContent.writeln(stackTrace.toString());
        logContent.writeln('');
      }

      // 额外信息
      if (additionalInfo != null && additionalInfo.isNotEmpty) {
        logContent.writeln('额外信息:');
        additionalInfo.forEach((key, value) {
          logContent.writeln('  $key: $value');
        });
        logContent.writeln('');
      }

      // 环境变量（仅Windows，用于调试）
      if (Platform.isWindows) {
        logContent.writeln('环境变量（部分）:');
        final envVars = Platform.environment;
        final relevantVars = [
          'LOCALAPPDATA',
          'APPDATA',
          'USERPROFILE',
          'TEMP',
          'TMP',
          'PATH',
        ];
        for (final varName in relevantVars) {
          if (envVars.containsKey(varName)) {
            logContent.writeln('  $varName: ${envVars[varName]}');
          }
        }
        logContent.writeln('');
      }

      // 分隔线
      logContent.writeln('=' * 60);
      logContent.writeln('日志结束');
      logContent.writeln('=' * 60);

      // 写入文件（使用默认UTF-8编码）
      final logFile = File(logFilePath);
      await logFile.writeAsString(logContent.toString());

      return logFilePath;
    } catch (e) {
      // 如果导出失败，抛出异常
      throw Exception('导出日志失败: $e');
    }
  }

  /// 打开文件所在目录（仅Windows）
  static Future<void> openFileLocation(String filePath) async {
    if (Platform.isWindows) {
      try {
        // 使用 explorer 打开文件所在目录
        await Process.run(
          'explorer',
          ['/select,', filePath],
        );
      } catch (e) {
        print('打开文件位置失败: $e');
      }
    } else if (Platform.isMacOS) {
      try {
        // macOS 使用 open 命令
        final dir = path.dirname(filePath);
        await Process.run('open', [dir]);
      } catch (e) {
        print('打开文件位置失败: $e');
      }
    }
  }
}
