import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:publish_unity_hot_assets/app/common/appwrite/packaging_server.dart';

/// 在应用内 WebView 窗口打开 Jenkins，并自动填充登录表单。
class JenkinsBrowserLauncher {
  JenkinsBrowserLauncher._();

  /// 打开打包机 Jenkins；若页面有登录表单则自动填入账号密码并提交。
  static Future<void> open(PackagingServer server) async {
    final url = _normalizeUrl(server.url);
    if (url.isEmpty) {
      throw StateError('打包机 URL 为空，无法打开 Jenkins');
    }

    final available = await WebviewWindow.isWebviewAvailable();
    if (!available) {
      throw StateError('当前系统未安装 WebView2 运行时，无法打开内嵌浏览器');
    }

    final userDataDir = await _windowsUserDataDir();
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: '${server.displayName} · Jenkins',
        windowWidth: 1280,
        windowHeight: 860,
        titleBarTopPadding: Platform.isMacOS ? 24 : 0,
        userDataFolderWindows: userDataDir,
      ),
    );

    final autoLoginScript = _buildAutoLoginScript(
      username: server.userName,
      password: server.password,
    );

    // 不要 setOnUrlRequestCallback：Windows 端插件会 cancel 导航再 Navigate(GET)，
    // 会把 Jenkins 登录 POST 变成无 body 的 GET，从而出现 Not Found 页。
    webview.addScriptToExecuteOnDocumentCreated(autoLoginScript);

    // 文档起始注入可能早于表单渲染；导航结束后再补一次。
    void tryFillAgain() {
      webview.evaluateJavaScript(autoLoginScript);
    }

    webview.isNavigating.addListener(() {
      if (!webview.isNavigating.value) {
        Future<void>.delayed(const Duration(milliseconds: 350), tryFillAgain);
      }
    });

    // Windows：关闭首次导航的 UrlRequest 拦截，减少无意义 cancel/重入。
    webview.launch(url, triggerOnUrlRequestEvent: !Platform.isWindows);
  }

  static String _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return trimmed;
    if (parsed.hasScheme) return trimmed;
    return 'http://$trimmed';
  }

  static Future<String> _windowsUserDataDir() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'jenkins_webview2');
  }

  /// 在 Jenkins 登录页填充 j_username / j_password 并提交。
  ///
  /// Windows WebView2 插件会把文档导航 POST 改成 GET，因此登录必须用
  /// fetch POST（非导航请求），成功后再 `location` 跳首页。
  static String _buildAutoLoginScript({
    required String username,
    required String password,
  }) {
    final userLit = jsonEncode(username);
    final passLit = jsonEncode(password);
    return '''
(function () {
  if (window.__jenkinsAutoLoginInstalled) return;
  window.__jenkinsAutoLoginInstalled = true;

  var user = $userLit;
  var pass = $passLit;

  function findUser() {
    return document.getElementById('j_username')
      || document.querySelector('input[name="j_username"]');
  }
  function findPass() {
    return document.querySelector('input[name="j_password"]')
      || document.getElementById('j_password');
  }
  function findForm(userEl) {
    return (userEl && userEl.form)
      || document.querySelector('form[name="login"]')
      || document.querySelector('form[action*="j_acegi_security_check"]')
      || document.querySelector('form');
  }
  function setValue(el, value) {
    if (!el) return;
    el.focus();
    el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function resolveAction(form) {
    if (!form) return location.origin + '/j_acegi_security_check';
    try {
      return new URL(form.getAttribute('action') || form.action || 'j_acegi_security_check', location.href).href;
    } catch (e) {
      return location.origin + '/j_acegi_security_check';
    }
  }
  function postLogin(form, username, password) {
    if (window.__jenkinsAutoLoginDone) return;
    window.__jenkinsAutoLoginDone = true;
    var action = resolveAction(form);
    var body = new URLSearchParams();
    body.set('j_username', username);
    body.set('j_password', password);
    var fromEl = form && form.querySelector('input[name="from"]');
    body.set('from', (fromEl && fromEl.value) ? fromEl.value : '/');
    body.set('Submit', 'Sign in');
    fetch(action, {
      method: 'POST',
      credentials: 'same-origin',
      redirect: 'follow',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    }).then(function () {
      window.location.href = location.origin + '/';
    }).catch(function () {
      window.__jenkinsAutoLoginDone = false;
    });
  }

  // 拦截登录表单的原生提交（含用户手动点登录），避免 Windows 把 POST 改成 GET。
  document.addEventListener('submit', function (e) {
    var form = e.target;
    if (!form || !form.querySelector) return;
    var u = form.querySelector('input[name="j_username"], #j_username');
    var p = form.querySelector('input[name="j_password"], #j_password');
    if (!u || !p) return;
    e.preventDefault();
    e.stopPropagation();
    postLogin(form, u.value, p.value);
  }, true);

  function tryFill() {
    if (window.__jenkinsAutoLoginDone) return true;
    if (!user) return false;
    var u = findUser();
    var p = findPass();
    if (!u || !p) return false;
    setValue(u, user);
    setValue(p, pass);
    postLogin(findForm(u), user, pass);
    return true;
  }

  if (tryFill()) return;
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { tryFill(); });
  }
  var attempts = 0;
  var timer = setInterval(function () {
    attempts += 1;
    if (tryFill() || attempts >= 40) clearInterval(timer);
  }, 250);
})();
''';
  }
}
