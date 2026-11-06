# AWBotNest 2 开放 API

AWBotNest 提供 `/api/v1` REST API，供自动化脚本、AI 助手和第三方系统管理插件、读写插件数据以及发送 Telegram 消息。

本文只描述稳定的开放 API，不包含 Web 控制台使用的内部 `/api/*` 接口。

## 认证

先在「系统设置 → 开放接口」生成并保存 API Key。每个请求携带以下任一请求头：

```http
X-API-Key: your_api_key
```

```http
Api-Key: your_api_key
```

基础地址为 `http://127.0.0.1:18001/api/v1`。请求和响应均使用 JSON、UTF-8。API Key 未配置时返回 `503`，缺失或错误时返回 `401`。

## 插件管理

### 列出插件

```http
GET /api/v1/plugins
```

```json
{
  "plugins": [{
    "id": "hello", "name": "启动检查", "version": "1.0.0",
    "scope": "standalone", "instance_mode": "shared",
    "plugin_api_version": 2,
    "enabled": true, "loaded": true, "error": ""
  }]
}
```

响应还可能包含 `requirements`、`resources`、`cookie_domains`、`requires_plugins`、`requires_capabilities`、`provides_capabilities`、系统版本范围及展示字段。调用方应忽略不认识的新增字段。

### 推送插件文件

上传一个 Python 插件文件到系统。文件会先进行元数据校验，上传成功后保持停用状态，不会自动执行。请求使用 `multipart/form-data`，字段名为 `file`，文件大小不能超过 2 MB。

```bash
curl -X POST \
  -H "X-API-Key: YOUR_API_KEY" \
  -F "file=@my_plugin.py" \
  http://127.0.0.1:18001/api/v1/plugins/upload
```

上传成功后，可使用 `POST /api/v1/plugins/{plugin_id}/enable` 启用插件。

### 插件详情与源码

```http
GET /api/v1/plugins/{plugin_id}
GET /api/v1/plugins/{plugin_id}/source
```

源码响应包含 `plugin_id`、相对 `path`、`source` 和 `is_package`。

远程修改源码已禁用：

```http
PUT /api/v1/plugins/{plugin_id}/source
```

该接口固定返回 `403`。修改源码等同远程执行代码，开放 API 不提供写入。可信本地文件管理、插件安装，以及管理员助手中受完整差异和逐次确认约束的专用源码工具，均不通过此接口开放权限；详见 [系统助手](ASSISTANT.md)。

### 启用、停用、重载

```http
POST /api/v1/plugins/{plugin_id}/enable
POST /api/v1/plugins/{plugin_id}/disable
POST /api/v1/plugins/{plugin_id}/reload
```

成功响应：

```json
{"ok": true, "message": "插件已启用"}
```

## 插件配置

```http
GET /api/v1/plugins/{plugin_id}/config
PUT /api/v1/plugins/{plugin_id}/config
```

保存请求：

```json
{"config": {"keyword": "hi"}}
```

系统按插件 `config_schema` 校验。字符串字段声明 `"format": "cron"` 时，系统同时校验其为 5 位或 6 位 Cron 表达式；Schema 页面和 Vue 页面的 `host.saveConfig()` 使用同一规则。已加载插件保存后会自动重载；重载失败返回 `409`，不得把该响应当作配置已经正常生效。

已声明的敏感字段及列表、对象中的敏感子字段返回 `********`。保存掩码时保留该路径的已保存值；
移动或删除含敏感字段的列表行前，需要先在管理员配置页读取真实值，避免下标变化误用其他行的值。

## 插件 KV 数据

```http
GET    /api/v1/plugins/{plugin_id}/kv
GET    /api/v1/plugins/{plugin_id}/kv/{key}
PUT    /api/v1/plugins/{plugin_id}/kv/{key}
DELETE /api/v1/plugins/{plugin_id}/kv/{key}
```

设置值的请求体：

```json
{"value": 42}
```

单值最大 10 MB，单插件 KV 数据库最大 256 MB。

这些 HTTP 接口内部使用 V2 async Storage，但对 HTTP 调用方仍是普通请求/响应。

`instance_mode="shared"` 插件继续使用以上原路径，不得传 `instance`。`instance_mode="account"` 插件必须通过 query 参数明确指定账号实例：

```http
GET    /api/v1/plugins/{plugin_id}/kv?instance=user_account
GET    /api/v1/plugins/{plugin_id}/kv/{key}?instance=user_account
PUT    /api/v1/plugins/{plugin_id}/kv/{key}?instance=user_account
DELETE /api/v1/plugins/{plugin_id}/kv/{key}?instance=user_account
```

`instance` 是系统中已有且允许该插件使用的用户 Session 名。缺少参数返回 `400`，账号或插件实例不存在返回 `404`。系统不会把多个账号实例的 Storage 隐式合并。

开放 API 当前不直接管理插件的内存 Session Runtime 或 Telegram Delivery 队列；它们随插件实例生命周期创建和清理。

## 发送 Telegram 消息

```http
POST /api/v1/messages/send
Content-Type: application/json
```

```json
{
  "chat_id": -1001234567890,
  "text": "Hello from AWBotNest",
  "sender": "bot",
  "session": "default",
  "parse_mode": "HTML"
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| `chat_id` | 是 | Telegram 会话 ID 或可解析的用户名 |
| `text` | 是 | 消息正文 |
| `sender` | 否 | `bot` 或 `user`，默认 `bot` |
| `session` | 否 | Bot ID 或用户 Session 名；省略时使用默认 Bot/首个在线用户 |
| `parse_mode` | 否 | 例如 `HTML` 或 `Markdown` |

成功响应包含 `ok`、`message_id`、`chat_id` 和 `date`。

## 查询会话

```http
GET /api/v1/chats/{chat_id}?session=user_account
```

此接口使用已连接的用户账号查询。返回 `id`、`title`、`username` 和 `type`。省略 `session` 时使用第一个在线用户账号；没有可用账号时返回 `503`。

## 账号列表

```http
GET /api/v1/accounts
```

```json
{
  "accounts": [
    {"id": "default", "kind": "bot", "connected": true},
    {"id": "user_account", "kind": "user", "connected": true}
  ]
}
```

开放 API 不提供手机号登录、验证码提交、Session 删除或密钥读取接口；这些高风险操作仅在管理控制台完成。

## 日志

```http
GET /api/v1/logs?limit=100
GET /api/v1/logs/plugins/{plugin_id}?limit=100
```

`limit` 范围为 1–1000。第三方程序应把日志当作敏感数据处理。

## 系统状态

```http
GET /api/v1/status
```

```json
{
  "version": "2.0.0.6",
  "bot_connected": true,
  "user_accounts_count": 1,
  "total_plugins": 5,
  "enabled_plugins": 3,
  "enabled_plugin_ids": ["a", "b", "c"]
}
```

`user_accounts_count` 只统计当前已连接的用户账号，不是系统保存的 Session 文件总数。

## Webhook

系统通知入站 Webhook 使用独立的 Webhook Secret，不使用开放 API Key：

```http
POST /api/v1/webhook?apikey=<WEBHOOK_SECRET>
Content-Type: application/json

{"title": "构建完成", "text": "发布成功", "category": "CI"}
```

插件公开 Webhook 地址为 `/api/plugin/{plugin_id}/{path}`，插件应自行验证签名或共享密钥。

### 企业微信自建应用回调

企业微信使用现有 `/api/wecom/callback/{channel_id}`，不是开放 API Key 接口：
GET 用于企业微信验证地址，POST 接收签名校验和 AES 解密后的消息。
管理员在通知渠道配置回调 Token、EncodingAESKey 和允许操作的成员，并把插件关联到该渠道。
不要用开放 API Key 或通知入站 Webhook Secret 代替企业微信回调凭据。

插件通过 `ctx.on_wecom_message()` 订阅文字、图片、文件或按钮事件，附件按需下载，
无需单独回调地址。原有文字指令保持优先；未注册的插件不会收到消息。
完整 SDK 和迁移示例见 [企业微信统一消息回调](PLUGIN_GUIDE.md#企业微信统一消息回调)。

## 错误格式

```json
{"detail": "错误说明"}
```

- `400`：参数或配置不合法。
- `401`：API Key 缺失或无效。
- `403`：操作因安全原因禁用。
- `404`：插件、键或会话不存在。
- `409`：插件加载或状态冲突。
- `502`：Telegram 或外部服务调用失败。
- `503`：API Key 未配置、账号离线或服务不可用。

账号实例插件访问 KV 时，缺少 `instance` 属于 `400`；指定未配置、未授权或不存在的账号实例属于 `404`。

## Python 示例

```python
import os
import requests

base = "http://127.0.0.1:18001/api/v1"
headers = {"X-API-Key": os.environ["AWBOTNEST_API_KEY"]}

response = requests.get(f"{base}/plugins", headers=headers, timeout=10)
response.raise_for_status()
print(response.json())
```

## cURL 示例

```bash
curl -H "X-API-Key: $AWBOTNEST_API_KEY" \
  http://127.0.0.1:18001/api/v1/status

curl -X POST \
  -H "X-API-Key: $AWBOTNEST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"chat_id":-1001234567890,"text":"Hello","sender":"bot"}' \
  http://127.0.0.1:18001/api/v1/messages/send
```

## 安全建议

1. 不要把 API Key 写进源码、聊天记录、URL 或公开日志，优先使用环境变量。
2. 公网访问必须配置 HTTPS 和访问控制；不需要公网时只允许可信网络访问。
3. 第三方工具不再使用时立即轮换 API Key。
4. 开放 API 可以启停插件、修改配置、读写插件数据和发送消息，应视为管理员级自动化权限。
5. 插件源码、运行日志和 KV 数据都可能包含敏感业务信息，不要向不可信程序提供 API Key。

## 系统累计安装统计

“关于 AWBotNest”的累计安装量由独立热度服务汇总，包含首次安装和重新部署次数，
不是独立系统数、用户数、镜像拉取次数或在线数量。

- 本机 `GET /api/ui/about`（需管理员登录）中的 `installations` 返回
  `{"total": 123, "enabled": true, "stale": false}`，数字仅为示例。
  未成功获取过数量时 `total` 为 `null`，页面显示 `—`；远程失败保留上次数量。
- 页面只读内存缓存，不触发远程登记或查询，也不等待热度服务。
- 系统可用后在后台登记当前部署，成功后每小时刷新数量；失败五分钟后重试。
  请求有短超时、响应大小限制，服务不可用不影响启动或插件运行。
- “系统设置 → 维护 → 匿名安装统计”默认开启。关闭并保存后停止统计请求，
  同一部署再次开启沿用原有标识，无需重启；已经登记的历史安装不会因关闭而扣减。
- 管理员设置接口 `PUT /api/settings` 支持布尔字段
  `system_install_statistics_enabled`；现有网页格式使用
  `settings.SYSTEM_INSTALL_STATISTICS_ENABLED`。省略该字段不会重置已保存的选择。

身份与缓存保存在 `data/system_installation.json`，不包含在系统配置导出包中。
首次安装、覆盖版本、更新镜像、保留数据目录重建容器都分别计一次。
普通重启、打开页面、相同部署的失败重试不重复增加。
容器的可写层部署标识用于识别重建；后端核心、已构建前端发布资源和版本的指纹用于识别源码覆盖，
同版本仅更新前端发布资源也能识别。上述标识和指纹只在本地使用，不读取数据目录或插件配置。
仅拉取镜像但未部署不增加。前后端发布内容、版本及构建标识全部未变的原样复制无法判断为新部署；
只读容器无法保存部署标记时，仅能识别代码变化，不会以每次启动生成随机标识的方式凑数。
每个部署周期的登记标识由持久化随机种子派生，相同部署交替启动仍上报同一个标识，
不会因请求重试或多个进程重复计数。损坏的身份记录不会被自动覆盖或重新生成。
写入使用操作系统进程锁，异常退出后自动释放，不会遗留占用；未知旧版 `.lock` 文件不会自动删除或抢占。

登记仅发送部署周期 UUID（v4/v5）和协议编号，不发送根种子、容器标识、代码指纹、账号、
密钥、版本、插件清单、配置或日志。
热度服务仅保存标识的 SHA-256 摘要和首次登记时间，不跟踪活跃情况。
网络连接仍会暴露出口地址，反向代理访问日志应由部署者控制。

服务端需先部署支持 `POST /api/system-installations/register` 和
`GET /api/system-installations/count` 的新版热度服务；原插件接口与数据不变。
当前沿用插件热度服务地址，公网部署建议经域名和 HTTPS 提供，不能把匿名标识视为鉴权凭据。
旧安装在升级后陆续登记，不回填无法验证的历史数量。
