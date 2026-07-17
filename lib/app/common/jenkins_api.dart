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

  /// 将 UI/业务平台名映射为 Jenkins 构建参数
  /// HarmonyOS 对应 Jenkins 参数 ohos
  String normalizeJenkinsPlatform(String platform) {
    final lower = platform.toLowerCase();
    if (lower == 'harmonyos') {
      return 'ohos';
    }
    return lower;
  }

  /// 将 UI/业务平台名映射为 Jenkins 产物目录名
  /// HarmonyOS 产物目录为 Harmony
  String jenkinsArtifactPlatformDir(String platform) {
    final lower = platform.toLowerCase();
    if (lower == 'harmonyos' || lower == 'ohos') {
      return 'Harmony';
    }
    return platform.toUpperCase();
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
    required int buildNumber,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final artifactDir = jenkinsArtifactPlatformDir(platform);
    // 构建下载路径：使用新路径结构
    final zipUrl =
        "$jenkinsUrl/job/build_unity_hot_asset/ws/HotUpdate/$buildNumber/$artifactDir/UploadAssets/*zip*/UploadAssets.zip";
    print('Jenkins下载资源 - 请求路径: $zipUrl');
    print('Jenkins下载资源 - 平台: $platform -> $artifactDir');
    print('Jenkins下载资源 - 构建配置: $buildConfiguration');
    print('Jenkins下载资源 - 构建号: $buildNumber');
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
      print('Jenkins下载资源失败 - 构建号: $buildNumber');
      print('Jenkins下载资源失败 - 错误信息: $e');
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          throw Exception(
              '资源文件不存在，可能构建尚未完成或构建失败\n请求路径: $zipUrl\n平台: $platform\n构建配置: $buildConfiguration\n构建号: $buildNumber\nHTTP状态码: 404\n请检查Jenkins构建状态');
        }
        final errorMessage =
            'Jenkins下载资源失败\n请求路径: $zipUrl\n平台: $platform\n构建配置: $buildConfiguration\n构建号: $buildNumber\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins下载资源失败\n请求路径: $zipUrl\n平台: $platform\n构建配置: $buildConfiguration\n构建号: $buildNumber\n错误: $e');
      }
    }
  }

  /// 获取最后一个构建的详细信息（包括参数）
  Future<Map<String, dynamic>?> getLastBuildInfo() async {
    try {
      final url =
          '$jenkinsUrl/job/build_unity_hot_asset/lastBuild/api/json?pretty=true';
      final res = await global.dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': getAuthHeader(),
          },
        ),
      );
      return res.data as Map<String, dynamic>?;
    } catch (e) {
      print('Jenkins获取最后一个构建信息失败: $e');
      return null;
    }
  }

  /// 从构建信息中提取 UID 参数
  String? extractUidFromBuildInfo(Map<String, dynamic>? buildInfo) {
    if (buildInfo == null) return null;

    try {
      final actions = buildInfo['actions'] as List?;
      if (actions == null) return null;

      for (final action in actions) {
        if (action is Map<String, dynamic>) {
          final parameters = action['parameters'] as List?;
          if (parameters != null) {
            for (final param in parameters) {
              if (param is Map<String, dynamic>) {
                final name = param['name'] as String?;
                if (name == 'UID') {
                  return param['value'] as String?;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('提取UID参数失败: $e');
    }

    return null;
  }

  /// 开启打包
  /// 返回构建号，如果查询不到则抛出异常
  /// [onProgress] 可选的进度回调，用于更新状态信息
  /// [shouldCancel] 可选的取消检查函数，返回 true 时终止循环
  Future<int> startBuild({
    required String platform,
    required String buildConfiguration,
    required String branch,
    void Function(String message)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    // 生成当前时间戳作为 UID
    final uid = DateTime.now().millisecondsSinceEpoch.toString();
    print('Jenkins开启打包 - 生成UID: $uid');

    final jenkinsPlatform = normalizeJenkinsPlatform(platform);
    final url = '$jenkinsUrl/job/build_unity_hot_asset/buildWithParameters';
    final queryParams = {
      'platform': jenkinsPlatform,
      'build_type': buildConfiguration,
      'branch': branch,
      'UID': uid, // 添加 UID 参数
    };

    print('Jenkins开启打包 - 请求路径: $url');
    print('Jenkins开启打包 - 平台: $platform -> $jenkinsPlatform');
    print('Jenkins开启打包 - 构建配置: $buildConfiguration');
    print('Jenkins开启打包 - 分支: $branch');
    print('Jenkins开启打包 - UID: $uid');
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
      print('Jenkins开启打包失败 - UID: $uid');
      print('Jenkins开启打包失败 - 查询参数: $queryParams');
      print('Jenkins开启打包失败 - 错误信息: $e');
      if (e is DioException) {
        final errorMessage =
            'Jenkins开启打包失败\n请求路径: $url\n平台: $platform\n构建配置: $buildConfiguration\n分支: $branch\nUID: $uid\n查询参数: $queryParams\nHTTP状态码: ${e.response?.statusCode}\n错误: ${e.message ?? e.toString()}';
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: errorMessage,
        );
      } else {
        throw Exception(
            'Jenkins开启打包失败\n请求路径: $url\n平台: $platform\n构建配置: $buildConfiguration\n分支: $branch\nUID: $uid\n查询参数: $queryParams\n错误: $e');
      }
    });

    final success = res.statusCode == 201;
    print('Jenkins开启打包结果 - HTTP状态码: ${res.statusCode}');
    print('Jenkins开启打包结果 - 响应数据: ${res.data}');
    print('Jenkins开启打包结果 - 响应头: ${res.headers}');
    print('Jenkins开启打包结果 - 成功: $success');

    if (!success) {
      throw Exception(
          'Jenkins开启打包失败\nHTTP状态码: ${res.statusCode}\n响应数据: ${res.data}');
    }

    final progressMessage = '构建请求已发送，开始等待获取构建号（UID: $uid）...';
    print('Jenkins开启打包 - $progressMessage');
    onProgress?.call(progressMessage);

    // 轮询查询最后一个构建的 UID，直到匹配（无限循环等待）
    int? buildNumber;
    int queryCount = 0;
    DateTime startTime = DateTime.now();
    const retryDelay = Duration(seconds: 3);

    while (buildNumber == null) {
      // 检查是否应该取消
      if (shouldCancel != null && shouldCancel()) {
        final cancelMessage = '已取消等待获取构建号（UID: $uid）';
        print('Jenkins开启打包 - $cancelMessage');
        onProgress?.call(cancelMessage);
        throw Exception('等待获取构建号已取消');
      }

      try {
        queryCount++;
        final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;
        final elapsedMinutes = (elapsedSeconds / 60).toStringAsFixed(1);

        String waitMessage;
        if (elapsedSeconds < 60) {
          waitMessage =
              '等待获取构建号中... (第${queryCount}次查询，已等待${elapsedSeconds}秒，UID: $uid)';
        } else {
          waitMessage =
              '等待获取构建号中... (第${queryCount}次查询，已等待${elapsedMinutes}分钟，UID: $uid)';
        }
        print('Jenkins开启打包 - $waitMessage');
        onProgress?.call(waitMessage);

        final buildInfo = await getLastBuildInfo();
        if (buildInfo == null) {
          final noInfoMessage =
              '尚未获取到最后一个构建信息，等待${retryDelay.inSeconds}秒后继续查询...';
          print('Jenkins开启打包 - $noInfoMessage');
          onProgress?.call(noInfoMessage);
          await Future.delayed(retryDelay);
          // 等待后检查是否应该取消
          if (shouldCancel != null && shouldCancel()) {
            final cancelMessage = '已取消等待获取构建号（UID: $uid）';
            print('Jenkins开启打包 - $cancelMessage');
            onProgress?.call(cancelMessage);
            throw Exception('等待获取构建号已取消');
          }
          continue;
        }

        final lastBuildNumber = buildInfo['number'] as int?;
        if (lastBuildNumber == null) {
          final noNumberMessage =
              '最后一个构建没有构建号，等待${retryDelay.inSeconds}秒后继续查询...';
          print('Jenkins开启打包 - $noNumberMessage');
          onProgress?.call(noNumberMessage);
          await Future.delayed(retryDelay);
          // 等待后检查是否应该取消
          if (shouldCancel != null && shouldCancel()) {
            final cancelMessage = '已取消等待获取构建号（UID: $uid）';
            print('Jenkins开启打包 - $cancelMessage');
            onProgress?.call(cancelMessage);
            throw Exception('等待获取构建号已取消');
          }
          continue;
        }

        final lastBuildUid = extractUidFromBuildInfo(buildInfo);
        final queryMessage =
            '查询到最后一个构建号: $lastBuildNumber, UID: $lastBuildUid, 期望UID: $uid';
        print('Jenkins开启打包 - $queryMessage');
        onProgress?.call(queryMessage);

        if (lastBuildUid == uid) {
          // UID 匹配成功，立即设置构建号并退出循环
          buildNumber = lastBuildNumber;
          final successMessage = '✅ UID匹配成功！获取到构建号: $buildNumber';
          print('Jenkins开启打包 - $successMessage');
          onProgress?.call(successMessage);
          // 立即退出循环，不再继续等待
          break;
        } else {
          // UID 不匹配，继续等待
          final mismatchMessage =
              '⏳ UID不匹配（当前: $lastBuildUid, 期望: $uid），继续等待...等待${retryDelay.inSeconds}秒后继续查询...';
          print('Jenkins开启打包 - $mismatchMessage');
          onProgress?.call(mismatchMessage);
          await Future.delayed(retryDelay);
          // 等待后检查是否应该取消
          if (shouldCancel != null && shouldCancel()) {
            final cancelMessage = '已取消等待获取构建号（UID: $uid）';
            print('Jenkins开启打包 - $cancelMessage');
            onProgress?.call(cancelMessage);
            throw Exception('等待获取构建号已取消');
          }
          // 继续下一次循环
          continue;
        }
      } catch (e) {
        // 如果是取消异常，直接抛出不再继续
        if (e.toString().contains('等待获取构建号已取消')) {
          rethrow;
        }
        final errorMessage = '查询构建信息失败: $e，等待${retryDelay.inSeconds}秒后继续查询...';
        print('Jenkins开启打包 - $errorMessage');
        onProgress?.call(errorMessage);
        // 即使查询失败也继续等待，不抛出异常
        await Future.delayed(retryDelay);
        // 等待后检查是否应该取消
        if (shouldCancel != null && shouldCancel()) {
          final cancelMessage = '已取消等待获取构建号（UID: $uid）';
          print('Jenkins开启打包 - $cancelMessage');
          onProgress?.call(cancelMessage);
          throw Exception('等待获取构建号已取消');
        }
        // 继续下一次循环
        continue;
      }
    }

    // 循环退出时，buildNumber 一定已经被设置（因为循环条件是 buildNumber == null）
    // 当 UID 匹配成功时，会执行 buildNumber = lastBuildNumber; break; 退出循环
    return buildNumber;
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
