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

    webview
      ..addScriptToExecuteOnDocumentCreated(autoLoginScript)
      ..setOnUrlRequestCallback((requested) {
        // 允许所有导航（含登录 POST 后的跳转）
        return true;
      });

    // 文档起始注入可能早于表单渲染；导航结束后再补一次。
    void tryFillAgain() {
      webview.evaluateJavaScript(autoLoginScript);
    }

    webview.isNavigating.addListener(() {
      if (!webview.isNavigating.value) {
        Future<void>.delayed(const Duration(milliseconds: 350), tryFillAgain);
      }
    });

    webview.launch(url);
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
  static String _buildAutoLoginScript({
    required String username,
    required String password,
  }) {
    final userLit = jsonEncode(username);
    final passLit = jsonEncode(password);
    return '''
(function () {
  if (window.__jenkinsAutoLoginDone) return;
  var user = $userLit;
  var pass = $passLit;
  if (!user) return;

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
  function tryFill() {
    if (window.__jenkinsAutoLoginDone) return true;
    var u = findUser();
    var p = findPass();
    if (!u || !p) return false;
    setValue(u, user);
    setValue(p, pass);
    window.__jenkinsAutoLoginDone = true;
    var form = findForm(u);
    if (form) {
      var submit = form.querySelector('button[type="submit"], input[type="submit"], input[name="Submit"]');
      if (submit) {
        submit.click();
      } else {
        form.submit();
      }
    }
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
