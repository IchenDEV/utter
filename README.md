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

## Demo Videos

<p align="center"><a href="https://utter.idevlab.dev/#videos"><img src="docs/assets/videos/utter-features-51s-poster.png" width="31%" alt="Feature tour" /></a> <a href="https://utter.idevlab.dev/#videos"><img src="docs/assets/videos/utter-day-58s-poster.png" width="31%" alt="A day at the office" /></a> <a href="https://utter.idevlab.dev/#videos"><img src="docs/assets/videos/utter-offline-28s-poster.png" width="31%" alt="Local voice input" /></a></p>

Watch on the [website](https://utter.idevlab.dev/#videos) or download the MP4s: [Feature tour (0:51)](docs/assets/videos/utter-features-51s-zh-vo.mp4) · [A day at the office (0:58)](docs/assets/videos/utter-day-58s-zh-vo.mp4) · [Local voice input (0:28)](docs/assets/videos/utter-offline-28s-zh-vo.mp4). All three have Mandarin voice-over. The UI is an animated reconstruction of the real app, and the sample texts are illustrative.

## Features

| Feature | Description |
|---|---|
| **Multiple Speech Engines** | Local Qwen3-ASR, Confucius4-R2T2, FireRedASR2, Mega-ASR, WhisperKit, or on-device Apple Speech; Doubao ASR as a remote option |
| **Smart Text Processing** | Local MLX models (Qwen3.5 / Qwen3 / Gemma) or a remote LLM infers spoken intent — contextual cleanup, "scratch that" restarts, self-correction handling, spoken punctuation, technical terms, numbers/ranges/units, and structured formatting |
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
| **Language Style Presets** | Casual / Professional / Custom prompt |
| **Input History & Stats** | Full history with raw vs. processed comparison, word count stats, configurable retention |
| **Bilingual UI** | Chinese and English interface, independent of recognition language |
| **Sound Feedback** | Audio cues on recording start and stop |
| **Guided Onboarding** | Step-by-step setup: permissions, model download, and first use |

## System Requirements

- **OS**: macOS 26 (Tahoe) or later
- **Chip**: Apple Silicon (M1 / M2 / M3 / M4)
- **Disk**: ~0.7 GB minimum (Apple Speech + Qwen3.5 0.8B); ~1.8 GB for the default setup (Apple Speech + Qwen3.5 2B); larger speech and text models need several GB more

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
bash scripts/sdlc-checks.sh
bash scripts/ci-basic-checks.sh
swift test
```

The public app is `Utter.app`. The Swift package product remains `OpenType` so existing source integrations and upgrade paths continue to work.

## First Run

1. Launch Utter — it appears as a waveform icon in the menu bar
2. The onboarding wizard guides you through permissions and model setup
3. Grant **Microphone** and **Accessibility** permissions (required)
4. Wait for the default text model (Qwen3.5 2B, ~1.7 GB) to download — one time only
5. Hold **Fn** to start dictating, release to stop and insert text

## Permissions

| Permission | Purpose | Required |
|---|---|---|
| Microphone | Audio capture | Yes |
| Accessibility | Global hotkey, text insertion (clipboard + simulated ⌘V), and reading the focused field for context | Yes |
| Speech Recognition | Apple on-device ASR engine | Only if using Apple Speech |
| Screen Recording | OCR for screen context and Voice Command mode | Optional |
| Network | Model downloads; remote LLM API calls | First run / remote LLM mode |

## Local Models

Everything below runs on your Mac. Download a model once and dictation keeps working with the network off.

| Stage | Models | Notes |
|---|---|---|
| Speech recognition | Qwen3-ASR 1.7B (recommended), Confucius4-R2T2, FireRedASR2-AED, Mega-ASR, WhisperKit (large-v3-turbo … tiny), Apple Speech (on-device) | Qwen3-ASR and Confucius run through native Swift + MLX; FireRed and Mega-ASR through MLX; Apple Speech is forced on-device |
| Text cleanup (LLM) | Qwen3.5 0.8B / **2B (default)** / 9B / 35B-A3B, Qwen3 0.6B–30B-A3B, Qwen2.5, Gemma 4 E2B / E4B, Gemma 3 1B / 4B / 12B | MLX on Apple Silicon; an experimental ANE-LM runtime can run a local Qwen3 model; you can also add your own MLX model |

Remote options are opt-in: Doubao (Volcengine) ASR and the remote LLM providers below send audio or text to that provider.

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

## Project Structure

```
Sources/
├── App/          # Entry point, AppDelegate, AppState, VoicePipeline, AppIcon
├── Audio/        # Microphone capture (AVAudioEngine), sound playback
├── Config/       # AppSettings, ModelCatalog, RemoteModelConfig, Localization
├── Hotkey/       # Global hotkey via CGEvent tap
├── LLM/          # LLMEngine (MLX), RemoteLLMClient (OpenAI/Anthropic)
├── Output/       # Text insertion (clipboard + simulated ⌘V; Accessibility for selection and context)
├── Processing/   # TextProcessor, InputHistory, MemoryStore, personal and industry vocabulary
├── Prompts/      # PromptBuilder, prompt catalogs, style prompt presets
├── Screen/       # Screen OCR (ScreenCaptureKit + Vision)
├── Speech/       # SpeechEngine protocol, WhisperKit, Apple Speech, Doubao ASR, local ASR engines
├── UI/           # SwiftUI: MenuBar, Settings, Onboarding, Overlay, History, Models
└── Resources/    # Localization strings (en/zh-Hans), sounds, app icon
docs/             # Website (GitHub Pages) incl. demo videos, SDLC artifacts, research
marketing/        # Promo video sources, render engine, voice-over scripts
scripts/
├── build-and-run.sh        # Build, sign, and launch a development .app bundle
├── build-app.sh            # Build release .app bundle and .dmg installer
├── ci-basic-checks.sh      # CI guardrails for linked files and resources
├── create-signing-cert.sh  # Generate self-signed code signing certificate
├── evaluate-voice-quality.py # Score ASR / formatting output (CER, terms, numbers, latency)
├── generate-icon.swift     # Generate AppIcon.icns from source PNG
├── render-promo.sh         # Render a promo video from marketing/<promo>/
├── sdlc-checks.sh          # Validate SDLC artifact stages and approvals
├── test-industry-lexicons.sh # Validate vocabulary recall and non-target preservation
├── unit-test-coverage.sh   # Run unit tests with coverage thresholds
└── validate-volc-asr.swift # Validate Volcengine ASR configuration manually
```

## Tech Stack

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — offline Whisper speech recognition
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — local LLM inference on Apple Silicon (Qwen3.5 / Qwen3 / Gemma)
- **SwiftUI + AppKit** — native macOS UI
- **ScreenCaptureKit + Vision** — screen OCR
- **AVAudioEngine** — low-latency microphone capture
- **Apple Speech Framework** — on-device speech recognition
- **Qwen3-ASR / FireRedASR2 / Mega-ASR on MLX** — local speech recognition

## License

[MIT](LICENSE)

---

<div align="center">

Made with care for Apple Silicon

</div>
