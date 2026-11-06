# AWBotNest 2 插件开发指南

AWBotNest 插件是可以独立安装、启用、停用和重载的功能单元。系统提供 Telegram、HTTP、Cookie、浏览器、AI、异步存储、Session、Telegram Delivery、通知、Webhook 和调度能力。

AWBotNest 2 使用 Telethon，仅支持按 V2 规范开发的插件。

## 快速开始

1. 新建 UTF-8 文本文件 `hello_world.py`，复制下方完整示例。文件名必须与 `__plugin__["id"]` 一致。
2. 在系统配置一个可用的 Telegram Bot；本例的 `scope` 为 `bot`。
3. 在「插件管理 → 上传插件」选择这个文件，或放入安装目录挂载的 `plugins/`。
4. 启用插件，向对应 Bot 发送 `/hello`，应收到回复。
5. 开发自己的功能时，修改名称、ID 和 `setup(ctx)` 中的事件或任务；保存文件后点击“重载”生效。

不需要获取系统核心源码，也不需要复制仓库内部模板。企业微信、独立运行或用户账号插件应选择相应的作用域，后文分别说明。

```python
__plugin__ = {
    "id": "hello_world",
    "name": "Hello World",
    "version": "1.0.0",
    "scope": "bot",
    "description": "回复 /hello",
}

async def setup(ctx):
    @ctx.on_message(pattern=r"^/hello$")
    async def hello(event):
        await event.reply("Hello World")

async def teardown(ctx):
    ctx.log.info("插件已停止")
```

## 插件形态

- 单文件：`plugins/<id>.py`
- 目录包：`plugins/<id>/__init__.py`

目录包适合拆分模块和携带资源。`id` 必须与文件名或目录名一致；以下划线开头的文件和目录不会被识别为插件。

## 元数据

`__plugin__` 必须是入口文件顶层的字面量字典，系统通过 AST 静态读取。

```python
__plugin__ = {
    "id": "my_feature",
    "name": "我的功能",
    "version": "1.0.0",
    "author": "作者",
    "description": "一句话说明功能",
    "tags": ["自动化", "消息处理", "数据统计"],
    "render_mode": "schema",
    "scope": "standalone",
    "bot": "",
    "instance_mode": "shared",
    "plugin_api_version": 2,
    "cookie_domains": ["example.org", "*.example.org"],
    "requires_plugins": [],
    "requires_capabilities": [],
    "provides_capabilities": [],
    "requirements": ["httpx>=0.28,<1"],
    "config_schema": {},
    "resources": {
        "timeout_seconds": 120,
        "max_concurrency": 8,
        "max_background_tasks": 32,
        "failure_threshold": 5,
        "recovery_seconds": 60,
    },
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| `id` | 是 | 唯一 ID，与入口名称一致 |
| `name` | 是 | 用户看到的名称 |
| `version` | 是 | 推荐语义化版本 |
| `scope` | 是 | `standalone`、`bot`、`user`、`both`、`wecom` |
| `description` | 否 | 面向用户的功能说明 |
| `author` | 否 | 插件卡片中 GitHub 图标旁显示的作者名 |
| `repository` | 否 | 源码所在的 GitHub 仓库，填写 `owner/repo` 或仓库根地址；旧安装核对更新来源时使用。从商店安装或更新的插件会自动记录来源。 |
| `tags` | 否 | 功能标签字符串列表；建议 1–4 个，每项不超过 24 个字符 |
| `bot` | 否 | 指定 Bot ID；留空使用默认 Bot |
| `requirements` | 否 | 启用前安装的 Python 依赖 |
| `config_schema` | 否 | 自动配置表单 |
| `render_mode` | 否 | `schema`（默认）或 `vue`；Vue 模式通过模块联邦加载插件配置组件 |
| `resources` | 否 | 超时、并发、任务数和熔断限制 |
| `instance_mode` | 否 | `shared`（默认）或 `account`；账号模式为每个所选在线用户创建独立实例 |
| `cookie_domains` | 否 | Cookie 只读权限范围，支持精确域名及 `*.example.org` |
| `requires_plugins` | 否 | 必需的前置插件 ID；系统不会自动下载或启用 |
| `requires_capabilities` | 否 | 必需的系统扩展能力名称 |
| `provides_capabilities` | 否 | 本插件声明提供的系统扩展能力名称 |
| `plugin_api_version` | 否 | 插件 API 版本，当前正式版本为 `2` |
| `min_platform_version` | 否 | 支持的最低系统版本 |
| `max_platform_version` | 否 | 支持的最高系统版本 |

作用域：`standalone` 不监听 Telegram；`bot` 监听 Bot；`user` 监听用户账号；`both` 同时挂载两者。
`wecom` 是企业微信专用插件，不需要 Telegram API_ID/API_HASH、Bot 或用户账号，
使用共享实例，通过 `ctx.on_wecom_message()` 接收系统统一回调。成员任务按 UserID 在插件内隔离。
专用插件不要填写 Telegram `bot` 字段，也不要使用 `instance_mode="account"`。
现有其他作用域的插件仍可订阅企业微信消息，不必更改作用域。

### Vue / 模块联邦配置界面（可选）

V2 默认使用 `config_schema` 自动生成配置界面。需要自定义 Vue 配置界面的目录插件可将 `render_mode` 设为 `vue`，并在 `frontend/dist` 发布模块联邦产物：

- 入口文件：`remoteEntry.js`（可位于 `dist/` 或 `dist/assets/`）
- 必须暴露：`./Config`
- `Config` 接收 `pluginId` 与 `host` props；通过 `host.getConfig`、`host.saveConfig` 读写配置，通过 `host.callApi` 调用插件 API
- `host.getConfig()` 对敏感字段只返回 `********`；需要在管理员配置页显示某个已声明的敏感字段时，使用 `await host.revealSecret(field)` 按字段读取真实值
- `host.ui.CronInput` 是系统统一 Cron 编辑器；`host.ui.cron.isValid(value)` 与 `host.ui.cron.describe(value)` 可用于自定义校验和说明
- 宿主会按插件 ID 动态注册远程模块，并在每次打开配置时刷新入口缓存

该接口是 V2 的正式插件扩展点，不依赖或修改 V1 前端；插件仍可选择使用 `config_schema`。

敏感字段支持递归声明：`list.fields`、`object.properties` 和 `array.items` 内的 `password`
或 `secret: True` 字段也会脱敏。顶层 `secret: True` 列表整体返回 `********`，读取后保留数组类型。
顶层字段仍可用 `host.revealSecret('token')`；嵌套字段使用 JSON Pointer，
例如 `host.revealSecret('/accounts/0/password')`。字段名中的 `~`、`/` 分别写为 `~0`、`~1`。
保存时同一路径的 `********` 会保留已保存值。列表删除或重排会改变下标，须先按原路径读取
待保留行的敏感值，再提交调整后的数组；原生配置表单会自动完成这一步。

## Python 依赖声明与安装

第三方 Python 包统一写在入口文件的 `__plugin__["requirements"]` 字符串列表中；无依赖时省略或填写 `[]`。仅放置 `requirements.txt`、`pyproject.toml` 或在市场清单中填写依赖，不会让系统自动安装。

```python
__plugin__ = {
    "id": "dependency_demo",
    "name": "依赖示例",
    "version": "1.0.0",
    "scope": "standalone",
    "requirements": ["httpx>=0.28,<1"],
}

import httpx  # 启用流程先处理依赖，再导入入口模块

async def setup(ctx):
    ctx.log.info("依赖示例已就绪")
```

### 声明规则

- 最多声明 50 项，使用发行包名称及版本约束，例如 `httpx>=0.28,<1`；不是任意 shell 命令。
- 不接受 URL/Git/本地路径依赖、pip 参数或带环境条件的声明，例如 `some-package; python_version < '3.13'`。
- 标准库（如 `json`、`asyncio`、`pathlib`）不用声明；发行包名和导入名不一定相同，例如 `beautifulsoup4` 对应 `bs4`。
- 当前检查器只检查发行包版本，不完整检查 extras 的附加依赖；不要仅靠 `package[extra]` 保证附加能力可用，应显式声明所需发行包并验证导入。
- 声明插件实际直接使用的第三方包，不要依赖开发机偶然已安装的包。不要把 V1 的 `schedulers` 等内部模块当作可安装依赖；调度使用 `ctx.schedule_interval` / `ctx.schedule_cron`。

### 安装时机与日志

1. 上传或市场安装先保存并校验插件；安装成功不代表已经启用或依赖已经安装。
2. 启用时检查当前 Python 环境能找到的发行包版本；缺包或不满足约束时，通过当前解释器的 `python -m pip install --target` 安装到 `data/plugin_deps`。
3. 已满足约束时跳过安装；多个插件需要安装时串行处理，并在获得安装锁后重新检查。因此首次启用可能等待其他插件安装。
4. 安装使用系统的代理和系统设置中的 pip 镜像源。单次 pip 执行最长 300 秒（不含等待安装锁的时间）。
5. 运行日志记录插件标题、所需依赖、开始安装、安装成功或失败原因。pip 失败显示末尾最多 2000 字符的输出；不是逐行实时输出。依赖失败时不会继续导入插件或执行 `setup`。

开关即时响应不代表后台初始化已完成；应以启用结果为准。插件不要在 `setup` 中自行运行 pip、修改系统环境或反复安装依赖。

### 共享环境与兼容性限制

`data/plugin_deps` 是持久化的共享目录，并加入系统进程的 Python 搜索路径；不是每个插件独立的虚拟环境，也不是安全沙箱。系统目前没有跨插件版本冲突求解、依赖升级事务或自动回滚保障。

开发者应选择与系统及其他插件兼容的版本范围。不要通过强制降级系统核心库解决单个插件的问题。当前安装命令不带 `--upgrade`，已有目标目录遇到版本变更时不能假定文件会正确替换；已导入模块也不会因为磁盘上的包变化而自动重新加载。遇到冲突应由管理员在备份和维护窗口内处理共享环境，必要时重启系统，不要让插件删除共享依赖目录。

`requirements` 只处理 Python 包，不安装操作系统库、编译器、浏览器可执行文件或 Node/npm 依赖。需要这些资源时，应在插件说明中列明 Windows/Linux、Python 版本及部署要求，并在缺失时给出清晰错误；优先使用系统提供的浏览器、HTTP、AI 等服务。自定义 Vue 界面由开发者构建后发布 `frontend/dist`，系统启用时不运行 npm 构建。

### 失败排查与发布检查

- “依赖声明不合法”：检查是否混入 URL、环境条件、文件路径或 pip 参数。
- “No matching distribution”或构建失败：检查包版本、当前 Python 版本、系统架构以及是否需要系统库/编译工具。
- 下载失败或超时：检查系统设置的 pip 镜像源、代理及对应服务可达性；GitHub Token 不用于 pip 包下载。
- 安装后仍提示缺模块：核对发行包名与导入名、extras、共享目录冲突，以及是否必须由管理员重启以加载变更。
- 发布前在干净环境验证首次启用、再次启用跳过安装、安装失败提示，以及多个插件共享依赖时的兼容性；日志和错误文本不得包含账号密码、Token 或私有源凭据。

`requirements` 是 Python 依赖，不是前置插件 ID 列表。前置插件使用 `requires_plugins: ["插件ID"]`；能力依赖使用 `requires_capabilities`，提供能力使用 `provides_capabilities` 并在 setup 中调用 `ctx.provide_capability(name, provider, priority=100)`。通过 `await ctx.call_capability(name, ...)` 调用，优先级高的提供者失败后尝试备用提供者。系统不自动启用缺失的前置插件，`dependencies` 不是受支持的别名。

插件默认应彼此独立；`requires_plugins` 仅用于少数边界清晰、确有必要的扩展场景。Capabilities 是系统扩展点，不是通用的 plugin-to-plugin RPC；普通插件不得借此取得其他插件实例、共享内部状态或形成链式依赖网络。

`instance_mode: "account"` 为每个所选在线用户账号创建独立上下文；默认 `"shared"` 保持全局实例。账号模式使用 `ctx.account_name`、`ctx.instance_id` 和 `ctx.user`。每个账号实例拥有独立的 storage、Session namespace、scheduler jobs、Delivery lifecycle 和 `data_dir`。不要把账号实例的 SQLite 隐式改成共享存储；确实需要共享数据时，应等待系统提供明确的 shared storage 能力。所有后台任务应通过 `ctx.create_task` 创建，额外资源通过 `ctx.add_cleanup(callback)` 登记清理。

读取系统 Cookie 必须声明 `cookie_domains`，如 `["example.org", "*.example.org"]`。`ctx.cookies.get/header/playwright` 支持 `path`；`get/header` 还支持 `names`。`ctx.cookies.available` 表示服务与快照可用，`await ctx.cookies.request_sync(domain)` 在已有有效 Cookie 时返回 True，否则提醒同步并返回 False。不得直接修改系统 Cookie 存储。

## Telethon 事件

回调只接收一个 Telethon Event：

```python
async def setup(ctx):
    @ctx.on_message(pattern=r"^/echo(?:\s+(.+))?$")
    async def echo(event):
        text = event.pattern_match.group(1) or "echo"
        await event.reply(text)

    @ctx.on_edited_message(pattern=r"^/status$")
    async def edited(event):
        await event.reply("消息已编辑")

    @ctx.on_callback(pattern=b"confirm")
    async def callback(event):
        await event.answer("已确认")
```

注册器：

- `ctx.on_message(pattern=None, chats=None, incoming=True, outgoing=False, interactive=False)`
- `ctx.on_edited_message(pattern=None, chats=None, interactive=False)`
- `ctx.on_callback(pattern=None, interactive=False)`

对按钮、小游戏和其他延迟敏感的短回调，可以显式传入 `interactive=True`：

```python
@ctx.on_callback(pattern=b"play", interactive=True)
async def play(event):
    await event.answer()
```

Interactive Fast Path 保留关闭检查、运行任务追踪、插件归属、异常隔离、取消传播和停用清理；
它不进入普通 Governor，因此不占用插件级并发信号量，也不执行通用超时、执行日志和熔断。
长任务、需要资源治理或完整执行事件记录的处理器继续使用默认路径。交互状态应放在
`ctx.sessions` 中并由插件按真实 session key 加锁，不要在每次交互中读写 SQLite Storage。

系统交互性能分析默认关闭。排查真实延迟时可在启动系统前设置：

```text
AWBOTNEST_INTERACTIVE_PROFILE=1
AWBOTNEST_INTERACTIVE_PROFILE_SLOW_MS=100
```

启用后，interactive wrapper 自动测量 dispatch 和 callback 总时长；通过 `ctx.sessions` 获取的
Session lock 会记录等待及持锁时间，`ctx.delivery.send/edit` 会记录每次 Telethon RPC await。
超过阈值时系统只输出脱敏摘要，最近 200 条内存记录可由 `ctx.interactive_profile.recent()`
在本地诊断中读取，不写入磁盘。直接调用 `event.answer/reply/edit` 或原生 client 方法不会被
自动拦截；系统不 monkey patch Telethon。

真实网络调用应在本地单独测量，记录耗时分布和 FloodWait 次数；测试脚本、账号数据和
结果不提交。可比较当前代理、直连和其他节点，测试时不要更改已保存的系统设置，输出
中的代理凭据和账号标识必须脱敏。

### Interactive / 实时插件性能规范

普通 handler 适合低频命令、后台业务和需要完整 Governance 的自动化；文字游戏、抢答、
按钮互动和高频多人输入才应显式使用 `interactive=True`。Fast Path 只降低 AWBotNest 收到
update 后的本地 dispatch 开销，不能消除 Telegram RPC、FloodWait 或插件自身慢操作。

Session lock 只保护短小的内存状态变化：

```python
session = await ctx.sessions.get(str(event.chat_id))

async with session.lock:
    apply_action(session.data)
    text = render(session.data)

await event.edit(text)
```

不要在锁内执行 `event.edit()`、`ctx.storage.get/set()`、`ctx.http.get()`、`ctx.ai.chat()`
或其他网络、SQLite、AI、Browser await。实测纯内存临界区为微秒级；模拟持锁约 20ms 的
慢 await 时，50 个并发任务的 lock wait median 可达到约 500ms。具体数值随机器和负载
变化，但排队关系不变。

当前回合、HP、手牌、题目、抢答状态和本局选择放入 `ctx.sessions`；积分、排行榜、长期玩家
资料、配置、历史和最终结算写入 `ctx.storage`。不要让每条互动命令都往返 SQLite。

真实 Telegram RPC 通常远高于本地 dispatch。一个玩家动作应尽量在内存完成状态变化后只做
一次最终 Telegram 更新，避免无必要的 `send → edit → edit` 串行调用。按钮交互在完成必要的
短本地权限、时效和玩家身份验证后，应尽早 `await event.answer()`；不要在 answer 前执行
HTTP、SQLite、AI 或 Browser 操作。

`ctx.bot` 是可用 Bot 或 `None`，`ctx.users` 是在线用户客户端列表。不要跨越停用、重载或重连缓存客户端。

### 发送文件（Telegram）

Telegram 已支持 Telethon 原生文件发送，不需要另外配置 Bot Token 或调用系统内部接口。
在 `ctx.on_message()` 回调中，可将插件生成的文件作为回复发送：

```python
from io import BytesIO

async def reply_export(event, excel_bytes: bytes):
    with BytesIO(excel_bytes) as file:
        file.name = "账本.xlsx"
        await event.reply("导出完成", file=file, force_document=True)
```

`excel_bytes` 是插件已生成的 Excel 内容，不是文件路径。`file.name` 决定接收端显示的文件名；
`force_document=True` 按文件发送。发送完成前不要关闭文件对象。
需要指定会话时，使用当前可用客户端的 `await client.send_file(chat_id, file, force_document=True)`；
客户端可取自 `ctx.bot`、`ctx.user` 或当前 `event.client`，使用前检查是否可用。
`event.reply()` 回复原会话，群消息会发回群里；私人账单等内容应限制在已授权用户的私聊中处理。
文件大小、发送权限和限流遵循 Telegram 与 Telethon 的限制，不套用下面企微接口的 20 MiB 限制。

## 配置表单

原生 schema 表单拒绝未声明字段。自定义 Vue 配置页允许额外业务字段，系统会保留其值，并继续校验已声明字段；密码等敏感字段仍应在 schema 中声明 `secret: True`，以便读写时脱敏。

```python
"config_schema": {
    "enabled": {
        "type": "boolean", "default": True, "label": "启用功能",
        "section": "常规", "cols": 6, "order": 1,
    },
    "keyword": {
        "type": "string", "default": "hello", "label": "关键词",
        "help": "收到包含此词的消息时触发", "required": True,
        "section": "常规", "cols": 6, "order": 2,
    },
    "token": {"type": "password", "default": "", "label": "访问令牌"},
    "mode": {
        "type": "select", "default": "reply", "label": "处理方式",
        "options": [{"value": "reply", "label": "回复"}, {"value": "forward", "label": "转发"}],
    },
    "target": {
        "type": "chat", "default": 0, "label": "目标会话",
        "chat_types": ["group", "channel"], "multi": False,
    },
    "test": {"type": "action", "label": "测试连接", "action": "test"},
}
```

界面类型：`string`、`password`、`number`、`boolean`、`select`、`multiselect`、`slider`、`text`、`list`、`chat`、`info`、`action`。

Cron 字段沿用字符串类型，通过标准 `format` 显式声明。系统会显示统一的可视化编辑器，并在前端和服务端共同校验 5 位或 6 位表达式；不要再依赖字段名包含 `cron` 或 `schedule` 的自动猜测：

```python
"schedule": {
    "type": "string",
    "format": "cron",
    "default": "6 3 * * *",
    "label": "执行周期",
    "help": "按 Asia/Shanghai 时区执行",
}
```

旧插件的 `type: "cron"` 仍兼容，但新插件应使用 `type: "string", format: "cron"`，这样服务端也能同时执行字符串类型校验。

自定义 Vue 配置页继续使用既有的 `host` prop，不需要调用新的 HTTP 接口。系统组件支持 Vue `v-model`，也兼容 `value` / `update`：

```vue
<script setup>
import { computed, reactive } from 'vue'

const props = defineProps({ host: { type: Object, required: true } })
const form = reactive({ schedule: '6 3 * * *' })
const CronInput = computed(() => props.host.ui.CronInput)

async function save() {
  if (!props.host.ui.cron.isValid(form.schedule)) {
    props.host.toast.error('执行周期格式不正确')
    return
  }
  await props.host.saveConfig(form)
}
</script>

<template>
  <label>执行周期</label>
  <component :is="CronInput" v-model="form.schedule" />
  <button type="button" @click="save">保存</button>
</template>
```

Vue 插件仍应在 `config_schema` 中为该字段声明 `type: "string", format: "cron"`。这样 `host.saveConfig()` 会经过系统服务端校验，不能仅依赖插件页面自己的前端判断。

常用属性包括 `default`、`label/title`、`help`、`required`、`options`、`min/max/step`、`section`、`order`、`cols`、`show_if`。`list` 使用 `fields`；`chat` 使用 `multi/chat_types/session`；`action` 使用 `action/danger`。

```python
keyword = ctx.config.get("keyword", "hello")
ctx.update_config({"last_run": "2026-08-31 12:00:00"})
```

动作按钮：

```python
async def setup(ctx):
    async def test(payload):
        return {"ok": True, "message": "连接正常"}
    ctx.action("test", test)
```

企业微信自建应用开启接收消息后，管理员可用 `/运行 插件ID 动作名` 调用同一动作，
无需再写企业微信回调。动作参数来自指令末尾的 JSON 对象，例如
`/运行 my_feature test {"account": "demo"}`，不带参数时为 `{}`。
只有已启用且关联到该通知渠道的插件可调用；仍经过系统的动作并发、超时和熔断控制。
执行结果私信发起成员；返回字符串或 `{"ok": true, "message": "连接正常"}` 可附带简短说明，
不要返回密码、Cookie 等敏感值。Telegram 消息处理函数不会通过此接口调用。
耗时动作应使用 `async def`，不要在动作中使用 `time.sleep()` 或同步网络请求阻塞事件循环。

### 系统助手调用动作与配置

现有 `ctx.action("test", callback)` 和装饰器写法继续有效。系统助手可以查询并调用这些已注册动作，**旧插件无需增加 `agent_exposed=True` 或重新适配**；写操作仍由管理员逐次确认。这里只兼容系统动作，不会把任意插件 API、Webhook、私有方法或所有 Vue 页面按钮都直接交给助手。

建议为动作补充用途和参数规范，帮助助手准确理解参数；这些声明也用于校验原有按钮、管理接口和消息渠道的调用：

```python
@ctx.action(
    "check_status",
    description="查询指定站点的最近签到结果，不执行签到。",
    parameters={
        "type": "object",
        "properties": {"site": {"type": "string", "enum": ["site_a", "site_b"]}},
        "required": ["site"],
        "additionalProperties": False,
    },
    read_only=True,
    agent_exposed=True,
)
async def check_status(payload):
    return {"site": payload["site"], "status": "已签到"}
```

- `description`：600 字以内的动作用途；显式声明 `agent_exposed=True` 时仍需填写。旧式注册无需为了兼容助手补充此项；用途不明时助手应询问，不能猜测业务含义。
- `parameters`：根节点必须是 `object`。支持 `properties`、`required`、`items`、`enum`、数字上下限和字符串/数组长度；不支持 `$ref`、正则、组合 schema 或未声明参数。定义深度、字段数、参数大小均有限制。不传参数规范时保留原网页按钮的传参兼容性；助手侧只允许空对象回退，不会猜测其他参数。
- `read_only`：仅查询、没有外部副作用才设为 `True`。默认 `False`；签到、发消息、打印、修改数据等都属于写入动作。不能为了省略确认把这些动作标为只读。
- `agent_exposed`：保留现有可选声明，默认 `False`；不再作为系统助手发现旧动作的必要条件。它不授予写权限，也不代替本次确认。这不是公开网络接口。

只向助手提供必要业务参数，不要求它传入密码、Cookie、Token、Session 或系统密钥，不在参数默认值、说明和返回值中放这些内容。含敏感参数的动作不会通过助手调用。
已声明参数的动作从按钮、管理接口、企业微信或助手调用时都会经过同一参数校验。动作仍由系统执行治理负责超时、排队和插件停用清理；助手排队时撤销授权或重载插件，旧调用会失效，不能借确认调用新注册的动作。
这不是任意方法调用接口，助手不能访问插件实例、私有 storage 或未注册的 Python 函数，也不能在主系统内安装插件或执行 Shell 命令。
系统助手可通过专用工具查询并修改 `config_schema` 中的非敏感配置，无需新增插件接口。修改使用目录返回的 JSON Pointer 字段路径，先显示旧值与新值并确认，再复用原有校验及配置生效流程。密码、密钥、Cookie、Session 和整体标为敏感的容器不向助手开放；其他对象或列表可以只修改已公开叶子，例如 `/accounts/0/cron`，保留同一行的密码等字段，不整体替换含敏感子项的列表。自定义 Vue 页面可以保存的额外业务字段，不会因此自动成为助手可修改的配置。
插件应准确声明配置类型、必填项、Cron 等格式以及敏感字段，不能依赖字段是否出现在页面上保护秘密。助手不会读取私有存储、猜测隐藏字段，或用整份配置覆盖未修改项。
当插件使用已保存凭据时，助手还会排除可能转发凭据的地址、代理、请求头、命令和执行路径等字段；此类设置仍可由管理员在原配置页处理。不要将敏感值藏在无敏感标记的普通字段中，也不要通过动作返回这些内容。
助手可以在管理员确认后启用、停用或重载已安装插件，复用系统原有生命周期锁与清理流程；这与插件自行开放的业务动作是两类操作，不需要插件额外适配。业务参数不能借此传入 Python 方法或命令。
已配对管理员主动进入 `/助手` 模式后，相应 Bot 私聊或企微消息由系统助手处理；未配对、未进入助手模式及普通群消息仍沿用原有分发。插件无需接入助手的图片识别或转写内部接口。

## 企业微信统一消息回调

插件可使用系统已配置的企业微信自建应用回调，接收文字、图片、文件和菜单按钮事件，
不需要另配回调地址、Token、EncodingAESKey 或应用 Secret。
管理员需开启该通知渠道的消息回调、设置允许操作的成员，并在插件通知设置中关联此渠道。
只有已启用、已关联且主动注册消息处理器的插件会收到消息；不会调用 Telegram handler。

### 注册与过滤

只使用企业微信的插件可声明如下元数据，仍使用同一安装、启用、停用和重载流程：

```python
__plugin__ = {
    "id": "wecom_printer",
    "name": "企业微信打印",
    "version": "1.0.0",
    "scope": "wecom",
    "instance_mode": "shared",
}
```

通知渠道在系统中关联，不在 `bot` 字段填写渠道 ID。未绑定渠道时插件可以启用，但不会收到消息。

在 `setup(ctx)` 中注册一个处理器。下面的 `enqueue_file` 和 `print_job` 是打印插件自己的业务函数，
接入时替换为实际实现；`print` 也需换成该应用打印按钮的 EventKey。

```python
async def setup(ctx):
    @ctx.on_wecom_message(
        message_types=("image", "file", "event"),
        events=("click", "template_card_event"),
    )
    async def receive(message):
        if message.message_type in {"image", "file"}:
            media = await message.download_media(max_bytes=10 * 1024 * 1024)
            # 按发送者隔离待打印任务，并校验文件格式、大小与文件名。
            await enqueue_file(message.user_id, media.content, media.filename)
            await message.reply("文件已接收，请选择打印。")
        elif message.event_key == "print":
            await print_job(message.user_id, message.fields)
```

支持 `@ctx.on_wecom_message()`、`ctx.on_wecom_message(receive, ...)` 两种写法。
默认 `message_types=("text", "image", "file", "event")`；还可选择
`voice`、`video`、`shortvideo`、`location`、`link`。
`events` 只过滤 event 消息，不影响同时订阅的图片、文件等类型；省略时接收所有支持的应用事件。
类型和事件过滤不区分大小写，消息字段保留原值。每插件只有一个处理器，重复注册替换旧处理器。
账号多实例插件仅主实例注册并接收，不会为每个 Telegram 账号重复执行。

内置 `/帮助`、`/help`、`帮助`、`/状态`、`/status`、`/插件`、`/plugins`、`/动作`、`/运行`、`/run`
指令优先由系统处理，其他文字交给订阅 text 的插件；没有接收插件时仍返回指令帮助。
未识别的消息类型，以及缺少 AgentID 的系统事件只确认接收，不交给插件。

### 消息、回复与附件

回调参数是 `WeComMessage`，不需要导入系统内部模块。常用属性：

| 属性 | 含义 |
| --- | --- |
| `channel_id`、`user_id` | 通知渠道 ID、发送成员 UserID |
| `corp_id`、`agent_id` | 已核对的企业 ID、应用 ID |
| `message_id`、`create_time` | 消息 ID、发送时间戳（整数秒） |
| `message_type`、`text` | 消息类型、文字内容 |
| `media_id`、`pic_url` | 附件 ID、原始图片地址 |
| `file_name`、`file_size` | 回调中的文件名、大小（缺少大小时为 `None`） |
| `event`、`event_key` | 事件名称、按钮键 |
| `fields` | 完整结构化明文，保留嵌套按钮参数 |

`fields` 中 XML 标量是字符串，嵌套节点是字典。
`SelectedItems.SelectedItem`、`OptionIds.OptionId` 等官方重复节点始终是列表，只有一个元素也不例外。
每个插件收到独立副本，不能通过修改字段改变其他插件的消息或系统鉴权结果。

`await message.reply(text)` 只回复发送成员，不广播，也不转发到其他通知渠道。
处理器返回非空字符串时，系统也会私聊发送者；不要同时回复并返回同一段文字。
系统不为每张图片、每个文件额外发送默认“完成”消息。回复中不要包含密码、Cookie 等敏感值。

生成的 Excel、CSV、PDF 等文件可直接回传给发送成员：

```python
result = await message.reply_file(
    excel_bytes,
    "账本.xlsx",
    content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
)
# 成功时 result 为 {"ok": True}，不包含凭据或临时素材 ID。
```

正式签名为
`await message.reply_file(content: bytes | bytearray, filename: str, *, content_type: str = "application/octet-stream")`。
`content` 只接受内存中的文件内容，大小为 6 字节至 20 MiB；不接受路径、URL 或文件对象。
`filename` 必须是单个文件名，UTF-8 编码不超过 200 字节，不能包含目录、控制字符或 Windows 文件名禁用字符，
也不能使用 `.`、`..`、首尾空白或末尾句点。
`content_type` 是不带参数、长度不超过 127 字节的 MIME 类型，例如 `text/csv`，不接受 `text/csv; charset=utf-8`。
文件名和 MIME 类型由插件提供，系统不会替插件检查 Excel、PDF 等文件的实际格式。

接口复用当前自建应用的凭据，先上传临时素材，再发送文件；只发给本消息的原发送成员，
不支持指定其他收件人、群机器人 Webhook 或回退到其他通知渠道。插件不需要保存 Secret、access token 或调用上传接口。
上传及发送过程中会复查渠道、成员、插件绑定和运行状态；解绑、停用或重载会使旧消息对象失效。
参数无效、上传失败或权限失效时会抛出异常；最终发送已发起但回执无法确认时抛出 `DeliveryUncertain`，
不能据此认定没有送达。系统不会自动重发这类文件，插件也不应盲目重试，以免重复投递。
调用失败或被取消时不会继续尝试其他渠道；耗时导出和业务记录仍由插件负责。

下面仅演示生成 Excel 字节，再回传文件；不是完整记账插件。
插件需在 `requirements` 声明 `openpyxl>=3.1,<4`，不要在消息回调里同步生成大型表格：

```python
import asyncio
from io import BytesIO
from openpyxl import Workbook

def build_excel_bytes():
    workbook = Workbook(write_only=True)
    try:
        sheet = workbook.create_sheet("明细")
        sheet.append(["项目", "金额（元）"])
        sheet.append(["示例", 12.50])
        with BytesIO() as output:
            workbook.save(output)
            return output.getvalue()
    finally:
        workbook.close()

async def send_export(message):
    content = await asyncio.to_thread(build_excel_bytes)
    await message.reply_file(content, "账本.xlsx")
```

在 `ctx.on_wecom_message(message_types=("text",))` 的处理器中核对成员和导出命令后调用
`send_export(message)`。不要注册系统保留的 `/运行` 等命令作为业务命令。
业务字段若来自用户输入，应在写入 Excel 前按文本处理以防公式注入；导出范围和用户数据隔离由插件校验。

`await message.download_media(max_bytes=...)` 返回带 `content`（bytes）、`filename`、`content_type` 的媒体对象。
只按本消息的 MediaId 获取附件，默认和最大上限为 20 MiB；可设置更小限制。
不会自动下载图片、文件，也不会访问 PicUrl、事件参数或接口控制响应中的任意下载 URL。
若媒体接口只返回视频 URL 而非附件内容，此方法会报错，不跟随该 URL。
应用 Secret 和 access token 不提供给插件。下载期间会复查绑定和成员权限，并限制响应大小。
文件名已去除路径和控制字符，但插件仍需校验文件类型，不能直接执行文件或信任扩展名。
下载失败、超限等异常由插件按业务处理；耗时网络和打印任务需使用异步调用，不要阻塞事件循环。

### 重试、停用与迁移

系统先检查签名、解密内容、企业/应用身份和成员权限，再进入有界异步队列，HTTP 回调及时确认接收。
系统启动、插件尚在恢复时，有效的用户回调返回可重试的 `503`，不提前确认并丢弃消息；地址验证不受影响。
同一通知渠道的 MsgId 在 24 小时内去重；无 MsgId 的事件用完整明文生成稳定 ID，改变重试 nonce 不会重复执行。
同一用户在同一秒发出的完全相同无 ID 事件可能合并，打印插件仍应按 TaskId 或自己的任务状态防重复打印。
去重记录不保存正文或附件；内存队列不是持久任务队列，系统重启后不保证重放未完成任务。
需要可靠打印时，插件应在确认业务接收后将待打印任务写入自己的 storage。

处理器经过系统并发、超时、熔断和生命周期管理，插件间异常隔离。
解绑、停用或重载后，不再投递排队中的旧消息；旧消息对象也不能继续回复、发送文件或下载。
后台任务使用 `ctx.create_task()`，不要自行创建无法随插件停用取消的任务。

原先使用独立回调的插件，可将验签解密、读取附件和按钮分支迁移到此处理器，
保留原有打印业务和任务状态，验证后再移除独立回调及其配置。
已有 `ctx.action()`、Webhook、Telegram 事件和通知发送接口不变；插件未注册新处理器时行为不变。
`reply_file()` 自系统 `v2.0.2.6` 提供，属于 Plugin API 2 的兼容新增，旧插件无需迁移。
使用此方法的插件应在元数据声明 `"min_platform_version": "2.0.2.6"`；
回退到旧系统时需同时回退相应插件，不能将文件内容改用文字通知发送。

## 调度与后台任务

```python
async def setup(ctx):
    async def refresh():
        ctx.log.info("刷新完成")

    ctx.schedule_interval("refresh", refresh, seconds=300)
    ctx.schedule_cron("daily", refresh, hour=8, minute=0)
    ctx.create_task(worker(), name="worker")
```

注意：`schedule_cron` 的时间字段使用 APScheduler 的字段名（如
`hour=8, minute=0`），不要传入 V1 的 `schedulers` 模块或自行导入调度器。
推荐使用 `async def` 回调。系统也支持普通同步函数，并将其放入工作线程运行，避免阻塞 Telethon 事件循环。同步函数返回 awaitable 时系统仍会等待其完成。没有有效时间字段的系统会拒绝注册并写入错误日志。

停用时系统会移除事件、调度、Webhook 和动作，并取消通过 `ctx.create_task()` 创建的后台任务。不要直接创建系统无法追踪的永久任务。

## 系统服务

### HTTP

```python
response = await ctx.http.get("https://example.com/api", timeout=15)
response.raise_for_status()
data = response.json()
```

`ctx.http` 继承系统代理。下载使用 `ctx.http.download(url, destination)`。

### 本地 OCR

插件需要本地验证码识别时，在 `requirements` 声明 `ddddocr>=1.5`，再使用系统托管的
OCR 服务：

```python
text = await ctx.ocr.classification(image_bytes)
results = await ctx.ocr.classification_many([original, processed])
```

现有插件继续使用 `ddddocr.DdddOcr()` 也会自动接入同一服务。OCR 模型只在独立工作
进程中加载，多个插件串行共用，空闲后自动退出；不要自行长期保存 ONNX Runtime 模型。

`classification` 支持 `png_fix`、`probability` 和颜色过滤参数；兼容对象也支持
`set_ranges`、`slide_comparison` 和自定义模型路径。不同对象的字符范围互不影响。
只做滑块匹配时使用 `ddddocr.DdddOcr(ocr=False, det=False)`，不加载文字模型。
异步识别的超时包含排队时间；取消任务后不再提交尚未开始的识别。

### KV 与文件

```python
count = await ctx.storage.get("count", 0)
await ctx.storage.set("count", count + 1)
await ctx.storage.delete("old_key")
all_values = await ctx.storage.items()
cache_file = ctx.data_dir / "cache.json"
```

`ctx.storage` 是 V2 正式的异步持久存储接口。`ctx.kv` 是指向同一对象的命名兼容别名，同样必须 `await`；不要使用同步形式调用。单个 KV 值最大 10 MB，数据库最大 256 MB。账号实例默认使用独立数据库。

#### 需要 SQL 计算时

`ctx.storage` 只提供上面的键值接口，没有 `ctx.sql` 或公开的任意 SQL 执行接口。
需要按日期汇总、分类统计等关系查询时，插件可在自己的 `ctx.data_dir` 下创建 SQLite 数据库，
在 `requirements` 声明 `aiosqlite>=0.20,<1`，通过 `aiosqlite` 异步访问。
不要连接系统数据库、读取其他插件数据库，或依赖 `ctx.storage` 的内部表结构。

例如，插件已自行创建 `entries(owner_id TEXT, amount_cents INTEGER)` 表后，可查询某个用户的合计：

```python
import aiosqlite

async def total_cents(ctx, owner_id: str) -> int:
    async with aiosqlite.connect(str(ctx.data_dir / "ledger.db")) as database:
        async with database.execute(
            "SELECT COALESCE(SUM(amount_cents), 0) FROM entries WHERE owner_id = ?",
            (owner_id,),
        ) as cursor:
            return int((await cursor.fetchone())[0])
```

表创建、迁移、事务提交及访问权限由插件负责；参数用占位符传入，不拼接用户输入。
金额建议以整数分保存，汇总后再格式化为元，避免浮点计算误差。
企微成员用 `message.user_id`、Telegram 用户用 `event.sender_id` 区分；若同时支持多个渠道或应用，
还应把渠道类型和渠道/账号 ID 纳入业务用户键，不能将不同来源的同名用户合并。

### Session Runtime

Session 用于牌局、回合状态、临时交互和其他运行期内存状态；长期统计、配置和历史数据仍应写入 `ctx.storage`。

```python
session = await ctx.sessions.get(
    str(event.chat_id),
    ttl=1800,
    initial={"round": 1, "players": []},
)

async with session.lock:
    session.data["round"] += 1
    session.touch()

await ctx.sessions.reset(str(event.chat_id))
```

- `get()` 与 `open()` 获取或创建当前插件实例命名空间中的 Session。
- 同一 key 返回同一个有效 Session；不同插件、不同账号实例和不同 key 彼此隔离。
- 修改 `session.data` 时使用 `async with session.lock`，避免同一会话的并发更新互相覆盖。
- `ttl` 到期后由系统清理；访问或调用 `session.touch()` 会刷新活动时间。
- Session 只保存在内存中，插件停用或系统重启后不会保留。

### Telegram Delivery（可选）

简单消息仍可直接使用 Telethon 的 `event.reply()`、`client.send_message()` 和 `message.edit()`。高频发送、连续编辑或需要顺序治理时使用 `ctx.delivery`：

```python
await ctx.delivery.send(ctx.user, event.chat_id, "处理中")
await ctx.delivery.edit(message, "进度 80%", coalesce=True)
```

Delivery 按“账号 + chat”保持发送顺序，不同 chat 可以并发；重复编辑会跳过，短时间连续编辑可以合并为最终内容，FloodWait 只进行有限重试。插件停用或重载时，属于该实例的等待操作会被取消。不要在插件中增加全局 Telegram 发送锁。

### Cookie、浏览器与 AI

```python
cookies = await ctx.cookies.get("example.com")
cookie_header = await ctx.cookies.header("example.com", path="/account")
browser_cookies = await ctx.cookies.playwright("example.com", path="/")
html = await ctx.browser.page_source("https://example.com")
reply = await ctx.ai.chat("你好", system="回答要简洁")
description = await ctx.ai.vision("screenshot.png", "识别图片中的文字")
generated = await ctx.ai.generate_image("一张蓝绿色的极简海报")
```

`ctx.browser` 跟随系统选择的浏览器引擎。插件不应读取或保存系统的浏览器密钥，也不应自行安装
系统浏览器引擎。

插件声明 `cloakbrowser` 依赖并直接调用其 `launch*` 接口时，Key 统一使用系统设置，插件传入的
`license_key` 或 `env` 中的 Key 不会覆盖系统设置；验证授权、查询席位和更新内核也使用同一把 Key。
关闭免费 Key 模式或删除 Key 后使用无 Key 内核，不读取环境变量或缓存 `license.key`。
无 Key 模式不支持 `CLOAKBROWSER_BINARY_PATH` 自定义内核，以免旧授权文件被原生内核读取。
已启用 Key 的浏览器在系统内按单会话排队，运行、排队或等待席位释放时不能切换或停用 Key。
插件必须在 `finally` 中调用 `browser.close()` 或 `context.close()`；只关闭 Page 不会释放浏览器会话，
可能阻塞其他插件。未传 `proxy` 参数时自动继承系统代理；插件显式传入的 `proxy` 优先，传入
`proxy=None`（或 `False`）可选择直连。

Cookie 接口是插件作用域内的只读能力，不提供 `ctx.cookies.set()`。`get(domain, path="/", names=None)` 返回 Cookie 对象列表，而非键值字典；`header(domain, path="/", names=None)` 返回请求头字符串。按域名、hostOnly、路径边界和有效期筛选，长路径优先；同名请求头使用优先匹配值。`playwright(domain, path="/")` 保留浏览器 Cookie 属性。CookieCloud 同步保留路径及过期等属性。旧 V2 键值缓存只能按根路径读取，需重新同步才能恢复原始路径信息。

`ctx.ai.is_available("text" | "vision" | "image")` 可判断能力是否可用；
`ctx.ai.available_models(...)` 只返回管理员授权给当前插件的模型别名和能力。插件不得自行保存服务地址或密钥。

### 通知

```python
await ctx.notify("任务执行完成", category="定时任务", level="info")

# 结构化数据自动转换，不需要插件拼 HTML。
await ctx.notify([{"账号": "账号 A", "结果": "成功"}], level="success")
await ctx.notify_table(["账号", "结果"], [["账号 A", "成功"]],
                       caption="签到结果", align=["left", "center"], level="success")

# 与 V1 一致的账号级接口；使用当前用户或 Bot 自身身份。
if ctx.user:
    supported = await ctx.user.supports_native_rich()
    await ctx.user.send_rich("me", "<table><tr><td>成功</td></tr></table>", format="html")
# ctx.bot.send_rich(chat_id, content, format="html" 或 "markdown") 同样可用。
```

`notify_table(headers, rows, ...)` 支持 `caption`、`bordered`、`striped`、`align`、`valign`，
并通过 `notify` 的渠道路由投递。表格单元格自动转义，HTML 通知经过安全过滤。
普通 `ctx.notify(text)` 按 V1 规则识别连续键值、账号明细和紧凑任务统计；
无法识别的文本保留原意，不强制猜成表格。直接提交 dict/list 时按 V1 结构化规则转换。
已有 HTML 使用 `format="rich"`。普通 `client.send_message()` 不改变语义、不自动转换。
Bot 与 Premium 用户走原生富文本，普通用户的 HTML 表格降级为逐项可读文本。
账号 `send_rich` 支持 `is_rtl`、`skip_entity_detection`，发送选项使用 Telethon 参数；
另兼容 V1 的 `disable_notification` 和 `reply_to_message_id`。

不要在日志或通知中包含密码、Token、Cookie 或 Session。

## 仪表盘卡片

插件可以把只读统计显示在首页，不需要制作 Vue 页面或修改插件清单。
管理员在右下角的「设置仪表板」选择显示内容，在「调整卡片」中拖动和改变大小。
未接入此接口的旧插件不受影响，也不会自动出现业务卡片。

### 最小可用示例

将下面的注册放进插件已有的 `async def setup(ctx)`。示例只读取插件自己的已保存统计，
**不要在卡片回调中执行签到、下载、通知、数据库写入或调用插件按钮**。
任务完成时另外保存统计，首页刷新仅负责读取：

```python
async def setup(ctx):
    @ctx.dashboard.register(
        "overview",
        title="任务统计",
        description="最近一次任务的统计",
        default_size={"w": 4, "h": 8},
        min_size={"w": 3, "h": 5},
        refresh_interval=60,
    )
    async def dashboard_overview():
        # get 为异步接口；缺少统计时显示空状态，不在这里启动任务。
        stats = await ctx.storage.get("dashboard_stats", {})
        return {
            "metrics": [
                {"label": "已完成", "value": int(stats.get("completed", 0)),
                 "unit": "项", "tone": "success"},
                {"label": "待处理", "value": int(stats.get("pending", 0)), "unit": "项"},
            ],
            "rows": [
                {"label": "最近结果", "value": str(stats.get("result", "尚未运行"))},
            ],
            "progress": [],
            "message": "",  # 可省略；这里只放适合管理员查看的简短说明。
        }
```

也支持先定义回调，再调用：

```python
ctx.dashboard.register("overview", dashboard_overview, title="任务统计")
```

### 注册参数

`ctx.dashboard.register(widget_id, callback=None, *, title, description="",`
`default_size=None, min_size=None, refresh_interval=60)`：

| 参数 | 说明 |
| --- | --- |
| `widget_id` | 插件内稳定且唯一的卡片 ID，以字母开头，只包含字母、数字、`_`、`-`，不超过 64 字符。不能用 `constructor`、`prototype` 等对象保留名称，不要随重启变化。 |
| `callback` | 无参数的 `async def` 函数；省略时作为装饰器。不能传同步函数，以免阻塞系统。 |
| `title` / `description` | 标题不超过 120 字符；说明可为空，不超过 300 字符。 |
| `default_size` | `{"w": 4, "h": 8}`，宽度采用 12 列网格，高度采用网格行数，不是像素。 |
| `min_size` | 默认 `{"w": 3, "h": 5}`；`w` 为 1–12、`h` 为 2–40 的整数，默认尺寸不能小于最小尺寸。 |
| `refresh_interval` | 15–3600 秒的整数，默认 60；系统按此间隔缓存采集结果，不因多个页面打开而重复调用。 |

同一 ID 再次注册会替换旧卡片；每个插件最多注册 12 张卡片，系统最多接受 256 张插件卡片。
账号独立实例模式下，仅主实例生效；回调读取的是主实例自己的 `ctx.storage`，
不会自动读取或合并其他账号实例的数据。需要汇总时，应由插件通过其已授权的业务数据设计实现，
不能读取其他实例、其他插件的数据库。

### 回调返回的数据

只接受普通字典，未使用的列表可以省略。所有文字按纯文本展示，不支持 HTML、脚本、
组件、任意链接或事件处理器；卡片配置入口由系统固定指向对应插件配置页。

| 字段 | 数据格式与限制 |
| --- | --- |
| `metrics` | 最多 12 项：`{"label": "完成", "value": 12, "unit": "项", "tone": "success"}`。 |
| `rows` | 最多 100 项：`{"label": "最近执行", "value": "完成", "detail": "可选补充", "tone": "normal"}`。 |
| `progress` | 最多 20 项：`{"label": "处理进度", "value": 30, "total": 100, "unit": "项"}`。 |
| `message` | 可选纯文本，最多 600 字符；适合空状态或简短业务说明。 |
| `updated_at` | 系统返回本次采集完成的 UTC ISO 时间，插件无需填写；传入值不用于显示。 |

`label` 最多 80 字符，`value` 为有限数字或最多 240 字符的字符串（不接受布尔值、对象、列表），
`unit` 最多 24 字符，`detail` 最多 300 字符。`tone` 仅允许
`normal`、`muted`、`accent`、`success`、`warning`、`danger`，不传时使用默认颜色。
进度的 `value` 必须是非负有限数字；`total` 缺省 100，必须大于 0，且 `value <= total`。
单次响应不超过 64 KiB，格式错误会让当前卡片显示暂不可用，不影响其他卡片。

不要返回密码、Token、Cookie、Session、完整配置、异常正文或个人资料。
系统不会根据字段名猜测哪些业务值属于敏感数据，也不会自动读取插件配置；
开发者必须在回调中明确选取可展示的统计字段，不能直接 `return ctx.config` 或整份数据库记录。

### 读取与生命周期

管理员前端读取卡片的接口为：

```text
GET /api/dashboard/widgets
→ {"widgets": [{"id": "plugin:hello_world:overview", "plugin_id": "hello_world",
    "widget_id": "overview", "plugin_name": "示例插件", "title": "任务统计",
    "description": "", "default_size": {"w": 4, "h": 8},
    "min_size": {"w": 3, "h": 5}, "refresh_interval": 60}]}

GET /api/dashboard/widgets/hello_world/overview
→ {"data": {"metrics": [], "rows": [], "progress": [], "updated_at": "..."}}
```

这两个接口只接受管理员鉴权；开放 API Key 和公开 Webhook 都不能读取卡片。
插件必须已启用并完成初始化；停用、重载和初始化失败会清理注册、缓存及在途采集，
旧实例结果不能交给新实例。找不到卡片返回 404，临时繁忙、超时或格式错误返回 503，
不会回传原始插件异常。同一卡片并发读取合并为一次采集，失败后短暂冷却，避免刷新造成重试风暴。

采集共用原有插件 Governor 和后台任务归属，另有全局 4 个只读采集名额及 5 秒期限；
用户关闭页面不会取消其他页面共用的采集。回调必须使用真正异步 I/O、合理设置内部超时，
并让 `asyncio.CancelledError` 继续传播，不能自己创建脱离系统追踪的任务。
卡片大小、排序、显隐由系统前端分别保存电脑和手机布局，插件不应自行保存或覆盖它们。

这是一项 Plugin API 2 的可选兼容新增，无数据迁移。回滚到不支持此接口的旧系统前，
先回退调用新接口的插件；若必须同时支持新旧系统，可使用
`if hasattr(ctx, "dashboard"):` 包裹注册，原插件任务和存储保持不变。

## 配置页内部 API

配置页使用 `host.callApi('/status')` 或 `host.callApi('/run', {method: 'POST', body: {}})`，
访问管理员鉴权的 `/api/plugins/<id>/api/<path>`。插件在 `setup` 中注册：

```python
async def setup(ctx):
    @ctx.on_api("status")
    async def status(request):
        return {"ok": True}
```

也支持 `ctx.on_api("status", status)`。回调接收与下文 Webhook 相同的请求对象，
通过 `request.method`、`request.query`、`request.json` 读取请求；一个路径的不同 HTTP 方法由回调处理。
插件必须启用并完成初始化后才能调用，停用时接口自动移除。
内部 API 无需注册公开 Webhook，也不使用 Webhook 密钥；仅注册 `on_api` 的接口不会通过公开 Webhook 路径暴露。
管理员 API 兼容调用已有 `on_webhook` 同名接口，但新插件应使用 `on_api`；两者同名时内部 API 优先。

## Webhook

```python
async def setup(ctx):
    async def receive(request):
        signature = request.headers.get("x-signature", "")
        if not verify(signature, request.body):
            return {"ok": False, "error": "invalid signature"}
        return {"ok": True, "payload": request.json}

    ctx.on_webhook("receive", receive)
```

公开地址为 `/api/plugin/<插件ID>/receive`。请求对象提供 `method`、`path`、`query`、`headers`、`body`、`text` 和 `json`。插件必须自行验证调用方。

Webhook 路径必须与注册值完全一致（这里的 `receive` 不能改成 `/receive`，也不能省略）：

```text
注册：ctx.on_webhook("receive", receive)
调用：POST /api/plugin/hello_world/receive
```

调用未注册的路径会返回“Webhook 不存在”。插件停用或重载后旧路由会被清理，
调用方应在插件重新启用后再请求。签名校验失败时应返回错误结果，不要抛出包含密钥的异常。

## 资源保护

系统按 `resources` 限制回调时间、并发和后台任务数，连续失败达到阈值后熔断。插件仍应为外部请求设置超时并捕获可预期异常。

`asyncio.CancelledError` 表示插件停用、重载或系统关闭，必须继续抛出，不得作为业务异常吞掉。Telethon 的 `StopPropagation` 是正常的 handler 控制流程，不属于插件失败；需要终止后续 handler 时可抛出 `ctx.StopPropagation`。

## 发布到插件市场

兼容仓库根目录必须有 `manifest_v2.json`：

```json
{
  "plugins": {
    "hello_world": {
      "name": "Hello World", "version": "1.0.0", "author": "作者",
      "description": "示例插件", "scope": "standalone", "path": "hello_world.py"
    }
  }
}
```

条目也可直接放在顶层。清单中的 ID、版本和作用域必须与 `__plugin__` 一致。安装后默认不启用。

## 发布前检查

发布前验证 Windows/Linux、停用与重载清理、`standalone` 无账号运行，以及依赖失败不影响其他插件。

1. ID 与文件/目录名一致，版本与清单同步。
2. 使用 Telethon Event 单参数回调，不导入 Pyrogram/Kurigram。
3. 启用、停用、重载后没有遗留处理器或任务。
4. 外部请求有超时，网络失败不会拖垮系统。
5. 密钥不进入源码、日志、通知或公开响应。
6. Windows、Linux 路径使用 `pathlib`，不要写死盘符或 `/home`。
7. 只写 `ctx.data_dir` 和异步 `ctx.storage`（`ctx.kv` 是同一接口的兼容别名）。
8. 临时交互状态使用 `ctx.sessions`，高频 Telegram 输出按需使用 `ctx.delivery`。
9. 不吞掉 `CancelledError`，不创建系统无法追踪的永久后台任务。

硬性规则见 [SPEC.md](SPEC.md)。
