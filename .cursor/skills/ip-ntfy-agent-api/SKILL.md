---
name: ip-ntfy-agent-api
description: Implements Flutter/desktop features against the ip_ntfy_agent ntfy protocol and Appwrite/Jenkins conventions. Use when adding or changing packaging-server, Jenkins proxy, hot-update zip upload/delete, Appwrite host/resource, or ntfy client code in this repo.
---

# ip_ntfy_agent 调用约定

做任何功能请参考/Users/king/Documents/ip_ntfy_agent提供的调用方法

## Source of truth

| 用途 | 路径 |
| --- | --- |
| 仓库根 | `/Users/king/Documents/ip_ntfy_agent` |
| 协议说明 | `/Users/king/Documents/ip_ntfy_agent/README.md` |
| ntfy 请求/响应处理 | `lib/agent.dart` |
| ntfy 收发 | `lib/ntfy_service.dart` |
| Appwrite | `lib/appwrite_service.dart` |
| Jenkins zip / 在线检测 | `lib/jenkins_service.dart` |
| topic / IP | `lib/ip_service.dart` |
| 环境变量 | `.env.example` |

实现或改动相关功能前，先读上述文件，再写本仓库代码。不要自创另一套消息格式、字段名或 URL 规则。

## Topic

从打包机文档 `url` 取 host（IP），topic 为：

```dart
'topic_${ip.replaceAll('.', '_')}'  // 例: 10.10.48.63 → topic_10_10_48_63
```

见 `ipToTopic` in `lib/ip_service.dart`。

## 客户端 → Agent（ntfy message body）

### 1. 代理 HTTP（访问 Jenkins 等）

```json
{
  "requestId": "optional-id",
  "method": "GET",
  "url": "http://127.0.0.1:8080/api/json",
  "headers": { "Authorization": "Basic xxx" },
  "params": { "tree": "jobs[name]" },
  "body": null
}
```

- `params` 也可写成 `query`；`body` 也可写成 `data`
- Agent 在打包机本机发起请求，再把结果推回同一 topic
- **workspace 目录**（URL 以 `/job/.../ws/.../` 结尾）：Agent 自动改走 `*plain*`，body 为 `{ files, folders, folderName }`，不要自己解析 HTML
- **文件 / 过大响应**：`bodyOmitted: true`，只有 `fileName` / `folderName` 等元数据；实际下载走 `uploadApk` / `uploadZip`

### 2. 上传热更 zip

```json
{
  "action": "uploadZip",
  "requestId": "build-123",
  "buildId": "123",
  "platform": "iOS",
  "tag": "test"
}
```

- 必填：`buildId`（或 `buildNumber`）+ `platform`（`iOS` / `Android` / `HarmonyOS`）
- `tag` 可选；缺省用 Agent `.env` 的 `APPWRITE_TAG_VALUE`
- 上传中约每 5 秒有 `type=progress`；结束为 `type=response`

### 3. 删除热更 zip

```json
{
  "action": "deleteZip",
  "requestId": "del-123",
  "buildId": "123",
  "tag": "test"
}
```

- 必填：`buildId`（或 `buildNumber`）
- 记录不存在时仍 `ok: true`，`body.deleted == false`

### 4. 上传 APK

```json
{
  "action": "uploadApk",
  "requestId": "apk-123",
  "path": "http://127.0.0.1:8080/job/build_unity_first_package/ws/Builds/app.apk",
  "buildId": "123",
  "tag": "test"
}
```

- 必填：`path`（本地绝对路径或 HTTP(S) URL）+ `buildId`
- 资源表 `buildId` 存为 `apk:{buildId}`；上传中有 `type=progress`；成功回传 `downloadUrl`
- 客户端流程：`uploadApk` → 本机下载 `downloadUrl` → `deleteApk` 清理

### 5. 删除 APK

```json
{
  "action": "deleteApk",
  "requestId": "del-apk-123",
  "buildId": "123",
  "tag": "test"
}
```

## Agent → 客户端（须忽略回环）

订阅时忽略：

- ntfy tags 含 `response` 或 `agent-response`
- payload `type` 为 `response` 或 `progress`

成功响应形状：

```json
{
  "type": "response",
  "requestId": "...",
  "ok": true,
  "statusCode": 200,
  "body": {}
}
```

`uploadZip` / `deleteZip` 另带 `action`；失败时 `ok: false` + `error`。

## Appwrite / Jenkins 约定（与 Agent 对齐）

打包机文档字段：`url` / `userName` / `password` / `active` / `tag` / `online`（Jenkins 凭据来自文档，不在客户端 `.env` 硬编码）。

热更 zip 在 Jenkins workspace 的路径（Agent 侧下载，客户端只发 `uploadZip`）：

```
{jenkinsUrl}/job/build_unity_hot_asset/ws/HotUpdate/{buildId}/{PLATFORM}/UploadAssets/*zip*/UploadAssets.zip
```

`PLATFORM`：`iOS`/`Android` → `IOS`/`ANDROID`；`HarmonyOS`/`ohos` → `Harmony`。

Agent 下载热更 zip 走本机 `http://127.0.0.1:{port}`（端口取自文档 `url`，缺省 `8080`），不直接用文档里的 IP；客户端代理 Jenkins 同样用 `_localJenkinsBase`。文档 `url` 若省略端口且误走文档 host，会打到 80 端口出现 Apache 404。

资源表字段：`tag` / `fileId` / `buildId`；同 `tag`+`buildId` 覆盖旧文件。

## 本仓库实现要点

1. 经 ntfy 调 Agent，不要假定可直连打包机内网 Jenkins（除非明确本地调试）。
2. `requestId` 用于匹配异步响应；UI 应处理 `progress`。
3. 鉴权头、字段名、action 名与 README / `agent.dart` 保持一致。
4. 不确定时打开 `/Users/king/Documents/ip_ntfy_agent` 对照，再改本仓库。
