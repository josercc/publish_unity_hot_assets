import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins_api.dart';

GlobalServer get global => Get.find();

class GlobalServer extends GetxService {
  final dio = Dio();
  String? token;
  String? gmallUrl;
  Environment? currentEnvironment;

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
}
