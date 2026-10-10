# 插件组合

Utter 的内置功能由 SwiftPM 模块拥有，并通过插件注册到应用中。
桌面按键、HTTP、XPC 和 CLI 共用会话与交付服务。插件可替换其契约提供者，
设置页和菜单项也由插件贡献；配置选择已经编入应用的插件。

在“设置 → 插件”编辑并保存 JSON。配置文件位于
`~/Library/Application Support/OpenType/plugins.json`，旧用户设置和模型目录保留。
默认组合为：

```json
{"schemaVersion":1,"bundles":["desktop"],"plugins":[],"bindings":{}}
```

组合按内置 bundle、已有用户设置、JSON 覆盖的顺序解析。已有设置页仍可选择
模型与服务商；显式 `bindings` 优先。以下配置使用本地 Whisper 和 MLX，
并隐藏关于页：

```json
{
  "schemaVersion": 1,
  "bundles": ["desktop"],
  "plugins": [{"id":"presentation.about","enabled":false}],
  "bindings": {"speech":"speech.whisper","text":"generation.mlx"}
}
```

| 能力 | 内置提供者 |
| --- | --- |
| `speech` | `speech.apple`、`speech.whisper`、`speech.volc`、`speech.qwen`、`speech.firered`、`speech.mega` |
| `text`、`fallback` | `generation.mlx`、`generation.ane`、`generation.remote` |
| `image` | `generation.mlx-image` |
| `mode.direct`、`mode.formatting`、`mode.command`、`mode.translation`、`mode.edit` | 对应同名 `mode.*` 提供者 |

停用插件时必须保留所选提供者及其依赖；保存会检查未知字段、未知 ID、
依赖缺失、冲突和失效绑定。插件装卸需要重启应用；当前已装载提供者之间
的绑定调整供下一次会话使用，进行中的会话保留开始时的配置。

文件损坏或组合无法启动时，应用进入配置恢复界面，并保留原文件。
“恢复默认”会先备份已有配置，再保存内置组合；重启后重新装载。
备份文件与配置在同一目录，可在退出应用后恢复。

## 开发替换插件

`UtterContracts`、`UtterMediaContracts`、`UtterPresentationContracts` 定义服务与值。
`UtterRuntime` 校验依赖并管理注册、撤销、清理和作用域。
功能模块导出 `PluginRegistration`；`UtterBuiltins` 是实现模块之间的装配入口，
`Sources/App/` 只负责启动与退出。

替换插件使用相同插件 ID，声明其提供的契约与依赖，并在
`BuiltinApplication.start(replacements:)` 注入。新增插件通过 `additional:` 注册。
每个服务只有一个当前提供者；跨模块调用通过契约。撤销时先拒绝新工作，
等待已借用的任务与副作用清理完成，再释放依赖。

插件代码随应用一起构建和签名。本阶段的 JSON 组合不安装外部二进制，也不改变
macOS 权限或签名边界。新增服务商仍需显式注册其能力绑定与模型目录信息。
