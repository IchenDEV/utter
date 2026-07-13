<div align="center">

# OpenType

**macOS 菜单栏 AI 语音输入**

---

[![GitHub Stars](https://img.shields.io/github/stars/IchenDEV/opentype?style=flat-square&logo=github&color=ffcc00)](https://github.com/IchenDEV/opentype/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/IchenDEV/opentype?style=flat-square&logo=github&color=4a90d9)](https://github.com/IchenDEV/opentype/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/IchenDEV/opentype?style=flat-square&logo=github&color=red)](https://github.com/IchenDEV/opentype/issues)

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/mac/m1/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

[![WhisperKit](https://img.shields.io/badge/驱动-WhisperKit-blue?style=flat-square)](https://github.com/argmaxinc/argmax-oss-swift)
[![MLX](https://img.shields.io/badge/驱动-MLX--LM-orange?style=flat-square)](https://github.com/ml-explore/mlx-swift-lm)

[官网](https://opentype.idevlab.dev) · [English](README.md)

</div>

---

## 项目简介

**OpenType** 是一款 macOS 菜单栏 AI 语音输入与听写应用，支持完全本地推理和远程 LLM API 两种模式。按住快捷键开始录音，松开后自动转写，结果直接输入到当前激活的应用中。

三种输出模式：

- **原文直出** — 语音识别原始结果，延迟最低
- **智能整理** — LLM 根据上下文清理语气词、修正口误、结构化排版
- **语音指令** — 说出指令，AI 结合屏幕内容生成回复

## 功能特性

| 功能 | 说明 |
|---|---|
| **多语音引擎** | Apple 语音识别、WhisperKit、豆包语音识别、Qwen3-ASR 或 MiMo-V2.5-ASR |
| **智能文字处理** | 本地 MLX Qwen2.5/Qwen3 或远程 LLM 理解口述意图 — 上下文感知的语气词清理、“算了/删掉刚才”重说处理、自动纠正、口述标点、技术词、数字/范围/单位和列表格式化 |
| **LLM 负责口述格式** | 大小写、无空格、标识符、文件路径、快捷键、表情、Markdown 任务、日期时间、数量、单位、公式、分数和数字串都由智能整理/语音指令提示词交给 LLM 判断，不在本地写死替换规则 |
| **语音编辑口令** | 在语音指令模式下，由 LLM 分类安全结构化动作，支持上一段/选区替换、撤销、校对、跨语言回复起草、接受/拒绝/追问回复、会议纪要、关键要点/结论/问题/风险/截止时间/负责人/行动项提取、标题化、摘要、语气改写、扩写、表格化、列表化、删除与改写口令 |
| **直出与预览边界** | 原文直出、流式 HUD、集成 partial 和快速插入草稿尽量保留 ASR 原文，只做词库、空白、重复转写和非语音垃圾过滤 |
| **远程 LLM** | 支持 OpenAI、Claude（Anthropic 格式）、Gemini、OpenRouter、硅基流动、豆包、百炼、MiniMax（国内/海外） |
| **全局快捷键** | 可配置按键（Fn/Ctrl/Shift/Option），支持长按、双击、单击三种触发模式 |
| **屏幕上下文 OCR** | 通过 ScreenCaptureKit + Vision 截取屏幕文字，辅助 LLM 纠正同音字 |
| **语音指令模式** | 屏幕感知的语音助手 — 总结、回复、翻译屏幕内容 |
| **输入记忆** | 近期输入历史作为 LLM 上下文，提升连续输入准确度 |
| **编辑规则** | 自定义文本替换规则，每次输出自动应用 |
| **语言风格预设** | 简洁精炼 / 正式书面 / 日常口语 / 自定义提示词 |
| **输入历史与统计** | 完整历史记录，原始文本与润色结果对比，字数统计，可配置保留时长 |
| **双语界面** | 中英文界面切换，独立于识别语言设置 |
| **音效反馈** | 录音开始/停止时播放提示音 |
| **引导式新手教程** | 分步设置：权限授予、模型下载、首次使用 |

## 系统要求

- **系统**：macOS 26 (Tahoe) 或更高版本
- **芯片**：Apple Silicon（M1 / M2 / M3 / M4）
- **空间**：最低约 400 MB（Apple Speech + Qwen3-0.6B），大模型最多约 4 GB

## 安装

### 下载安装

从 [Releases](https://github.com/IchenDEV/opentype/releases) 页面下载最新 `.dmg`，打开后将 **OpenType.app** 拖入"应用程序"文件夹。

> **首次打开提示"无法验证开发者"？** 由于应用未经 Apple 公证，首次运行前需在终端执行：
> ```bash
> xattr -cr /Applications/OpenType.app
> ```
> 或在"系统设置 → 隐私与安全性"中点击"仍然打开"。

### 从源码构建

```bash
# 构建 .app 包 + .dmg 安装器
bash scripts/build-app.sh

# 或开发模式
swift build
swift run OpenType

# 构建、签名并启动开发用 .app 包
bash scripts/build-and-run.sh --verify

# 或在 Xcode 中打开
open Package.swift
```

## 首次使用

1. 启动 OpenType — 菜单栏出现波形图标
2. 新手引导自动启动，引导完成权限和模型配置
3. 授予 **麦克风** 和 **辅助功能** 权限（必需）
4. 等待 LLM 模型下载完成（约 335 MB，仅首次）
5. 长按 **Fn** 键开始语音输入，松开后文字自动插入当前位置

## 权限说明

| 权限 | 用途 | 必需 |
|---|---|---|
| 麦克风 | 语音采集 | 是 |
| 辅助功能 | 全局快捷键 + 文本注入（模拟粘贴） | 是 |
| 语音识别 | Apple 语音识别引擎 | 使用 Apple Speech 时需要 |
| 屏幕录制 | OCR 屏幕文字辅助纠错 + 语音指令模式 | 可选 |
| 网络 | 下载模型；远程 LLM API 调用 | 首次运行 / 远程 LLM 模式 |

## 远程 LLM 服务商

OpenType 同时支持 **OpenAI 兼容** 和 **Anthropic** 两种 API 格式：

| 服务商 | API 格式 | 接口地址 |
|---|---|---|
| OpenAI | OpenAI | `https://api.openai.com/v1` |
| Anthropic Claude | Anthropic | `https://api.anthropic.com/v1` |
| Google Gemini | OpenAI | `https://generativelanguage.googleapis.com/v1beta/openai` |
| OpenRouter | OpenAI | `https://openrouter.ai/api/v1` |
| 硅基流动 | OpenAI | `https://api.siliconflow.cn/v1` |
| 火山引擎豆包 | OpenAI | `https://ark.cn-beijing.volces.com/api/v3` |
| 阿里百炼 | OpenAI | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| MiniMax（国内） | OpenAI | `https://api.minimax.chat/v1` |
| MiniMax（海外） | OpenAI | `https://api.minimaxi.chat/v1` |

## 本地语音识别服务商

| 服务商 | 本地运行方式 | 默认模型 |
|---|---|---|
| Qwen3-ASR | `qwen3-asr-mlx` + Apple Silicon MLX | `mlx-community/Qwen3-ASR-1.7B-bf16` |
| MiMo-V2.5-ASR | 小米本地 Python 运行文件 + 本地模型目录 | `XiaomiMiMo/MiMo-V2.5-ASR` + `XiaomiMiMo/MiMo-Audio-Tokenizer` |

这两个引擎不会调用托管 ASR API。App 会把选中的模型下载到 WhisperKit/MLX 使用的同一个模型存储位置，在应用管理的虚拟环境里准备 Qwen Python 运行环境，按需下载 MiMo 运行文件，自动寻找可用的 Python 3，再运行内置本地脚本。

## 项目结构

```
Sources/
├── App/          # 应用入口、AppDelegate、状态管理、语音管道、应用图标
├── Audio/        # 麦克风录音（AVAudioEngine）、音效播放
├── Config/       # 用户设置、模型目录、远程模型配置、多语言
├── Hotkey/       # 全局快捷键（CGEvent tap）
├── LLM/          # 本地推理引擎（MLX）、远程客户端（OpenAI/Anthropic）
├── Output/       # 文本注入（Accessibility API + 剪贴板粘贴）
├── Processing/   # 文本处理器、输入历史、记忆系统、个人词库
├── Prompts/      # 提示词构建、固定提示词目录、风格提示词预设
├── Screen/       # 屏幕 OCR（ScreenCaptureKit + Vision）
├── Speech/       # 语音识别协议、WhisperKit 引擎、Apple Speech 引擎、豆包语音识别引擎、本地语音识别引擎
├── UI/           # SwiftUI：菜单栏、设置面板、新手引导、浮动 HUD、历史、模型管理
└── Resources/    # 本地化字符串（中/英）、音效、应用图标
scripts/
├── build-and-run.sh        # 构建、签名并启动开发用 .app 包
├── build-app.sh            # 构建发布用 .app 包和 .dmg 安装器
├── ci-basic-checks.sh      # CI 文件关联和资源检查
├── create-signing-cert.sh  # 生成自签名代码签名证书
├── generate-icon.swift     # 从源 PNG 生成 AppIcon.icns
├── unit-test-coverage.sh   # 运行单元测试并检查覆盖率
└── validate-volc-asr.swift # 手动验证火山引擎 ASR 配置
```

## 技术栈

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — 离线 Whisper 语音识别
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — Apple Silicon 本地 LLM 推理（Qwen2.5 / Qwen3）
- **SwiftUI + AppKit** — macOS 原生 UI
- **ScreenCaptureKit + Vision** — 屏幕 OCR
- **AVAudioEngine** — 低延迟麦克风采集
- **Apple Speech Framework** — 系统语音识别

## License

[MIT](LICENSE)

---

<div align="center">

专为 Apple Silicon 打造

</div>
