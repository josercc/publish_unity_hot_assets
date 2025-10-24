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
    final url = '$jenkinsUrl/user/$jenkinsUserName/api/json?pretty=true';
    print('Jenkins验证登录 - 请求路径: $url');
    print('Jenkins验证登录 - 用户名: $jenkinsUserName');

    final res = await global.dio
        .get(
      url,
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      print('Jenkins验证登录失败 - 请求路径: $url');
      print('Jenkins验证登录失败 - 用户名: $jenkinsUserName');
      print('Jenkins验证登录失败 - 错误信息: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins验证登录失败\n请求路径: $url\n用户名: $jenkinsUserName\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins验证登录失败\n请求路径: $url\n用户名: $jenkinsUserName\n错误: $e');
      }
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
    print('Jenkins下载资源 - 请求路径: $zipUrl');
    print('Jenkins下载资源 - 平台: $platform');
    print('Jenkins下载资源 - 构建配置: $buildConfiguration');
    print('Jenkins下载资源 - 本地保存路径: $zipPath');

    final zipFile = File(zipPath);
    if (await zipFile.exists()) {
      throw Exception("本地文件已存在: $zipPath");
    }

    try {
      await global.dio.downloadUri(
        Uri.parse(zipUrl),
        zipFile.path,
        onReceiveProgress: onReceiveProgress,
        options: Options(headers: {
          'Authorization': getAuthHeader(),
        }),
      );
      print('Jenkins下载资源成功 - 保存到: $zipPath');
    } catch (e) {
      print('Jenkins下载资源失败 - 请求路径: $zipUrl');
      print('Jenkins下载资源失败 - 平台: $platform');
      print('Jenkins下载资源失败 - 构建配置: $buildConfiguration');
      print('Jenkins下载资源失败 - 错误信息: $e');
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          throw Exception(
              '资源文件不存在，可能构建尚未完成或构建失败\n请求路径: $zipUrl\n平台: $platform\n构建配置: $buildConfiguration\nHTTP状态码: 404\n请检查Jenkins构建状态');
        }
        final errorMessage =
            'Jenkins下载资源失败\n请求路径: $zipUrl\n平台: $platform\n构建配置: $buildConfiguration\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins下载资源失败\n请求路径: $zipUrl\n平台: $platform\n构建配置: $buildConfiguration\n错误: $e');
      }
    }
  }

  /// 开启打包
  Future<bool> startBuild({
    required String platform,
    required String buildConfiguration,
    required String branch,
  }) async {
    final url = '$jenkinsUrl/job/build_unity_hot_asset/buildWithParameters';
    final queryParams = {
      'platform': platform.toLowerCase(),
      'build_type': buildConfiguration,
      'branch': branch,
    };

    print('Jenkins开启打包 - 请求路径: $url');
    print('Jenkins开启打包 - 平台: $platform');
    print('Jenkins开启打包 - 构建配置: $buildConfiguration');
    print('Jenkins开启打包 - 分支: $branch');
    print('Jenkins开启打包 - 查询参数: $queryParams');

    final res = await global.dio
        .post(
      url,
      queryParameters: queryParams,
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      print('Jenkins开启打包失败 - 请求路径: $url');
      print('Jenkins开启打包失败 - 平台: $platform');
      print('Jenkins开启打包失败 - 构建配置: $buildConfiguration');
      print('Jenkins开启打包失败 - 分支: $branch');
      print('Jenkins开启打包失败 - 查询参数: $queryParams');
      print('Jenkins开启打包失败 - 错误信息: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins开启打包失败\n请求路径: $url\n平台: $platform\n构建配置: $buildConfiguration\n分支: $branch\n查询参数: $queryParams\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins开启打包失败\n请求路径: $url\n平台: $platform\n构建配置: $buildConfiguration\n分支: $branch\n查询参数: $queryParams\n错误: $e');
      }
    });

    final success = res.statusCode == 201;
    print('Jenkins开启打包结果 - HTTP状态码: ${res.statusCode}');
    print('Jenkins开启打包结果 - 成功: $success');
    return success;
  }

  /// 获取最后一个构建号
  Future<int> getLastBuildNumber() async {
    final url =
        '$jenkinsUrl/job/build_unity_hot_asset/lastBuild/api/json?pretty=true';
    print('Jenkins获取构建号 - 请求路径: $url');

    final res = await global.dio
        .get(
      url,
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      print('Jenkins获取构建号失败 - 请求路径: $url');
      print('Jenkins获取构建号失败 - 错误信息: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins获取构建号失败\n请求路径: $url\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception('Jenkins获取构建号失败\n请求路径: $url\n错误: $e');
      }
    });
    int? lastBuildNumber = JSON(res.data)['number'].int;
    print('Jenkins获取构建号成功 - 构建号: $lastBuildNumber');
    if (lastBuildNumber == null) {
      throw '获取最后一个构建号失败\n请求路径: $url\n响应数据: ${res.data}';
    }
    return lastBuildNumber;
  }

  /// 查询构建结果
  Future<String?> queryBuildResult({
    required int buildNumber,
  }) async {
    final url =
        '$jenkinsUrl/job/build_unity_hot_asset/$buildNumber/api/json?pretty=true';
    print('Jenkins查询构建结果 - 请求路径: $url');
    print('Jenkins查询构建结果 - 构建号: $buildNumber');

    final res = await global.dio
        .get(
      url,
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      print('Jenkins查询构建结果失败 - 请求路径: $url');
      print('Jenkins查询构建结果失败 - 构建号: $buildNumber');
      print('Jenkins查询构建结果失败 - 错误信息: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins查询构建结果失败\n请求路径: $url\n构建号: $buildNumber\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins查询构建结果失败\n请求路径: $url\n构建号: $buildNumber\n错误: $e');
      }
    });

    final result = JSON(res.data)['result'].string;
    print('Jenkins查询构建结果成功 - 构建号: $buildNumber, 结果: $result');
    return result;
  }

  /// 查询默认分支
  Future<String?> queryDefaultBranch() async {
    final url = '$jenkinsUrl/job/build_unity_hot_asset/api/json?pretty=true';
    print('Jenkins查询默认分支 - 请求路径: $url');

    final res = await global.dio
        .get(
      url,
      options: Options(
        headers: {
          'Authorization': getAuthHeader(),
        },
      ),
    )
        .catchError((e) {
      print('Jenkins查询默认分支失败 - 请求路径: $url');
      print('Jenkins查询默认分支失败 - 错误信息: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins查询默认分支失败\n请求路径: $url\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception('Jenkins查询默认分支失败\n请求路径: $url\n错误: $e');
      }
    });

    final property = JSON(res.data)['property'].listValue;
    if (property.isEmpty) {
      throw '查询默认分支失败\n请求路径: $url\n响应数据: ${res.data}';
    }
    final parameterDefinitions =
        JSON(property[0])['parameterDefinitions'].listValue;
    final defaultBranch = parameterDefinitions
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

    print('Jenkins查询默认分支成功 - 默认分支: $defaultBranch');
    return defaultBranch;
  }

  /// 获取分支列表
  Future<List<String>> getBranchList() async {
    try {
      final url = '$jenkinsUrl/job/build_unity_hot_asset/api/json?pretty=true';
      print('Jenkins获取分支列表 - 请求路径: $url');

      // 使用完整的API地址获取任务信息
      final res = await global.dio
          .get(
        url,
        options: Options(
          headers: {
            'Authorization': getAuthHeader(),
          },
        ),
      )
          .catchError((e) {
        print('Jenkins获取分支列表失败 - 请求路径: $url');
        print('Jenkins获取分支列表失败 - 错误信息: $e');
        if (e is DioException) {
          final errorMessage =
              'Jenkins获取分支列表失败\n请求路径: $url\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
          throw DioException(
            requestOptions: e.requestOptions,
            response: e.response,
            type: e.type,
            error: errorMessage,
          );
        } else {
          throw Exception('Jenkins获取分支列表失败\n请求路径: $url\n错误: $e');
        }
      });

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
      print('Jenkins获取分支列表成功 - 分支列表: []');
      return [];
    } catch (e) {
      print('获取分支列表时发生错误: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins获取分支列表失败\n请求路径: $jenkinsUrl/job/build_unity_hot_asset/api/json?pretty=true\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins获取分支列表失败\n请求路径: $jenkinsUrl/job/build_unity_hot_asset/api/json?pretty=true\n错误: $e');
      }
    }
  }
}
