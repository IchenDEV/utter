<div align="center">

# Utter

**Local AI-powered voice input for macOS menu bar**

---

[![GitHub Stars](https://img.shields.io/github/stars/IchenDEV/utter?style=flat-square&logo=github&color=ffcc00)](https://github.com/IchenDEV/utter/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/IchenDEV/utter?style=flat-square&logo=github&color=4a90d9)](https://github.com/IchenDEV/utter/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/IchenDEV/utter?style=flat-square&logo=github&color=red)](https://github.com/IchenDEV/utter/issues)

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/mac/m1/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

[![WhisperKit](https://img.shields.io/badge/Powered%20by-WhisperKit-blue?style=flat-square)](https://github.com/argmaxinc/argmax-oss-swift)
[![MLX](https://img.shields.io/badge/Powered%20by-MLX--LM-orange?style=flat-square)](https://github.com/ml-explore/mlx-swift-lm)

[Website](https://utter.idevlab.dev) · [中文文档](README_zh.md)

</div>

---

## Overview

**Utter** is a macOS menu bar app for AI-powered voice input and dictation. It supports both fully local on-device inference and remote LLM APIs. Press a hotkey to start recording, release to transcribe, and the result is typed directly into whatever app you're using.

Three output modes are available:

- **Verbatim** — raw transcription, lowest latency
- **Smart Format** — transcription cleaned up by an LLM (contextual filler removal, grammar fixes, structured formatting)
- **Voice Command** — speak a command and get an AI-generated response based on screen context

## Features

| Feature | Description |
|---|---|
| **Multiple Speech Engines** | Apple Speech, WhisperKit, Doubao ASR, or Qwen3-ASR |
| **Smart Text Processing** | Local MLX Qwen2.5/Qwen3 or remote LLM infers spoken intent — contextual cleanup, "scratch that" restarts, self-correction handling, spoken punctuation, technical terms, numbers/ranges/units, and structured formatting |
| **LLM-Owned Spoken Formatting** | Spoken casing, no-space dictation, identifiers, file paths, shortcuts, emoji, Markdown tasks, dates/times, quantities, units, formulas, fractions, and digit sequences are handled by the Smart Format / Voice Command prompts instead of local hardcoded rewrite rules |
| **Voice Edit Commands** | In Voice Command mode, an LLM classifies safe structured actions for replacing, undoing, proofreading, titling, summarizing, drafting replies, making meeting notes, extracting key points/decisions/questions/risks/deadlines/owners/action items, rewriting tone, expanding, making tables/lists, or deleting the previous Utter insertion or selected text |
| **Verbatim & Preview Boundary** | Verbatim mode, streaming HUD, integration partials, and instant-insert drafts keep ASR text close to raw output with only dictionary, whitespace, duplicate, and non-speech-artifact cleanup |
| **Remote LLM Support** | OpenAI, Claude (Anthropic format), Gemini, OpenRouter, SiliconFlow, Doubao, Bailian, MiniMax (CN & Global) |
| **Global Hotkey** | Configurable key (Fn/Ctrl/Shift/Option) with long-press, double-tap, or single-tap activation |
| **Translation Dictation** | Use a dedicated hotkey chord to speak in one language and insert an English, Chinese, Japanese, Korean, Spanish, French, or German translation |
| **Screen Context OCR** | Captures on-screen text via ScreenCaptureKit + Vision to help the LLM correct homophones |
| **Voice Command Mode** | Screen-aware voice assistant — summarize, reply, translate based on what's on screen |
| **Input Memory** | Recent input history injected as LLM context for better continuity |
| **Industry Vocabulary** | Choose Medical, Legal, Finance & Accounting, or Software Technology terms for Apple Speech / Whisper biasing and output normalization; personal terms take priority |
| **Edit Rules** | Personal text replacement rules applied on every output |
| **Language Style Presets** | Concise / Formal / Casual / Custom prompt per language |
| **Input History & Stats** | Full history with raw vs. processed comparison, word count stats, configurable retention |
| **Bilingual UI** | Chinese and English interface, independent of recognition language |
| **Sound Feedback** | Audio cues on recording start and stop |
| **Guided Onboarding** | Step-by-step setup: permissions, model download, and first use |

## System Requirements

- **OS**: macOS 26 (Tahoe) or later
- **Chip**: Apple Silicon (M1 / M2 / M3 / M4)
- **Disk**: ~400 MB minimum (Apple Speech + Qwen3-0.6B), up to ~4 GB with larger models

## Installation

### Download

Grab the latest `.dmg` from [Releases](https://github.com/IchenDEV/utter/releases), open it, and drag **Utter.app** to Applications.

> **"Cannot verify the developer" on first launch?** The app is not notarized by Apple. Before first run, execute in Terminal:
> ```bash
> xattr -cr /Applications/Utter.app
> ```
> Or go to System Settings → Privacy & Security and click "Open Anyway".

### Build from Source

```bash
# Build .app bundle + .dmg installer
bash scripts/build-app.sh

# Or for development
swift build
swift run OpenType

# Build, sign, and launch the development .app bundle
bash scripts/build-and-run.sh --verify

# Or open in Xcode
open Package.swift
```

Material changes follow the artifact-driven workflow in
[`docs/sdlc/README.md`](docs/sdlc/README.md). Before opening a pull request, run:

```bash
python3 scripts/sdlc.py validate --worktree
bash scripts/ci-basic-checks.sh
swift test
```

The public app is `Utter.app`. The Swift package product remains `OpenType` so existing source integrations and upgrade paths continue to work.

## First Run

1. Launch Utter — it appears as a waveform icon in the menu bar
2. The onboarding wizard guides you through permissions and model setup
3. Grant **Microphone** and **Accessibility** permissions (required)
4. Wait for the LLM model to download (~335 MB, one-time)
5. Hold **Fn** to start dictating, release to stop and insert text

## Permissions

| Permission | Purpose | Required |
|---|---|---|
| Microphone | Audio capture | Yes |
| Accessibility | Global hotkey + text injection (simulated paste) | Yes |
| Speech Recognition | Apple on-device ASR engine | Only if using Apple Speech |
| Screen Recording | OCR for screen context and Voice Command mode | Optional |
| Network | Model downloads; remote LLM API calls | First run / remote LLM mode |

## Remote LLM Providers

Utter supports both **OpenAI-compatible** and **Anthropic** API formats:

| Provider | API Format | Base URL |
|---|---|---|
| OpenAI | OpenAI | `https://api.openai.com/v1` |
| Anthropic Claude | Anthropic | `https://api.anthropic.com/v1` |
| Google Gemini | OpenAI | `https://generativelanguage.googleapis.com/v1beta/openai` |
| OpenRouter | OpenAI | `https://openrouter.ai/api/v1` |
| SiliconFlow | OpenAI | `https://api.siliconflow.cn/v1` |
| Volcengine Doubao | OpenAI | `https://ark.cn-beijing.volces.com/api/v3` |
| Alibaba Bailian | OpenAI | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| MiniMax (China) | OpenAI | `https://api.minimax.chat/v1` |
| MiniMax (Global) | OpenAI | `https://api.minimaxi.chat/v1` |

## Local ASR Providers

| Provider | Local runtime | Default model |
|---|---|---|
| Qwen3-ASR | Native Swift + MLX on Apple Silicon | `mlx-community/Qwen3-ASR-1.7B-bf16` |

Qwen3-ASR does not call a hosted ASR API. The app downloads the selected model into the same model storage used by WhisperKit and runs inference locally through native Swift and MLX.

## Project Structure

```
Sources/
├── App/          # Entry point, AppDelegate, AppState, VoicePipeline, AppIcon
├── Audio/        # Microphone capture (AVAudioEngine), sound playback
├── Config/       # AppSettings, ModelCatalog, RemoteModelConfig, Localization
├── Hotkey/       # Global hotkey via CGEvent tap
├── LLM/          # LLMEngine (MLX), RemoteLLMClient (OpenAI/Anthropic)
├── Output/       # Text injection (Accessibility API + clipboard paste)
├── Processing/   # TextProcessor, InputHistory, MemoryStore, personal and industry vocabulary
├── Prompts/      # PromptBuilder, prompt catalogs, style prompt presets
├── Screen/       # Screen OCR (ScreenCaptureKit + Vision)
├── Speech/       # SpeechEngine protocol, WhisperKit, Apple Speech, Doubao ASR, local ASR engines
├── UI/           # SwiftUI: MenuBar, Settings, Onboarding, Overlay, History, Models
└── Resources/    # Localization strings (en/zh-Hans), sounds, app icon
scripts/
├── build-and-run.sh        # Build, sign, and launch a development .app bundle
├── build-app.sh            # Build release .app bundle and .dmg installer
├── ci-basic-checks.sh      # CI guardrails for linked files and resources
├── create-signing-cert.sh  # Generate self-signed code signing certificate
├── generate-icon.swift     # Generate AppIcon.icns from source PNG
├── test-industry-lexicons.sh # Validate vocabulary recall and non-target preservation
├── unit-test-coverage.sh   # Run unit tests with coverage thresholds
└── validate-volc-asr.swift # Validate Volcengine ASR configuration manually
```

## Tech Stack

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — offline Whisper speech recognition
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — local LLM inference on Apple Silicon (Qwen2.5 / Qwen3)
- **SwiftUI + AppKit** — native macOS UI
- **ScreenCaptureKit + Vision** — screen OCR
- **AVAudioEngine** — low-latency microphone capture
- **Apple Speech Framework** — on-device speech recognition

## License

[MIT](LICENSE)

---

<div align="center">

Made with care for Apple Silicon

</div>
