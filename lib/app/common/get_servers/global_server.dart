import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins_api.dart';

GlobalServer get global => Get.find();

class GlobalServer extends GetxService {
  final dio = Dio();
  String? token;
  DateTime? tokenExpireTime; // Token过期时间
  String? gmallUrl;
  Environment? currentEnvironment;
  bool isIntranetJenkinsMode = true;

  JenkinsApi? jenkinsApi;

  Future<Response<T>> post<T>({
    required String path,
    required Object? data,
    void Function(int, int)? onSendProgress,
    Map<String, dynamic>? headers,
  }) async {
    final url = _gmallUrl(path);
    print(url);
    print(data);
    final res = await dio
        .post<T>(
      url,
      data: data,
      options: Options(
        headers: {'x-access-token': token, ...headers ?? {}},
      ),
      onSendProgress: onSendProgress,
    )
        .catchError((e) {
      print('请求失败 - URL: $url');
      print('请求失败 - 错误信息: $e');
      // 创建一个包含URL信息的错误
      if (e is DioException) {
        final errorMessage =
            '请求失败\nURL: $url\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception('请求失败\nURL: $url\n错误: $e');
      }
    });
    print(res.data);
    return res;
  }

  Future<Map> postData({
    required String path,
    required Map<String, dynamic> data,
    void Function(int, int)? onSendProgress,
  }) async {
    final res = await post(
      path: path,
      data: data,
      onSendProgress: onSendProgress,
    );
    final success = JSON(res.data)['success'].boolValue;
    final message = JSON(res.data).stringValue;
    if (!success) {
      throw Exception(message);
    }
    return JSON(res.data)['data'].mapValue;
  }

  String _gmallUrl(String path) {
    // return 'http://frontmanager-sit.winnerapp.cn:8000$path';
    return '$gmallUrl$path';
  }

  /// 设置token和过期时间（5小时后过期）
  void setToken(String tokenValue) {
    token = tokenValue;
    // Token有效期为5小时
    tokenExpireTime = DateTime.now().add(const Duration(hours: 5));
  }

  /// 检查token是否有效
  /// 返回true表示token有效，false表示token无效或不存在
  bool isTokenValid() {
    // 如果token不存在，返回false
    if (token == null || token!.isEmpty) {
      return false;
    }

    // 如果过期时间不存在，返回false
    if (tokenExpireTime == null) {
      return false;
    }

    // 检查是否已过期
    return DateTime.now().isBefore(tokenExpireTime!);
  }

  /// 获取token剩余有效时间（小时）
  /// 返回null表示token不存在或已过期
  double? getTokenRemainingHours() {
    if (token == null || token!.isEmpty || tokenExpireTime == null) {
      return null;
    }

    final now = DateTime.now();
    if (now.isAfter(tokenExpireTime!)) {
      return null; // 已过期
    }

    final remaining = tokenExpireTime!.difference(now);
    return remaining.inMinutes / 60.0; // 转换为小时
  }
}
