import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:dio/dio.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_auth_service.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/appwrite_config.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';

typedef AppwriteDownloadProgress = void Function({
  required String phase,
  required String message,
  double? percent,
});

/// 从 Appwrite Storage 把临时文件下载到本机（与 workspace APK 下载同源）。
Future<void> downloadAppwriteTempFile({
  required String downloadUrl,
  required String fileId,
  required String savePath,
  String label = '文件',
  AppwriteDownloadProgress? onProgress,
}) async {
  final url = downloadUrl.isNotEmpty
      ? downloadUrl
      : (fileId.isNotEmpty ? _appwriteFileDownloadUrl(fileId) : '');
  if (url.isEmpty) {
    throw StateError('无法下载：downloadUrl 与 fileId 均不可用');
  }

  final storage = Storage(appwriteAuth.client);
  int? sizeOriginal;
  if (fileId.isNotEmpty) {
    try {
      final fileInfo = await storage.getFile(
        bucketId: AppwriteConfig.hotUpdateBucketId,
        fileId: fileId,
      );
      if (fileInfo.sizeOriginal > 0) {
        sizeOriginal = fileInfo.sizeOriginal;
      }
    } catch (e) {
      // ignore: avoid_print
      print('获取 Appwrite 文件元数据失败，进度改用 Content-Length: $e');
    }
  }

  final headers = await appwriteAuth.storageDownloadHeaders(Uri.parse(url));

  try {
    DateTime? lastProgressAt;
    await global.dio.download(
      url,
      savePath,
      options: Options(headers: headers),
      onReceiveProgress: (received, total) {
        final knownTotal = (sizeOriginal != null && sizeOriginal > 0)
            ? sizeOriginal
            : (total > 0 ? total : 0);
        final isComplete = knownTotal > 0 ? received >= knownTotal : false;
        final now = DateTime.now();
        final shouldEmit = lastProgressAt == null ||
            now.difference(lastProgressAt!).inMilliseconds >= 200 ||
            isComplete;
        if (!shouldEmit) return;
        lastProgressAt = now;

        final receivedMb = (received / 1024 / 1024).toStringAsFixed(2);
        final totalText = knownTotal > 0
            ? ' / ${(knownTotal / 1024 / 1024).toStringAsFixed(2)}MB'
            : 'MB';
        final percent = knownTotal > 0
            ? (received / knownTotal * 100).clamp(0, 100).toDouble()
            : null;
        onProgress?.call(
          phase: 'downloading',
          message: '[$receivedMb$totalText] 正在下载$label...',
          percent: percent,
        );
      },
    );
    return;
  } catch (e) {
    // ignore: avoid_print
    print('dio 下载失败，回退 Storage.getFileDownload: $e');
  }

  if (fileId.isEmpty) {
    throw StateError('下载失败且无法回退：缺少 fileId');
  }
  onProgress?.call(
    phase: 'downloading',
    message: '正在从 Appwrite Storage 下载$label...',
    percent: null,
  );
  final bytes = await storage.getFileDownload(
    bucketId: AppwriteConfig.hotUpdateBucketId,
    fileId: fileId,
  );
  await File(savePath).writeAsBytes(bytes, flush: true);
  onProgress?.call(
    phase: 'downloading',
    message: '下载完成 (${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB)',
    percent: 100,
  );
}

String _appwriteFileDownloadUrl(String fileId) {
  final base = AppwriteConfig.endpoint.replaceAll(RegExp(r'/+$'), '');
  return '$base/storage/buckets/${AppwriteConfig.hotUpdateBucketId}'
      '/files/$fileId/download'
      '?project=${AppwriteConfig.projectId}';
}
