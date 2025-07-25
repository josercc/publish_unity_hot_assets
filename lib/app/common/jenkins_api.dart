import 'dart:convert';
import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:dio/dio.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';

class JenkinsApi {
  final String jenkinsUrl;
  final String jenkinsUserName;
  final String jenkinsPassword;

  JenkinsApi({
    required this.jenkinsUrl,
    required this.jenkinsUserName,
    required this.jenkinsPassword,
  });

  // 获取Base64编码的认证字符串
  String getAuthHeader() {
    final String authString = '$jenkinsUserName:$jenkinsPassword';
    final List<int> authBytes = utf8.encode(authString);
    return 'Basic ${base64Encode(authBytes)}';
  }

  /// 验证登录
  Future<bool> verifyLogin() async {
    final res = await global.dio
        .get(
      '$jenkinsUrl/user/$jenkinsUserName/api/json?pretty=true',
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      throw e;
    });
    final property = JSON(res.data)['property'].listValue;
    return property.isNotEmpty;
  }

  /// 下载zip包
  Future<void> downloadZipUrl({
    required String platform,
    required String buildConfiguration,
    required String zipPath,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final zipUrl =
        "$jenkinsUrl/job/build_unity_hot_asset/ws/HotUpdate/${platform.toLowerCase()}/$buildConfiguration/${platform.toUpperCase()}/UploadAssets/*zip*/UploadAssets.zip";
    print(zipUrl);
    final zipFile = File(zipPath);
    if (await zipFile.exists()) {
      throw Exception("$zipPath文件已存在");
    }

    await global.dio.downloadUri(
      Uri.parse(zipUrl),
      zipFile.path,
      onReceiveProgress: onReceiveProgress,
      options: Options(headers: {
        'Authorization': getAuthHeader(),
      }),
    );
  }

  /// 开启打包
  Future<bool> startBuild({
    required String platform,
    required String buildConfiguration,
    required String branch,
  }) async {
    final url = '$jenkinsUrl/job/build_unity_hot_asset/buildWithParameters';
    print(url);
    final res = await global.dio
        .post(
      url,
      queryParameters: {
        'platform': platform.toLowerCase(),
        'build_type': buildConfiguration,
        'branch': branch,
      },
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      print(e.toString());
      throw e;
    });
    return res.statusCode == 201;
  }

  /// 获取最后一个构建号
  Future<int> getLastBuildNumber() async {
    final res = await global.dio.get(
      '$jenkinsUrl/job/build_unity_hot_asset/lastBuild/api/json?pretty=true',
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    );
    int? lastBuildNumber = JSON(res.data)['number'].int;
    if (lastBuildNumber == null) {
      throw '获取最后一个构建号失败';
    }
    return lastBuildNumber;
  }

  /// 查询构建结果
  Future<String?> queryBuildResult({
    required int buildNumber,
  }) async {
    final res = await global.dio.get(
      '$jenkinsUrl/job/build_unity_hot_asset/$buildNumber/api/json?pretty=true',
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    );
    return JSON(res.data)['result'].string;
  }

  /// 查询默认分支
  Future<String?> queryDefaultBranch() async {
    final res = await global.dio.get(
      '$jenkinsUrl/job/build_unity_hot_asset/api/json?pretty=true',
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    );
    final property = JSON(res.data)['property'].listValue;
    if (property.isEmpty) {
      throw '查询默认分支失败';
    }
    final parameterDefinitions =
        JSON(property[0])['parameterDefinitions'].listValue;
    return parameterDefinitions
        .map((e) {
          final defaultParameterValue =
              JSON(e)['defaultParameterValue'].mapValue;
          final name = JSON(e)['name'].stringValue;
          if (name == 'branch') {
            return defaultParameterValue['value'];
          }
          return null;
        })
        .whereType<String>()
        .firstOrNull;
  }
}
