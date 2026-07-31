import 'dart:convert';

import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server_service.dart';
import 'package:publish_unity_hot_assets/app/common/environment.dart';
import 'package:publish_unity_hot_assets/app/common/get_servers/global_server.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_historical_task.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_parameter.dart';
import 'package:publish_unity_hot_assets/app/common/jenkins/jenkins_job_run_status.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/jenkins_workload_service.dart';
import 'package:publish_unity_hot_assets/app/common/ntfy/ntfy_agent_client.dart';

/// 经 ntfy Agent 查询 Jenkins Job 参数定义。
class JenkinsJobParamsService {
  JenkinsJobParamsService({NtfyAgentClient? client})
      : _client = client ?? NtfyAgentClient() {
    _workload = JenkinsWorkloadService(client: _client);
  }

  final NtfyAgentClient _client;
  late final JenkinsWorkloadService _workload;

  /// crumb + 会话 Cookie 短时缓存，避免每个 ActiveChoices / 触发都再打一次。
  final _crumbCache = <String, _CachedCrumb>{};
  static const _crumbTtl = Duration(minutes: 5);

  /// 常用 Job 名。
  static const jobUnityCache = 'build_unity_cache';
  static const jobUnityFirstPackage = 'build_unity_first_package';
  static const jobUnityHotAsset = 'build_unity_hot_asset';
  static const jobWinnerAppBinary = 'build_winner_app_binary_2.0';

  /// 任务用机：首页有选中则用选中机，否则自动分配最闲机。
  Future<PackagingServer?> resolveTaskServer({
    Environment? environment,
  }) async {
    if (packagingServers.activeServers.isEmpty) {
      await packagingServers.fetchActiveServers();
    }
    final manual = packagingServers.selectedServer;
    if (manual != null) {
      // ignore: avoid_print
      print(
        '[JobParams] use selected server=${manual.displayName} '
        'tag=${manual.tag}',
      );
      return manual;
    }
    return pickMostIdleServer(environment: environment);
  }

  /// 从打包机列表选最闲的一台：优先测试打包机（tag=test），再按工作负载排序。
  Future<PackagingServer?> pickMostIdleServer({
    Environment? environment,
  }) async {
    if (packagingServers.activeServers.isEmpty) {
      await packagingServers.fetchActiveServers();
    }

    final online = packagingServers.activeServers
        .where((s) => s.active && s.online && s.url.isNotEmpty)
        .toList();
    if (online.isEmpty) {
      // 无在线机时仍给一个 active 兜底，由上层报离线
      final active = packagingServers.activeServers
          .where((s) => s.active && s.url.isNotEmpty)
          .toList();
      return active.isEmpty ? null : active.first;
    }

    // 优先测试打包机；没有在线测试机再用全部在线机
    final testPool =
        online.where((s) => s.tag.toLowerCase() == 'test').toList();
    final pool = testPool.isNotEmpty ? testPool : online;

    final ranked = <({PackagingServer server, int score})>[];
    for (final server in pool) {
      final status = await _workload.queryStatus(server);
      ranked.add((server: server, score: status.idleScore));
    }

    ranked.sort((a, b) => a.score.compareTo(b.score));
    final selected = ranked.first.server;
    // ignore: avoid_print
    print(
      '[JobParams] auto-assign server=${selected.displayName} '
      'tag=${selected.tag} score=${ranked.first.score} '
      'pool=${pool.map((e) => e.displayName).join(',')}',
    );
    return selected;
  }

  /// @Deprecated 使用 [pickMostIdleServer]
  PackagingServer? resolveServer({Environment? environment}) {
    final env = environment ?? global.currentEnvironment ?? Environment.test;
    final preferTag = env == Environment.prod ? 'release' : 'test';
    final active = packagingServers.activeServers
        .where((s) => s.active && s.url.isNotEmpty)
        .toList();
    if (active.isEmpty) return null;

    final online = active.where((s) => s.online).toList();
    final pool = online.isNotEmpty ? online : active;

    final testPool =
        pool.where((s) => s.tag.toLowerCase() == 'test').toList();
    if (testPool.isNotEmpty) return testPool.first;

    for (final s in pool) {
      if (s.tag.toLowerCase() == preferTag) return s;
    }
    return pool.first;
  }

  Future<List<JenkinsJobParameter>> fetchJobParameters({
    required String jobName,
    PackagingServer? server,
    Environment? environment,
    Map<String, String>? currentValues,
  }) async {
    if (packagingServers.activeServers.isEmpty) {
      await packagingServers.fetchActiveServers();
    }
    final target =
        server ?? await resolveTaskServer(environment: environment);
    if (target == null) {
      throw StateError('没有可用的打包机（需要 active=true）');
    }
    if (!target.online) {
      throw StateError('打包机离线: ${target.displayName}');
    }
    final topic = target.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('无法从打包机 URL 解析 ntfy topic: ${target.url}');
    }

    final jenkinsBase = _localJenkinsBase(target.url);
    final encodedJob = Uri.encodeComponent(jobName);
    final auth = _basicAuth(target.userName, target.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };

    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/job/$encodedJob/api/json',
      headers: headers,
      params: const {
        'tree':
            'property[parameterDefinitions[_class,name,description,'
                'defaultParameterValue[*],choices,choiceType,'
                'referencedParameters,randomName]]',
      },
      timeout: const Duration(seconds: 60),
    );

    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      throw StateError(
        '查询 Job 参数失败 job=$jobName status=${res.statusCode} error=${res.error}',
      );
    }

    final body = _asMap(res.body);
    var params = _parseParameters(body);

    // Active Choices：经 scriptText 调用 Groovy getChoices() 拿动态选项
    // 先拿一次 crumb，整轮复用，减少 ntfy 发布次数
    final crumbHeaders = await _fetchCrumbHeaders(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      required: false,
    );
    params = await _resolveActiveChoices(
      jobName: jobName,
      params: params,
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      crumbHeaders: crumbHeaders,
      currentValues: currentValues ?? const {},
    );

    return params;
  }

  /// 仅刷新某个 Active Choices 参数的选项（用于 Reactive 联动）。
  Future<List<String>> evaluateActiveChoiceChoices({
    required String jobName,
    required String paramName,
    required PackagingServer server,
    Map<String, String> referencedValues = const {},
  }) async {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('无法从打包机 URL 解析 ntfy topic: ${server.url}');
    }
    final jenkinsBase = _localJenkinsBase(server.url);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };
    final crumbHeaders = await _fetchCrumbHeaders(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      required: false,
    );
    return _runGetChoicesScript(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      crumbHeaders: crumbHeaders,
      jobName: jobName,
      paramName: paramName,
      referencedValues: referencedValues,
    );
  }

  Future<List<JenkinsJobParameter>> _resolveActiveChoices({
    required String jobName,
    required List<JenkinsJobParameter> params,
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required Map<String, String> crumbHeaders,
    required Map<String, String> currentValues,
  }) async {
    if (params.every((p) => !p.isActiveChoices)) return params;

    final values = Map<String, String>.from(currentValues);
    for (final p in params) {
      if (!values.containsKey(p.name)) {
        values[p.name] = '${p.initialValue ?? ''}';
      }
    }

    final result = <JenkinsJobParameter>[];
    for (final param in params) {
      if (!param.isActiveChoices) {
        result.add(param);
        continue;
      }

      final refs = <String, String>{};
      for (final ref in param.referencedParameters) {
        refs[ref] = values[ref] ?? '';
      }

      try {
        final choices = await _runGetChoicesScript(
          topic: topic,
          jenkinsBase: jenkinsBase,
          headers: headers,
          crumbHeaders: crumbHeaders,
          jobName: jobName,
          paramName: param.name,
          referencedValues: refs,
        );
        // ignore: avoid_print
        print(
          '[JobParams] ActiveChoices ${param.name} '
          'choices=${choices.length} refs=$refs',
        );
        final updated = param.copyWith(
          choices: choices.isNotEmpty ? choices : param.choices,
        );
        result.add(updated);
        if (choices.isNotEmpty) {
          final current = values[param.name] ?? '';
          if (current.isEmpty || !choices.contains(current)) {
            values[param.name] = choices.first;
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[JobParams] ActiveChoices ${param.name} evaluate failed: $e');
        result.add(param);
      }
    }
    return result;
  }

  /// 通过 Jenkins `/scriptText` 执行 Groovy，调用 Active Choices 的 getChoices()。
  Future<List<String>> _runGetChoicesScript({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required Map<String, String> crumbHeaders,
    required String jobName,
    required String paramName,
    Map<String, String> referencedValues = const {},
  }) async {
    final script = _buildGetChoicesGroovy(
      jobName: jobName,
      paramName: paramName,
      referencedValues: referencedValues,
    );

    var crumbs = crumbHeaders;
    if (crumbs.isEmpty) {
      crumbs = await _fetchCrumbHeaders(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
        required: false,
      );
    }

    final postHeaders = <String, String>{
      ...headers,
      ...crumbs,
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    };

    final res = await _client.proxyHttp(
      topic: topic,
      method: 'POST',
      url: '$jenkinsBase/scriptText',
      headers: postHeaders,
      body: 'script=${Uri.encodeQueryComponent(script)}',
      timeout: const Duration(seconds: 90),
    );

    if (res.statusCode == 403) {
      // crumb 可能过期：清缓存后重试一次
      _invalidateCrumb(topic, jenkinsBase);
      final fresh = await _fetchCrumbHeaders(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
        required: false,
      );
      if (fresh.isNotEmpty) {
        final retry = await _client.proxyHttp(
          topic: topic,
          method: 'POST',
          url: '$jenkinsBase/scriptText',
          headers: {
            ...headers,
            ...fresh,
            'Content-Type':
                'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: 'script=${Uri.encodeQueryComponent(script)}',
          timeout: const Duration(seconds: 90),
        );
        if (retry.ok &&
            retry.statusCode != null &&
            retry.statusCode! < 400) {
          return _parseScriptChoices(retry.body);
        }
      }
    }

    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      throw StateError(
        'scriptText 失败 param=$paramName status=${res.statusCode} '
        'error=${res.error} body=${_bodyPreview(res.body)}',
      );
    }

    return _parseScriptChoices(res.body);
  }

  String _buildGetChoicesGroovy({
    required String jobName,
    required String paramName,
    required Map<String, String> referencedValues,
  }) {
    final jobLit = jsonEncode(jobName);
    final paramLit = jsonEncode(paramName);
    final refsLit = _groovyMapLiteral(referencedValues);
    return '''
import hudson.model.ParametersDefinitionProperty
import groovy.json.JsonOutput

def jobName = $jobLit
def paramName = $paramLit
def refs = $refsLit as Map

def job = Jenkins.instance.getItemByFullName(jobName)
if (job == null) {
  println '[]'
  return
}
def prop = job.getProperty(ParametersDefinitionProperty)
if (prop == null) {
  println '[]'
  return
}
def defn = prop.getParameterDefinition(paramName)
if (defn == null) {
  println '[]'
  return
}

def result
try {
  if (defn.metaClass.respondsTo(defn, 'getChoices', Map)) {
    result = defn.getChoices(refs ?: [:])
  } else if (defn.metaClass.respondsTo(defn, 'getChoices')) {
    result = defn.getChoices()
  } else {
    result = []
  }
} catch (Throwable t) {
  println JsonOutput.toJson([error: t.toString()])
  return
}

def list = []
if (result instanceof Map) {
  result.each { k, v ->
    def key = k?.toString() ?: ''
    key = key.replaceAll(/(?i):selected\$/, '').replaceAll(/(?i):disabled\$/, '')
    if (key) list << key
  }
} else if (result instanceof Collection) {
  result.each { v ->
    def key = v?.toString() ?: ''
    key = key.replaceAll(/(?i):selected\$/, '').replaceAll(/(?i):disabled\$/, '')
    if (key) list << key
  }
} else if (result != null) {
  list << result.toString()
}
println JsonOutput.toJson(list)
''';
  }

  String _groovyMapLiteral(Map<String, String> map) {
    if (map.isEmpty) return '[:]';
    final entries = map.entries
        .map((e) => '${jsonEncode(e.key)}: ${jsonEncode(e.value)}')
        .join(', ');
    return '[$entries]';
  }

  String _crumbCacheKey(String topic, String jenkinsBase) =>
      '$topic|$jenkinsBase';

  void _invalidateCrumb(String topic, String jenkinsBase) {
    _crumbCache.remove(_crumbCacheKey(topic, jenkinsBase));
  }

  /// 获取 CSRF crumb（含会话 Cookie）。
  ///
  /// [required]=true 时失败会抛错（触发构建必须有 crumb）；
  /// false 时失败返回空 Map（ActiveChoices 可降级）。
  Future<Map<String, String>> _fetchCrumbHeaders({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    bool required = false,
  }) async {
    final key = _crumbCacheKey(topic, jenkinsBase);
    final cached = _crumbCache[key];
    if (cached != null && !cached.isExpired) {
      return Map<String, String>.from(cached.headers);
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _client.proxyHttp(
          topic: topic,
          method: 'GET',
          url: '$jenkinsBase/crumbIssuer/api/json',
          headers: headers,
          timeout: const Duration(seconds: 90),
        );
        if (!res.ok || res.statusCode != 200) {
          lastError = StateError(
            'crumb HTTP status=${res.statusCode} error=${res.error}',
          );
          // ignore: avoid_print
          print('[JobParams] crumb fetch attempt ${attempt + 1}: $lastError');
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        final body = _asMap(res.body);
        final field = body['crumbRequestField']?.toString() ?? '';
        final crumb = body['crumb']?.toString() ?? '';
        if (field.isEmpty || crumb.isEmpty) {
          lastError = StateError('crumb 响应缺少字段');
          break;
        }

        final out = <String, String>{field: crumb};
        final cookie = _extractCookie(res.headers);
        if (cookie != null && cookie.isNotEmpty) {
          out['Cookie'] = cookie;
        }
        _crumbCache[key] = _CachedCrumb(
          headers: out,
          fetchedAt: DateTime.now(),
        );
        // ignore: avoid_print
        print(
          '[JobParams] crumb ok field=$field '
          'cookie=${cookie != null} attempt=${attempt + 1}',
        );
        return Map<String, String>.from(out);
      } catch (e) {
        lastError = e;
        // ignore: avoid_print
        print('[JobParams] crumb fetch attempt ${attempt + 1} failed: $e');
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    if (required) {
      throw StateError(
        '无法获取 Jenkins CSRF crumb，请稍后重试。原因: $lastError',
      );
    }
    // ignore: avoid_print
    print('[JobParams] crumb fetch skipped after retries: $lastError');
    return const {};
  }

  String? _extractCookie(Map<String, String> headers) {
    // http 包可能把 set-cookie 合成一个字符串，也可能是多值拼接
    String? raw;
    headers.forEach((key, value) {
      if (key.toLowerCase() == 'set-cookie') {
        raw = value;
      }
    });
    if (raw == null || raw!.isEmpty) return null;

    final pairs = <String>[];
    // 粗略按逗号拆（expires= 里也可能有逗号，取每段第一个 ; 前）
    for (final part in raw!.split(',')) {
      final pair = part.split(';').first.trim();
      if (pair.contains('=') && !pair.toLowerCase().startsWith('expires=')) {
        pairs.add(pair);
      }
    }
    if (pairs.isEmpty) return null;
    return pairs.join('; ');
  }

  List<String> _parseScriptChoices(dynamic body) {
    if (body is List) {
      return body
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (body is Map && body.containsKey('error')) {
      throw StateError('Groovy getChoices 错误: ${body['error']}');
    }
    if (body is String) {
      final text = body.trim();
      if (text.isEmpty) return const [];
      try {
        final decoded = jsonDecode(text);
        return _parseScriptChoices(decoded);
      } catch (_) {
        // 非 JSON：按行拆
        return text
            .split(RegExp(r'[\r\n]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e != 'Result:' && e != 'null')
            .toList();
      }
    }
    return const [];
  }

  List<JenkinsJobParameter> _parseParameters(Map<String, dynamic> body) {
    final properties = body['property'];
    if (properties is! List) return const [];

    final params = <JenkinsJobParameter>[];
    for (final property in properties) {
      if (property is! Map) continue;
      final type = property['_class']?.toString() ?? '';
      if (!type.contains('ParametersDefinitionProperty')) continue;
      final definitions = property['parameterDefinitions'];
      if (definitions is! List) continue;
      for (final raw in definitions) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final name = (map['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        params.add(JenkinsJobParameter.fromJson(map));
      }
    }
    return params;
  }

  String _localJenkinsBase(String url) {
    final uri = Uri.tryParse(url.trim());
    final port = uri?.hasPort == true ? uri!.port : 8080;
    return 'http://127.0.0.1:$port';
  }

  String? _basicAuth(String userName, String password) {
    final user = userName.trim();
    if (user.isEmpty) return null;
    return 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
  }

  Map<String, dynamic> _asMap(dynamic body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    if (body is String && body.trim().isNotEmpty) {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  String _bodyPreview(dynamic body) {
    final text = '$body';
    if (text.length <= 200) return text;
    return '${text.substring(0, 200)}...';
  }

  /// 触发 Job 构建，返回队列项 ID（用于后续轮询）。
  Future<JenkinsTriggeredBuild> triggerBuild({
    required String jobName,
    required PackagingServer server,
    required Map<String, String> parameters,
  }) async {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('无法从打包机 URL 解析 ntfy topic: ${server.url}');
    }
    final jenkinsBase = _localJenkinsBase(server.url);
    final encodedJob = Uri.encodeComponent(jobName);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };

    // 触发构建必须带有效 crumb，否则 Jenkins 直接 403
    final crumbHeaders = await _fetchCrumbHeaders(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      required: true,
    );

    // Jenkins 推荐用 form body 提交参数；query 过长时易被截断导致「没带参数」
    final formBody = parameters.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    Future<NtfyProxyResponse> postBuild(Map<String, String> crumbs) {
      return _client.proxyHttp(
        topic: topic,
        method: 'POST',
        url: '$jenkinsBase/job/$encodedJob/buildWithParameters',
        headers: {
          ...headers,
          ...crumbs,
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: formBody,
        timeout: const Duration(seconds: 120),
      );
    }

    var res = await postBuild(crumbHeaders);

    // crumb 失效时清缓存换新 crumb 再试一次
    if (res.statusCode == 403) {
      // ignore: avoid_print
      print('[JobParams] trigger 403, refreshing crumb and retrying');
      _invalidateCrumb(topic, jenkinsBase);
      final fresh = await _fetchCrumbHeaders(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
        required: true,
      );
      res = await postBuild(fresh);
    }

    // Jenkins 成功触发一般为 201；部分环境也可能 200
    final code = res.statusCode ?? 0;
    if (!res.ok || (code != 201 && code != 200)) {
      throw StateError(
        '触发构建失败 job=$jobName status=$code error=${res.error} '
        'body=${_bodyPreview(res.body)}',
      );
    }

    final queueId = _parseQueueIdFromHeaders(res.headers);
    // ignore: avoid_print
    print('[JobParams] triggered job=$jobName queueId=$queueId');
    return JenkinsTriggeredBuild(queueId: queueId);
  }

  /// 查询队列项 / 构建状态。
  Future<JenkinsJobRunSnapshot> queryRunStatus({
    required String jobName,
    required PackagingServer server,
    int? queueId,
    int? buildNumber,
  }) async {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('无法从打包机 URL 解析 ntfy topic: ${server.url}');
    }
    final jenkinsBase = _localJenkinsBase(server.url);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };

    var resolvedBuild = buildNumber;
    var resolvedQueue = queueId;

    if (resolvedBuild == null && resolvedQueue != null) {
      final queueSnap = await _queryQueueItem(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
        queueId: resolvedQueue,
      );
      if (queueSnap.status == JenkinsJobRunStatus.aborted ||
          queueSnap.status == JenkinsJobRunStatus.waiting ||
          queueSnap.status == JenkinsJobRunStatus.error) {
        return queueSnap;
      }
      resolvedBuild = queueSnap.buildNumber;
      resolvedQueue = queueSnap.queueId;
      if (resolvedBuild == null) {
        return queueSnap;
      }
    }

    if (resolvedBuild == null) {
      // 无队列信息时看 lastBuild
      return _queryLastBuild(
        topic: topic,
        jenkinsBase: jenkinsBase,
        headers: headers,
        jobName: jobName,
      );
    }

    return _queryBuild(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      jobName: jobName,
      buildNumber: resolvedBuild,
      queueId: resolvedQueue,
    );
  }

  Future<JenkinsJobRunSnapshot> _queryQueueItem({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required int queueId,
  }) async {
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/queue/item/$queueId/api/json',
      headers: headers,
      params: const {
        'tree': 'id,cancelled,why,executable[number,url]',
      },
      timeout: const Duration(seconds: 90),
    );

    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      // 队列项过期消失时，常见 404
      if (res.statusCode == 404) {
        return JenkinsJobRunSnapshot(
          status: JenkinsJobRunStatus.waiting,
          queueId: queueId,
          message: '队列项已离开，等待构建号',
        );
      }
      return JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.error,
        queueId: queueId,
        message: '查询队列失败 status=${res.statusCode} error=${res.error}',
      );
    }

    final body = _asMap(res.body);
    if (body['cancelled'] == true) {
      return JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.aborted,
        queueId: queueId,
        message: '队列任务已取消',
      );
    }

    final executable = body['executable'];
    int? buildNumber;
    if (executable is Map) {
      final n = executable['number'];
      if (n is num) {
        buildNumber = n.toInt();
      } else {
        buildNumber = int.tryParse('$n');
      }
    }

    if (buildNumber != null) {
      return JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.building,
        queueId: queueId,
        buildNumber: buildNumber,
        message: '已进入构建 #$buildNumber',
      );
    }

    final why = body['why']?.toString();
    return JenkinsJobRunSnapshot(
      status: JenkinsJobRunStatus.waiting,
      queueId: queueId,
      message: (why != null && why.isNotEmpty) ? why : '等待中',
    );
  }

  Future<JenkinsJobRunSnapshot> _queryBuild({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required String jobName,
    required int buildNumber,
    int? queueId,
  }) async {
    final encodedJob = Uri.encodeComponent(jobName);
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/job/$encodedJob/$buildNumber/api/json',
      headers: headers,
      params: const {
        'tree': 'number,building,result,url',
      },
      timeout: const Duration(seconds: 90),
    );

    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      return JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.error,
        queueId: queueId,
        buildNumber: buildNumber,
        message: '查询构建失败 status=${res.statusCode} error=${res.error}',
      );
    }

    final body = _asMap(res.body);
    final building = body['building'] == true;
    final result = body['result']?.toString();

    if (building || result == null || result.isEmpty || result == 'null') {
      return JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.building,
        queueId: queueId,
        buildNumber: buildNumber,
        message: '打包中 #$buildNumber',
      );
    }

    switch (result.toUpperCase()) {
      case 'SUCCESS':
        return JenkinsJobRunSnapshot(
          status: JenkinsJobRunStatus.success,
          queueId: queueId,
          buildNumber: buildNumber,
          message: '打包完成 #$buildNumber',
        );
      case 'FAILURE':
      case 'UNSTABLE':
        return JenkinsJobRunSnapshot(
          status: JenkinsJobRunStatus.failure,
          queueId: queueId,
          buildNumber: buildNumber,
          message: '打包失败 #$buildNumber ($result)',
        );
      case 'ABORTED':
        return JenkinsJobRunSnapshot(
          status: JenkinsJobRunStatus.aborted,
          queueId: queueId,
          buildNumber: buildNumber,
          message: '打包取消 #$buildNumber',
        );
      default:
        return JenkinsJobRunSnapshot(
          status: JenkinsJobRunStatus.error,
          queueId: queueId,
          buildNumber: buildNumber,
          message: '未知结果 #$buildNumber ($result)',
        );
    }
  }

  Future<JenkinsJobRunSnapshot> _queryLastBuild({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required String jobName,
  }) async {
    final encodedJob = Uri.encodeComponent(jobName);
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/job/$encodedJob/lastBuild/api/json',
      headers: headers,
      params: const {
        'tree': 'number,building,result,url',
      },
      timeout: const Duration(seconds: 90),
    );

    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      return const JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.waiting,
        message: '等待构建出现',
      );
    }

    final body = _asMap(res.body);
    final n = body['number'];
    final buildNumber = n is num ? n.toInt() : int.tryParse('$n');
    if (buildNumber == null) {
      return const JenkinsJobRunSnapshot(
        status: JenkinsJobRunStatus.waiting,
        message: '等待构建出现',
      );
    }
    return _queryBuild(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      jobName: jobName,
      buildNumber: buildNumber,
    );
  }

  /// 在所有在线打包机上查找「等待中 / 进行中」且参数与 [parameters] 一致的任务。
  ///
  /// 比较时忽略 `uid` / `tag`（每次提交会变或由打包机写入）。
  Future<List<JenkinsDuplicateActiveJob>> findDuplicateActiveJobs({
    required String jobName,
    required Map<String, String> parameters,
    List<PackagingServer>? servers,
  }) async {
    if (packagingServers.activeServers.isEmpty) {
      await packagingServers.fetchActiveServers();
    }
    final targets = (servers ?? packagingServers.activeServers)
        .where((s) => s.active && s.online && s.url.isNotEmpty)
        .toList();
    if (targets.isEmpty) return const [];

    // 先订齐各打包机 topic，再查询；否则未订阅的 topic 收不到 Agent 回包
    final topics = targets
        .map((s) => s.ntfyTopic)
        .whereType<String>()
        .where((t) => t.isNotEmpty);
    await _client.ensureTopicsListening(topics);

    // 按机串行：每台 topic 内复用同一条 SSE，避免并行多路丢包
    final out = <JenkinsDuplicateActiveJob>[];
    for (final server in targets) {
      try {
        out.addAll(
          await _findDuplicatesOnServer(
            jobName: jobName,
            server: server,
            parameters: parameters,
          ),
        );
      } catch (e) {
        // ignore: avoid_print
        print(
          '[JobParams] duplicate check failed '
          'server=${server.displayName}: $e',
        );
      }
    }
    return out;
  }

  Future<List<JenkinsDuplicateActiveJob>> _findDuplicatesOnServer({
    required String jobName,
    required PackagingServer server,
    required Map<String, String> parameters,
  }) async {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) return const [];
    final jenkinsBase = _localJenkinsBase(server.url);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };

    final out = <JenkinsDuplicateActiveJob>[];

    // 1) 队列中（等待中）
    final queued = await _fetchQueuedJobsWithParams(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      jobName: jobName,
    );
    for (final item in queued) {
      if (!jobParametersMatch(parameters, item.parameters)) continue;
      out.add(
        JenkinsDuplicateActiveJob(
          server: server,
          jobName: jobName,
          status: JenkinsJobRunStatus.waiting,
          queueId: item.queueId,
          parameters: item.parameters,
        ),
      );
    }

    // 2) 正在构建中
    final building = await _fetchBuildingJobsWithParams(
      topic: topic,
      jenkinsBase: jenkinsBase,
      headers: headers,
      jobName: jobName,
    );
    for (final item in building) {
      if (!jobParametersMatch(parameters, item.parameters)) continue;
      out.add(
        JenkinsDuplicateActiveJob(
          server: server,
          jobName: jobName,
          status: JenkinsJobRunStatus.building,
          buildNumber: item.buildNumber,
          parameters: item.parameters,
        ),
      );
    }

    return out;
  }

  Future<List<({int queueId, Map<String, String> parameters})>>
      _fetchQueuedJobsWithParams({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required String jobName,
  }) async {
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/queue/api/json',
      headers: headers,
      params: const {
        'tree':
            'items[id,task[name,url],actions[parameters[name,value]]]',
      },
      timeout: const Duration(seconds: 90),
    );
    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      return const [];
    }

    final body = _asMap(res.body);
    final items = body['items'];
    if (items is! List || items.isEmpty) return const [];

    final expect = jobName.trim().toLowerCase();
    final out = <({int queueId, Map<String, String> parameters})>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (!_queueItemMatchesJob(map, expect)) continue;

      final idRaw = map['id'];
      final queueId =
          idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw');
      if (queueId == null) continue;

      out.add((
        queueId: queueId,
        parameters: _extractParametersFromBuild(map),
      ));
    }
    return out;
  }

  bool _queueItemMatchesJob(Map<String, dynamic> item, String expectLower) {
    final task = item['task'];
    if (task is! Map) return false;
    final name = '${task['name'] ?? ''}'.trim();
    if (name.toLowerCase() == expectLower) return true;
    final url = '${task['url'] ?? ''}'.trim();
    if (url.isEmpty) return false;
    // 兼容 /job/xxx/ 或末尾带斜杠的路径
    final encoded = Uri.encodeComponent(expectLower);
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('/job/$expectLower/') ||
        lowerUrl.contains('/job/$encoded/') ||
        lowerUrl.endsWith('/job/$expectLower') ||
        RegExp(r'/job/([^/]+)/?$').firstMatch(lowerUrl)?.group(1) ==
            expectLower;
  }

  Future<List<({int buildNumber, Map<String, String> parameters})>>
      _fetchBuildingJobsWithParams({
    required String topic,
    required String jenkinsBase,
    required Map<String, String> headers,
    required String jobName,
    int lookback = 20,
  }) async {
    final encodedJob = Uri.encodeComponent(jobName);
    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/job/$encodedJob/api/json',
      headers: headers,
      params: {
        'tree':
            'builds[number,building,actions[parameters[name,value]]]'
                '{0,$lookback}',
      },
      timeout: const Duration(seconds: 90),
    );
    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      return const [];
    }

    final body = _asMap(res.body);
    final builds = body['builds'];
    if (builds is! List || builds.isEmpty) return const [];

    final out = <({int buildNumber, Map<String, String> parameters})>[];
    for (final raw in builds) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['building'] != true) continue;
      final n = map['number'];
      final buildNumber = n is num ? n.toInt() : int.tryParse('$n');
      if (buildNumber == null) continue;
      out.add((
        buildNumber: buildNumber,
        parameters: _extractParametersFromBuild(map),
      ));
    }
    return out;
  }

  /// 比较两组 Job 参数是否表示「同一打包」（忽略 uid / tag）。
  ///
  /// 以 [a]（当前准备提交的参数）为准：其有效字段须在 [b] 中取值一致。
  static bool jobParametersMatch(
    Map<String, String> a,
    Map<String, String> b, {
    Set<String> ignoreKeys = const {'uid', 'tag'},
  }) {
    Map<String, String> normalize(Map<String, String> source) {
      final out = <String, String>{};
      for (final e in source.entries) {
        final key = e.key.trim();
        if (key.isEmpty) continue;
        final lower = key.toLowerCase();
        if (ignoreKeys.any((k) => k.toLowerCase() == lower)) continue;
        out[lower] = e.value.trim();
      }
      return out;
    }

    final prepared = normalize(a);
    if (prepared.isEmpty) return false;
    final remote = normalize(b);
    for (final e in prepared.entries) {
      if ((remote[e.key] ?? '') != e.value) return false;
    }
    return true;
  }

  /// 拉取 Jenkins Job 的构建历史（含参数，供任务列表 / 重试）。
  Future<List<JenkinsHistoricalTask>> fetchJobBuildHistory({
    required String jobName,
    required PackagingServer server,
    int limit = 10,
  }) async {
    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) {
      throw StateError('无法从打包机 URL 解析 ntfy topic: ${server.url}');
    }
    final jenkinsBase = _localJenkinsBase(server.url);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };
    final encodedJob = Uri.encodeComponent(jobName);
    final lookback = limit < 1 ? 1 : limit;

    final res = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/job/$encodedJob/api/json',
      headers: headers,
      params: {
        'tree':
            'builds[number,building,result,timestamp,duration,'
                'actions[parameters[name,value]]]{0,$lookback}',
      },
      timeout: const Duration(seconds: 90),
    );
    if (!res.ok || res.statusCode == null || res.statusCode! >= 400) {
      throw StateError(
        '查询构建历史失败 job=$jobName status=${res.statusCode} error=${res.error}',
      );
    }

    final body = _asMap(res.body);
    final builds = body['builds'];
    if (builds is! List || builds.isEmpty) return const [];

    final out = <JenkinsHistoricalTask>[];
    for (final item in builds) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final n = map['number'];
      final buildNumber = n is num ? n.toInt() : int.tryParse('$n');
      if (buildNumber == null) continue;

      final params = _extractParametersFromBuild(map);
      final status = _statusFromBuildFields(
        building: map['building'] == true,
        result: map['result']?.toString(),
      );
      final ts = map['timestamp'];
      final ms = ts is num ? ts.toInt() : int.tryParse('$ts');
      final when = ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.fromMillisecondsSinceEpoch(0);

      out.add(
        JenkinsHistoricalTask(
          id: '${server.id}_${jobName}_$buildNumber',
          jobName: jobName,
          serverName: server.displayName,
          serverTag: server.tag,
          parameters: params,
          status: status,
          message: _messageForBuildStatus(status, buildNumber, map['result']?.toString()),
          buildNumber: buildNumber,
          createdAt: when,
          updatedAt: when,
        ),
      );
    }
    return out;
  }

  Map<String, String> _extractParametersFromBuild(Map<String, dynamic> buildInfo) {
    final out = <String, String>{};
    final actions = buildInfo['actions'];
    if (actions is! List) return out;
    for (final action in actions) {
      if (action is! Map) continue;
      final parameters = action['parameters'];
      if (parameters is! List) continue;
      for (final param in parameters) {
        if (param is! Map) continue;
        final name = param['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        out[name] = param['value']?.toString() ?? '';
      }
    }
    return out;
  }

  JenkinsJobRunStatus _statusFromBuildFields({
    required bool building,
    String? result,
  }) {
    if (building || result == null || result.isEmpty || result == 'null') {
      return JenkinsJobRunStatus.building;
    }
    switch (result.toUpperCase()) {
      case 'SUCCESS':
        return JenkinsJobRunStatus.success;
      case 'FAILURE':
      case 'UNSTABLE':
        return JenkinsJobRunStatus.failure;
      case 'ABORTED':
        return JenkinsJobRunStatus.aborted;
      default:
        return JenkinsJobRunStatus.error;
    }
  }

  String _messageForBuildStatus(
    JenkinsJobRunStatus status,
    int buildNumber,
    String? result,
  ) {
    switch (status) {
      case JenkinsJobRunStatus.building:
        return '打包中 #$buildNumber';
      case JenkinsJobRunStatus.success:
        return '打包完成 #$buildNumber';
      case JenkinsJobRunStatus.failure:
        return '打包失败 #$buildNumber${result != null ? ' ($result)' : ''}';
      case JenkinsJobRunStatus.aborted:
        return '打包取消 #$buildNumber';
      default:
        return '构建 #$buildNumber${result != null ? ' ($result)' : ''}';
    }
  }

  /// 按构建参数 UID 查找构建号（触发回包丢失时的兜底）。
  Future<int?> findBuildNumberByUid({
    required String jobName,
    required PackagingServer server,
    required String uid,
    int lookback = 15,
  }) async {
    final expect = uid.trim();
    if (expect.isEmpty) return null;

    final topic = server.ntfyTopic;
    if (topic == null || topic.isEmpty) return null;
    final jenkinsBase = _localJenkinsBase(server.url);
    final auth = _basicAuth(server.userName, server.password);
    final headers = <String, String>{
      if (auth != null) 'Authorization': auth,
    };
    final encodedJob = Uri.encodeComponent(jobName);

    final listRes = await _client.proxyHttp(
      topic: topic,
      method: 'GET',
      url: '$jenkinsBase/job/$encodedJob/api/json',
      headers: headers,
      params: {
        'tree': 'builds[number]{0,$lookback}',
      },
      timeout: const Duration(seconds: 90),
    );
    if (!listRes.ok || listRes.statusCode != 200) return null;

    final listBody = _asMap(listRes.body);
    final builds = listBody['builds'];
    if (builds is! List || builds.isEmpty) return null;

    for (final item in builds) {
      if (item is! Map) continue;
      final n = item['number'];
      final buildNumber = n is num ? n.toInt() : int.tryParse('$n');
      if (buildNumber == null) continue;

      final detail = await _client.proxyHttp(
        topic: topic,
        method: 'GET',
        url: '$jenkinsBase/job/$encodedJob/$buildNumber/api/json',
        headers: headers,
        params: const {
          'tree': 'number,actions[parameters[name,value]]',
        },
        timeout: const Duration(seconds: 90),
      );
      if (!detail.ok || detail.statusCode != 200) continue;

      final foundUid = _extractUidFromBuild(_asMap(detail.body));
      if (foundUid != null && foundUid.trim() == expect) {
        // ignore: avoid_print
        print('[JobParams] UID match build=#$buildNumber uid=$expect');
        return buildNumber;
      }
    }
    return null;
  }

  String? _extractUidFromBuild(Map<String, dynamic> buildInfo) {
    final actions = buildInfo['actions'];
    if (actions is! List) return null;
    for (final action in actions) {
      if (action is! Map) continue;
      final parameters = action['parameters'];
      if (parameters is! List) continue;
      for (final param in parameters) {
        if (param is! Map) continue;
        final name = param['name']?.toString() ?? '';
        if (name.toLowerCase() == 'uid') {
          return param['value']?.toString();
        }
      }
    }
    return null;
  }

  int? _parseQueueIdFromHeaders(Map<String, String> headers) {
    String? location;
    headers.forEach((key, value) {
      if (key.toLowerCase() == 'location') {
        location = value;
      }
    });
    if (location == null || location!.isEmpty) return null;
    final match = RegExp(r'/queue/item/(\d+)').firstMatch(location!);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  void close() {
    _crumbCache.clear();
    _workload.close();
    _client.close();
  }
}

/// 某台打包机上发现的「等待中 / 进行中」同参任务。
class JenkinsDuplicateActiveJob {
  final PackagingServer server;
  final String jobName;
  final JenkinsJobRunStatus status;
  final int? queueId;
  final int? buildNumber;
  final Map<String, String> parameters;

  const JenkinsDuplicateActiveJob({
    required this.server,
    required this.jobName,
    required this.status,
    this.queueId,
    this.buildNumber,
    this.parameters = const {},
  });

  String get detailLabel {
    if (buildNumber != null) return '构建 #$buildNumber';
    if (queueId != null) return '队列 #$queueId';
    return status.label;
  }

  /// 给用户看的提示文案。
  String get userMessage =>
      '${server.displayName} 存在相同打包（${status.label}，$detailLabel），请稍后再试';
}

class _CachedCrumb {
  _CachedCrumb({required this.headers, required this.fetchedAt});

  final Map<String, String> headers;
  final DateTime fetchedAt;

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) >
      JenkinsJobParamsService._crumbTtl;
}
