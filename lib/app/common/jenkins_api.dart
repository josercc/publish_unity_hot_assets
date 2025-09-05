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

  /// 获取分支列表
  Future<List<String>> getBranchList() async {
    try {
      // 使用完整的API地址获取任务信息
      final res = await global.dio.get(
        '$jenkinsUrl/job/build_unity_hot_asset/api/json?pretty=true',
        options: Options(
          headers: {
            'Authorization': getAuthHeader(),
          },
        ),
      );

      print('Jenkins API响应: ${res.data}');

      // 首先尝试从actions数组中查找参数定义
      final actions = JSON(res.data)['actions'].listValue;
      print('Actions: $actions');

      for (final action in actions) {
        final actionClass = JSON(action)['_class'].stringValue;
        print('Action class: $actionClass');

        // 查找参数定义属性
        if (actionClass == 'hudson.model.ParametersDefinitionProperty') {
          final parameterDefinitions =
              JSON(action)['parameterDefinitions'].listValue;
          print('参数定义: $parameterDefinitions');

          // 查找branch参数的定义
          for (final param in parameterDefinitions) {
            final name = JSON(param)['name'].stringValue;
            final paramClass = JSON(param)['_class'].stringValue;
            print('参数名称: $name, 类型: $paramClass');

            if (name == 'branch') {
              // 根据参数类型处理
              if (paramClass == 'hudson.model.ChoiceParameterDefinition') {
                final choices = JSON(param)['choices'].listValue;
                print('choices列表: $choices');
                return choices
                    .map((e) => e.toString())
                    .whereType<String>()
                    .toList();
              } else if (paramClass ==
                  'hudson.model.StringParameterDefinition') {
                // 如果是字符串参数，尝试获取默认值
                final defaultValue =
                    JSON(param)['defaultParameterValue']['value'].stringValue;
                if (defaultValue.isNotEmpty) {
                  return [defaultValue];
                }
              }
            }
          }
        }
      }

      // 如果actions中没有找到，尝试从property数组中查找
      final properties = JSON(res.data)['property'].listValue;
      print('Properties: $properties');

      for (final property in properties) {
        final propertyClass = JSON(property)['_class'].stringValue;
        print('Property class: $propertyClass');

        // 查找参数定义属性
        if (propertyClass == 'hudson.model.ParametersDefinitionProperty') {
          final parameterDefinitions =
              JSON(property)['parameterDefinitions'].listValue;
          print('参数定义: $parameterDefinitions');

          // 查找branch参数的定义
          for (final param in parameterDefinitions) {
            final name = JSON(param)['name'].stringValue;
            final paramClass = JSON(param)['_class'].stringValue;
            print('参数名称: $name, 类型: $paramClass');

            if (name == 'branch') {
              // 根据参数类型处理
              if (paramClass == 'hudson.model.ChoiceParameterDefinition') {
                final choices = JSON(param)['choices'].listValue;
                print('choices列表: $choices');
                return choices
                    .map((e) => e.toString())
                    .whereType<String>()
                    .toList();
              } else if (paramClass ==
                  'hudson.model.StringParameterDefinition') {
                // 如果是字符串参数，尝试获取默认值
                final defaultValue =
                    JSON(param)['defaultParameterValue']['value'].stringValue;
                if (defaultValue.isNotEmpty) {
                  return [defaultValue];
                }
              }
            }
          }
        }
      }

      print('没有找到branch参数定义');
      return [];
    } catch (e) {
      print('获取分支列表时发生错误: $e');
      return [];
    }
  }
}
