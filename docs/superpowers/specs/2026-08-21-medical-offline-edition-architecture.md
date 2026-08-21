# Utter 医疗离线版一期架构

> 状态：一期实现与跨平台施工基线
> 目标平台：Windows 11 x64、Ubuntu 24.04 x86_64；macOS 版本用于先行验证产品流程
> 硬件口径：AVX2、8 GB 内存目标、16 GB 推荐、CPU-first
> 研究依据：[医疗与隔离网行业版研究](./2026-08-21-medical-airgapped-industry-edition-research.md)

## 1. 产品合同

Utter 医疗离线版只提供医疗听写、术语识别、有限格式整理和用户主动触发的翻译。它不提供诊断、用药建议、治疗建议或自动医嘱，也不绕过医院原有 EMR/HIS 的身份、确认、签名和审计流程。

一期固定要求：

- 安装包内置固定 ASR、固定文本整理模型、Tokenizer、医疗词库、许可证和文件哈希；
- 首次启动、识别、整理、日志和故障恢复均不连接公网；
- 不提供模型选择、下载、导入、远程 provider、API key、自定义 prompt、插件、开放 HTTP 接口或 CLI 集成；
- 输出先形成待确认草稿，由医务人员确认后再插入目标系统；
- 数字、剂量、单位、侧别、阴阳性和否定词属于高风险 token，无直接证据时不得增删改；
- 失败时保留或回退到 ASR 原文，不允许静默丢失口述内容。

“全离线”是可测试的网络行为合同，不等于自动满足医疗、个人信息、等保、关基或涉密要求。

## 2. 固定模型栈

### Windows / Linux 发布基线

| 阶段 | 固定运行时 | 固定候选 | 发布前状态 |
|---|---|---|---|
| ASR | `sherpa-onnx` / ONNX Runtime CPU | Qwen3-ASR-0.6B INT8 ONNX | 约 941 MB 静态文件；转换物许可链、医疗准确率与目标 CPU 延迟待实测 |
| 文本整理与翻译 | `llama.cpp` | Qwen3-0.6B GGUF Q8_0 | 许可链清晰；峰值内存、翻译质量与医疗忠实度待实测 |
| 词库 | Utter 只读医疗基础包 | `medical-seed-v1` + 医院签名扩展包 | 种子包已落地；客户词库 schema、签名与审批待实现 |

### macOS 先行验证栈

现有 Swift 应用固定使用 `Qwen3-ASR-0.6B-bf16 + qwen3-asr-mlx 0.1.1` 做语音识别，使用 `Qwen3-0.6B-4bit + MLX-LM` 做文本整理和翻译。ASR 运行时与两套权重都通过离线行业打包脚本注入，不纳入源码仓库。当前 ASR MLX 运行时未实现量化层装载，因此一期 macOS 包不把 4-bit ASR 当作可运行产物。

模型名称相同不代表转换产物可自动再分发。每个平台的转换权重、运行时、Tokenizer、NOTICE 和许可证必须单独归档与审核。

## 3. 核心模块与接口

跨平台版本建立一个深模块 `MedicalDraftEngine`，平台客户端只学习一个处理接口：

```text
process(audioSegment, locale, lexiconSnapshot, documentContext?) -> DraftResult
```

接口不暴露模型路径、量化参数、prompt、采样参数或运行时类型。实现内部依次完成：

1. 校验离线包、版本和签名；
2. VAD 与本地 ASR；
3. 术语证据匹配和确定性规范化；
4. 释放或回收 ASR 工作集；
5. 按用户模式执行短上下文本地格式整理或翻译；
6. 高风险 token 差异检查；
7. 返回草稿、原文、风险标记和可诊断错误。

`DraftResult` 至少包含：

```text
rawTranscript
formattedDraft
warnings[]
protectedTokenDiff
modelBundleVersion
lexiconVersion
fallbackUsed
```

外部接口的关键不变量：

- 不发起网络请求；
- 不直接提交到 EMR/HIS；
- 不返回诊断或治疗建议；
- 高风险检查失败时 `formattedDraft` 回退为安全文本，并明确标记原因；
- 调用方无需理解具体推理运行时。

## 4. 平台适配器

| seam | Windows 11 adapter | Ubuntu 24.04 adapter | macOS 先行 adapter |
|---|---|---|---|
| 音频采集 | WASAPI | PipeWire，必要时 ALSA fallback | AVAudioEngine |
| 全局快捷键 | RegisterHotKey / 低级键盘钩子，按实际组合选择 | X11 与 Wayland 分开实现；Wayland 依桌面门户能力验收 | CGEvent tap |
| 文字插入 | UI Automation / SendInput，剪贴板 fallback | X11 与 Wayland 分开；受限环境只提供确认复制 | Accessibility API，剪贴板 fallback |
| 本地推理 | sherpa-onnx Qwen3-ASR + llama.cpp AVX2 | sherpa-onnx Qwen3-ASR + llama.cpp AVX2 | qwen3-asr-mlx + MLX-LM |
| 安装 | 企业 MSI，签名 EXE 作为备选 | `.deb`，离线仓库包作为备选 | 签名 `.app` / `.dmg` |
| 更新 | 管理员导入签名离线包 | 管理员导入签名离线包 | 管理员导入签名离线包 |

Wayland 不允许把 X11 注入方法直接泛化。每个目标桌面环境与 EMR/HIS 输入控件都要单独记录“直接插入 / 剪贴板确认 / 不支持”。

## 5. 离线安装包

```text
UtterMedical/
  manifest.json
  SHA256SUMS
  LICENSES/
  NOTICE
  runtimes/
    sherpa-onnx-qwen-asr/
    qwen-text/
  models/
    speech/
    formatting/
  lexicons/
    medical-seed-v1.json
  app/
```

`manifest.json` 锁定 edition、平台、架构、最低目标内存、运行时版本、模型 revision、词库版本和每个相对路径。安装、启动和离线更新必须拒绝绝对路径、`..`、未知 edition、缺失文件、哈希不匹配和未受信签名。

第一期不支持用户任意导入模型。医院词库更新是独立的受控数据包：只允许声明式词项，不允许 prompt、脚本、动态库或可执行文件。

## 6. 8 GB 内存策略

8 GB 是发布目标，不是当前已验证承诺。实现必须按串行推理设计：

- batch 固定为 1；
- 录音分段，处理完成后立即释放原始缓冲；
- ASR 完成后回收其工作集，再加载或唤醒 Qwen 文本模型；
- LLM context 首版限制为 2,048 tokens，输出只覆盖短病历段落；
- 文本整理与翻译均禁用 thinking，避免隐藏推理占用和不可控输出；
- 设置进程内存保护，无法安全整理时回退 ASR 原文；
- 不让历史记录无限进入上下文；
- 测试时必须同时运行目标 EMR/浏览器，不能只测空系统。

只有 Windows 11 与 Ubuntu 24.04 的 Intel/AMD 真实 8 GB 机器同时通过峰值内存、连续 100 次、60 秒录音和目标 EMR 输入验收后，才能把“8 GB 支持”写入公开规格。

## 7. 交付阶段

### P0：macOS 产品流程和离线包合同

- 固定模型与离线能力策略；
- 移除模型、远程和开放集成入口；
- 内置医疗种子词库；
- 模型随包复制、结构校验和 SHA-256 清单；
- 医疗草稿人工确认后插入。
- 默认不记录口述历史、不启用跨会话上下文记忆或自动纠错学习；
- 个人词条只允许本机手工维护，未签名的导入导出入口关闭。

### P1：跨平台核心

- 建立独立的 Rust workspace，不把 AppKit 代码条件编译成“跨平台”；
- 实现 `MedicalDraftEngine`、包校验、sherpa-onnx/llama.cpp adapter；
- 实现高风险 token guard、原文回退和不含患者正文的结构化日志；
- 在 CLI 测试壳中跑医疗语料、内存和零外联门禁。

### P2：Windows 客户端

- 完成录音、快捷键、确认草稿、UI Automation/剪贴板插入；
- 验证前三个目标 EMR/HIS；
- 交付签名 MSI、静默安装/卸载和离线更新。

### P3：Ubuntu 客户端

- 分别交付 X11 与选定 Wayland 桌面环境；
- 验证 PipeWire、快捷键和插入权限；
- 交付 `.deb`、离线依赖包与更新回滚。

## 8. 发布门禁

任何平台缺少以下一项都不能称为完成：

- 零公网 DNS/TCP/UDP；
- 安装包内含完整模型、运行时、词库、许可证、NOTICE 和哈希；
- 8 GB 目标机不 OOM、不出现不可接受换页；
- 医疗 CER、术语召回和高风险 token exact match 达到医疗负责人批准阈值；
- 高风险 guard 失败 100% 回退；
- 草稿未经确认不得插入；
- 安装、卸载、离线更新、签名校验和回滚通过；
- 日志不记录完整患者口述正文。

第二行业优先工业制造/能源现场记录；涉密政务、军工和关基项目只有在资质、检测和客户采购边界明确后再进入产品范围。
