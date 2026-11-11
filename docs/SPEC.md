# AWBotHub 插件公共契约

本文说明插件可以依赖的公开接口、数据边界和兼容要求，不是系统核心的开发规范。本仓库不公开核心实现；插件应使用 `ctx` 提供的接口，不依赖内部模块、数据库表或编译文件。

完整签名、参数、示例与发布方法见 [插件开发指南](PLUGIN_GUIDE.md)，外部程序的调用方式见 [开放 API](API.md)。

## 版本与入口

当前正式 Plugin API 版本为 `2`。AWBotHub 使用 Telethon，不兼容 V1 的 Pyrogram、Kurigram 或内部 `schedulers` 接口。

插件支持两种形态：

- 单文件：`plugins/<id>.py`。
- 目录包：`plugins/<id>/__init__.py`，可携带自己的资源及已构建配置页面。

入口需要顶层字面量字典 `__plugin__`，至少声明 `id`、`name`、`version`、`scope`，并提供可调用的 `setup(ctx)`；可选提供 `teardown(ctx)`。ID 与文件或目录名一致，不以下划线开头。元数据由静态解析读取，不要用函数、导入结果或运行期表达式生成。

受支持的 `scope` 为 `standalone`、`bot`、`user`、`both`、`wecom`。企业微信专用插件可使用 `wecom`，不需要 Telegram 账号；不要把 Telegram 账号实例当作企业微信成员实例。

## 生命周期与实例隔离

`setup(ctx)` 用于注册事件、定时任务、动作、接口和清理回调；`teardown(ctx)` 释放插件自行申请的资源。插件必须能安全停用和重新加载，初始化失败不能影响无关插件。

- 长期协程通过 `ctx.create_task()` 创建；额外资源通过 `ctx.add_cleanup()` 或 `teardown(ctx)` 释放。
- 使用当前上下文的客户端，不要跨停用、重载或重连缓存 Telegram 客户端。
- 默认 `instance_mode="shared"`；`"account"` 为所选 Telegram 用户账号建立独立上下文。
- 账号实例分别拥有自己的 Storage、Session、定时任务和数据目录，不要将其数据库隐式合并。
- 停用后不得继续处理事件或运行任务。取消时应继续抛出 `asyncio.CancelledError`，不能当作普通业务失败吞掉。
- 不依赖插件加载顺序，也不直接访问其他插件实例或内部状态。

## 公开能力

| 用途 | 公开入口 |
| --- | --- |
| Telegram 事件 | `ctx.on_message`、`ctx.on_edited_message`、`ctx.on_callback` |
| 企业微信入站消息 | `ctx.on_wecom_message` |
| 定时任务、后台任务 | `ctx.schedule_interval`、`ctx.schedule_cron`、`ctx.create_task` |
| 网页动作、配置页接口 | `ctx.action`、`ctx.on_api` |
| 外部 Webhook | `ctx.on_webhook` |
| 持久化、临时状态 | `ctx.storage`、`ctx.data_dir`、`ctx.sessions` |
| 网络与系统服务 | `ctx.http`、`ctx.browser`、`ctx.ai`、`ctx.ocr`、`ctx.cookies` |
| 通知与 Telegram 发送治理 | `ctx.notify`、`ctx.notify_table`、`ctx.delivery` |
| 仪表盘只读统计 | `ctx.dashboard.register` |

这里列出的是能力目录；具体参数和返回值以开发指南为准。不要根据名称推测未公开的方法。

### 事件、调度与执行

Telegram 事件使用 Telethon 的单 Event 参数回调。定时任务通过上下文注册；Cron 至少需要一个有效时间字段。推荐异步回调，阻塞计算或同步 I/O 不要直接占用事件循环。

系统对事件、动作、定时任务等提供超时、并发及错误隔离。插件仍须为外部请求设置超时、限制重试，并正确关闭连接。Telethon 的 `StopPropagation` 是正常控制流，不属于插件故障。

高频互动可按开发指南显式使用 `interactive=True`，这不是解除生命周期和数据隔离的权限。临时回合状态使用 `ctx.sessions`，按真实业务键加锁；不要为所有账号和聊天设置一把全局锁。

### 配置与 Vue 页面

原生表单通过 `config_schema` 声明字段；自定义 Vue 配置页可保存额外业务字段，已声明字段仍接受系统校验。敏感字段必须明确标为敏感，例如 `secret: True` 或受支持的密码类型，不能依赖字段名猜测。

管理页面默认只返回敏感值掩码。Vue 页面使用 `host.revealSecret(field)` 按字段受控读取真实值；不要将掩码写回覆盖已保存的凭据。

Cron 字段显式声明 `type: "string", format: "cron"`，由系统统一显示编辑器并校验 5 位或 6 位表达式。Vue 页面可使用 `host.ui.CronInput`，保存仍通过 `host.saveConfig()`。

Vue 插件暴露 `./Config`，随插件发布构建好的 `frontend/dist/remoteEntry.js`。通过宿主注入的 `host.getConfig`、`host.saveConfig`、`host.callApi` 访问能力；系统启用插件时不运行 npm 构建。

### 存储与 SQL

`ctx.storage.get/set/delete/items` 是正式异步接口，必须 `await`；`ctx.kv` 是同一对象的兼容别名，不是同步接口。

持久文件放在自己的 `ctx.data_dir`。需要 SQL 汇总时，可在该目录创建插件自己的 SQLite 数据库，并通过声明的异步依赖访问；没有公开的 `ctx.sql` 任意 SQL 接口。不要读取系统数据库、其他插件数据库或依赖 Storage 内部表结构。

`ctx.sessions` 只保存运行期内存状态，停用或重启后不保留；长期数据应保存到 Storage 或自己的文件。

### 浏览器、AI、Cookie 与依赖

插件通过托管接口使用浏览器、AI 和 Cookie，不自行读取系统密钥或 Telegram Session。

- `ctx.browser` 复用系统镜像内置的 CloakBrowser 和代理设置，支持多个会话同时运行，不需要 CloakBrowser Key。插件任务自身的并发、超时和队列限制仍然有效。直接使用 SDK 的插件仍须声明与内置 `0.5.12` 兼容的依赖；需要 GeoIP 时声明对应 extra。组件与内核随系统镜像更新，插件不要自行安装、在线更新或设置自定义浏览器路径；使用完正常关闭 Browser/Context。
- 浏览器双通道按架构匹配：AMD64 的 Stable/Preview 分别为 `156.0.8078.47.1`、`156.0.8078.47.3`；ARM64 分别为 `155.0.8059.39.2`、`156.0.8078.47.1`。指定版本时不得混用其他架构的版本号。
- AI 只使用管理员分配的模型与能力，插件不要另存系统服务地址或密钥。
- Cookie 必须声明 `cookie_domains`，接口只读，按域名、路径和有效期筛选；不得绕过授权读取完整 Cookie 存储。
- 第三方 Python 包在元数据 `requirements` 声明。系统启用前安装缺失或版本不符的依赖，目录为共享的持久化 `data/plugin_deps`，不是每插件独立环境。
- `requirements` 不安装系统库、浏览器二进制或 npm 依赖，也不提供跨插件版本冲突求解和自动回滚。不要在 `setup` 中运行 pip、强制降级系统核心库或删除共享依赖目录。

### 企业微信与文件回传

注册 `ctx.on_wecom_message()` 的已启用插件，可接收绑定渠道中通过成员白名单和消息类型过滤的文字、图片、文件或事件。不需要插件另设公开回调。

消息对象的 `reply()`、`reply_file()` 只回复原成员；`download_media()` 只读取当前消息的原附件。凭据由系统使用，不交给插件。文件大小、参数和完整示例见开发指南。

回调去重不等于持久任务保证，重启后未完成业务不保证重放。打印、记账或其他有副作用的操作，应由插件持久化业务状态并防重复。发送结果不确定时，不要自动重发。Telegram 文件回传可使用可用客户端的原生 `send_file()`。

### 仪表盘与助手

`ctx.dashboard.register()` 注册无参数异步只读采集回调，返回受支持的统计结构，不返回任意 HTML、JS 或组件。只读取插件自己已获授权的数据，不执行任务、写配置或发送通知，也不直接返回整份配置或数据库记录。

卡片大小、排序和显隐统一保存在系统中，电脑和手机共用一套布局，手机自动适配；插件不应自行保存或覆盖布局。

系统助手可发现已注册的 `ctx.action()`，不要求声明 `agent_exposed=True`。助手不执行任意插件方法或私有 API。写操作须管理员授权和逐次确认；未声明参数的动作在助手中只接受空对象，不能凭按钮名猜参数。

## 安全边界

插件是管理员安装的受信 Python 代码，并非系统强制隔离的沙箱。开发者必须自行遵守以下边界：

1. 不读取其他插件数据、系统配置文件、Telegram Session 或管理员凭据。
2. 密钥、Cookie、密码、验证码和会话内容不进入源码、日志、异常、通知或公开响应。
3. Webhook 验证调用方，并限制请求体和处理时长；不要把未鉴权接口变成任意代码执行入口。
4. 不绕过系统代理、域名授权、资源限制或停用清理。
5. 配置和数据操作保留未修改字段，格式变化提供迁移办法，不以删除用户数据作为默认升级方案。
6. 使用 UTF-8、可移植路径，并在涉及系统命令或架构特定依赖时明确部署要求。

## 发布与兼容

发布到商店时提供 `manifest_v2.json`，其 ID、路径、版本和作用域与入口元数据一致；作者、图标等公开展示信息也应保持一致。

只打包插件所需代码和资源，不包含真实配置、Token、Session、Cookie、`.env` 或用户业务数据。升级递增版本号，说明改动和不兼容项；新增接口可通过能力检测兼容旧系统，但不能假定所有旧镜像已经支持最新 SDK。

发布前在所声明的系统版本和架构上验证启用、停用、重载、配置保存、错误处理及资源释放。插件使用了新 SDK 时，声明对应最低系统版本，并在说明中提供升级要求。
