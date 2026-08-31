# M5 / macOS 27 上的 Apple Neural Engine 兼容性调查

日期：2026-08-31
范围：Utter 当前 Espresso 后端、Apple 公开的 Core ML / Core AI 路径，以及可直接访问 ANE 的开源项目。这里的“M5”包含本次实际可用的 M5 Max；没有把仅有项目自述、但没有设备和系统版本证据的支持声明当作已验证事实。

> 证据标记：**[事实]** 可由 Apple 文档、上游仓库或本机复现实验直接核对；**[推断]** 是基于这些事实的工程判断；**[未确认]** 仍需针对 Utter 的模型和发布形态验证。

## 结论

**Apple 没有在 M5 或 macOS 27 上彻底封堵 ANE。** 当前证据反而能排除“硬件被关闭”或“普通进程一律无权访问”这两种解释：

- **[事实] 公开路径仍在。** Apple 当前的 [Core ML 文档](https://developer.apple.com/documentation/coreml)仍明确写明会利用 CPU、GPU 和 Neural Engine；[`MLComputeUnits`](https://developer.apple.com/documentation/coreml/mlcomputeunits)仍公开提供 `.all` 和 `.cpuAndNeuralEngine`。macOS 27 新增的 [Core AI](https://developer.apple.com/documentation/coreai)也明确面向 CPU、GPU 和 Neural Engine。
- **[事实] 同一台 M5 Max / macOS 27.0 机器上，私有路径也能工作。** 本次从未修改的 [`maderix/ANE`](https://github.com/maderix/ANE) 源码编译运行了十组 `_ANEInMemoryModel` 程序、RMSNorm、32K classifier、softmax 和 classifier backward，全部成功。随后 [`ANEForge`](https://github.com/sbryngelson/ANEForge) 的另一条私有 `e5rt` 编译/执行路径也在同机跑通卷积、CNN 和 transformer encoder block。
- **[事实] Utter 当前 Espresso 仍失败。** 当前 M5 Max / macOS 27 主机对 Espresso 的 24 组 MIL 组合全部返回 Apple 私有编译器 Code 10，真实 GPT-2 `.esp` 也在 layer 0 attention 失败。详见本仓库的 [验证记录](../sdlc/changes/2026-08-29-espresso-ane/verification.md)。
- **[事实] Code 10 不是“ANE 被封”的专用错误。** [`oMLX` issue #3124](https://github.com/jundot/omlx/issues/3124)记录了一台 M5 Max / macOS 27 主机上 rc2 可编译、rc3 因给 `_ANEInMemoryModel` 调用 `setModelURL:` 而遭 bundle hash 校验 Code 10；维护者随后提交了[修复](https://github.com/jundot/omlx/commit/7d77098ed83d7abcafeeaffaa4de1491820021d7)。

因此，**[推断] Espresso 的失败是其生成的 MIL、权重/bundle 组织或私有运行时调用方式与 M5 Max / macOS 27 校验规则之间的具体不兼容，而不是 Apple 对 ANE 的系统性封锁。** 这也意味着它有修复空间，但不能保证私有 API 下一个系统版本仍稳定。

目前存在能在 M5 上直接调用 ANE 的开源实现，但**没有一个未经修改即可替换 Utter 当前 Swift 后端**。本次因此从 ANE-LM 做了窄 fork，只保留 Qwen3 加载、生成、取消、重置和卸载接口，并在 Utter 中继续保留用户可控的 MLX fallback。

## 先区分两个容易混淆的“神经加速器”

- **Apple Neural Engine（ANE）**：独立的 Neural Engine。Core ML、Core AI，以及本报告中的 Espresso、maderix/ANE、ANEForge 私有路径讨论的是它。
- **M5 GPU core 内的 Neural Accelerator**：属于 GPU/Metal 路径。Apple 的 [M5 Tech Talk](https://developer.apple.com/videos/play/tech-talks/111432/)说明 MLX、llama.cpp、PyTorch 可以通过 Metal 利用这类 GPU 加速器；这不等于它们使用独立 ANE。

**[事实]** Apple 官方 [`ml-explore/mlx`](https://github.com/ml-explore/mlx) README 将当前支持设备写为 CPU 和 GPU，没有 ANE backend。Utter 的 MLX fallback 在 M5 上可用，但它不是“换一种方式调用 ANE”。

## 证据矩阵

| 路径 | API 性质 | 设备 / 系统证据 | 当前结论 |
|---|---|---|---|
| Core ML | Apple 公开 API | Apple 文档持续列出 Neural Engine；FluidAudio 在 M5 Pro / macOS 26.5 做了 100 条 TTS 实测 | 可用，但系统决定每个算子落到 CPU、GPU 还是 ANE |
| Core AI | Apple 公开 API，macOS 27+ | Apple 文档明确跨 CPU、GPU、ANE；macOS 27 release notes 仍在改进大模型 ANE 加载和内存归属 | 是 macOS 27 上自定义现代模型的长期路径 |
| Utter + Espresso | 私有 `_ANEClient` / `_ANEInMemoryModel` | M5 Max / macOS 27，24/24 编译组合及真实 GPT-2 均 Code 10 | 当前不兼容；不能据此推断整个私有 API 被封 |
| maderix/ANE | 私有 `_ANEInMemoryModel` | 本机 M5 Max / macOS 27，十组峰值程序及四个 classifier 测试全部通过 | 直接反证“私有 ANE 已被全面封锁” |
| ANEForge | 私有 `e5rt` | 上游有 M5/M5 Pro + macOS 26.5 数据；本机 M5 Max / macOS 27 CNN/transformer 均通过 | M5 可直接调用 ANE，但项目是 Python 前端和研究运行时 |
| oMLX | 私有 `_ANEInMemoryModel` | issue 报告 M5 Max / macOS 27：rc2 成功，rc3 Code 10；维护者定位到 `setModelURL:` | 证明 Code 10 可由 bundle/staging 细节触发，不是芯片封禁 |
| FluidAudio | 公开 Core ML | M5 Pro/macOS 26.5 与 M5/iPadOS 27 的实际运行和分阶段路由 | ANE 可用；个别 Apple GPU/BNNS/Core ML stage 仍会有 OS 特定 bug |
| ANE-LM | 私有 `_ANEInMemoryModel` | 本机原版真实 Qwen3-0.6B 在 fused QKV Code 10；[`IchenDEV/ANE-LM@033472e`](https://github.com/IchenDEV/ANE-LM/commit/033472ec12ea796fc7ea4f8cefd7ed456f69900b) 已完成 28 层、ANE LM head 和 Utter 产品路径实测 | 已作为精确 revision 集成；仍是实验性私有 API，只确认当前 M5 Max/macOS 27 + Qwen3-0.6B |
| ane-infer | 私有 API | README 声称 M1–M5；本次未做当前主机的真实模型复测 | 可作 Rust 混合运行时参考，不能当作已验证的 drop-in |

## 公开 API 没有被撤掉

### Core ML：macOS 26 及更早兼容面的公开选择

**[事实]** Apple 在 [WWDC25 的机器学习框架总览](https://developer.apple.com/videos/play/wwdc2025/360/?time=675)明确说明，Core ML 会在运行时跨 CPU、GPU、Neural Engine 优化执行。`MLComputeUnits.cpuAndNeuralEngine` 允许 CPU 与 ANE、排除 GPU；`.all` 允许系统选择全部可用计算单元。

边界也很明确：

- **[事实]** 公开枚举没有 `neuralEngineOnly`。应用能限制允许的设备集合，不能要求整个模型或每个 op 必须落到 ANE。
- **[事实]** Apple 公开了 `MLComputePlan` 和 `MLNeuralEngineComputeDevice`，可以检查预期的逐 op 设备使用，但模型能否编译、如何分区仍由系统决定。
- **[事实]** Apple 自己的 [`coremltools` issue #2687](https://github.com/apple/coremltools/issues/2687)包含 M5 上某些 shape 的 `mish/softplus` 实际路由到 ANE 的报告，同时也显示路由规则和数值边界会随芯片变化。这是“ANE 在工作”与“不是每个图都稳定”的同时证据。

### Core AI：macOS 27 的前向路径

**[事实]** [Core AI](https://developer.apple.com/documentation/coreai)从 macOS 27 起可用，Apple 将其定位为运行最新模型架构和推理技术的框架，并明确写明会使用 CPU、GPU 和 Neural Engine。Apple 同时提供 [`coreai-models`](https://github.com/apple/coreai-models) 和模型准备工具，不再要求开发者依赖私有 ANE ABI 才能运行现代模型。

**[事实]** [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)提到大模型在 Neural Engine 上的加载改进、ANE 内存归属到应用进程，以及后台 ANE 推理的新 entitlement。它描述的是受支持框架的资源管理和后台限制，不是前台应用被禁止访问 ANE。该 release note 仍是 beta 文档，且其中一条写作 iOS 27，因此不能把每项限制无差别外推到 macOS 前台运行。

### 公开路径的真实开源项目证据

**[事实]** [`FluidAudio` issue #667](https://github.com/FluidInference/FluidAudio/issues/667)和已合并的 [PR #671](https://github.com/FluidInference/FluidAudio/pull/671)在 M5 Pro / macOS 26.5 上把大部分 Kokoro 阶段固定为 `.cpuAndNeuralEngine`，100 条英文、中文语料均完成；只是把 ANE 不接受或 Apple framework 有 bug 的 tail stage 路由到 GPU。

**[事实]** 已合并的 [FluidAudio PR #849](https://github.com/FluidInference/FluidAudio/pull/849)又针对 M5 iPad Pro / OS 27 把有 MPSGraph 问题的 noise/tail 路由到 CPU，RNN 和 vocoder 继续使用 `.cpuAndNeuralEngine`。这说明 OS 27 上需要逐 stage 规避 bug，但不是 ANE 整体不可用。

## 私有 API：同机实测排除了全面封锁

### Utter 当前 Espresso 的失败边界

**[事实]** 当前分支已在 M5 Max / macOS 27 上验证：

- Espresso 0.9.0 和当时 upstream main 的真实 GPT-2 generation 均在 layer 0 attention 返回 `verifyBundleAtPath: invalid model`、Code 10。
- iOS 18、iOS 19、macOS 26、macOS 27 四个 MIL target，乘 LayerNorm/RMSNorm、spatial 64/128/256，共 24 组全部失败。
- 同一请求切换到 MLX 后可以完成，因此失败在 Espresso 私有 ANE 编译/加载路径，而不是 Utter 的通用文本处理流水线。

上游 [`Espresso` README](https://github.com/christopherkarani/Espresso)只把 M1–M4 列为已测试，未列 M5。另一方面，[Espresso issue #18](https://github.com/christopherkarani/Espresso/issues/18)显示 M1 Ultra / macOS 26 的真实模型问题后来通过保持 `ios18` target 得到解决，说明“某个系统上的 Code 10/compile failure”需要按 MIL 和调用细节诊断，不能直接归因为 Apple 封锁。

### maderix/ANE：同一私有类、同一主机成功

本次在 Apple M5 Max、macOS 27.0（26A5421a）上检出 [`maderix/ANE` commit `d91c984`](https://github.com/maderix/ANE/commit/d91c9845c0784dec7753048954fc6d0e8411fe29)，未修改源码：

- **[事实]** [`inmem_peak.m`](https://github.com/maderix/ANE/blob/main/inmem_peak.m) 的十组 programmatic MIL 均完成 compile、load 和 eval；两次观察到的峰值约为 12.6–12.8 TFLOPS。
- **[事实]** [`training/test_classifier.m`](https://github.com/maderix/ANE/blob/main/training/test_classifier.m) 完成四次 ANE 编译：RMSNorm 最大误差 `0.002856`；32K classifier projection 最大误差 `0.000831`；32K softmax 最大误差约 `0.000001`；classifier backward 最大误差 `0.006952`，全部判定通过。
- **[事实]** 这些程序与 Utter 的 Espresso 一样使用 `_ANEInMemoryModelDescriptor`、`_ANEInMemoryModel`、`compileWithQoS`、`loadWithQoS` 和 IOSurface，而不是 Core ML 的公开模型 API。

这组结果直接证明，同一台机器上的 `_ANEInMemoryModel` 编译、加载和执行能力仍开放给普通进程。差异落在具体图、权重、bundle 或调用参数，而不是 API 类完全消失或权限被统一拒绝。

### ANEForge：另一条私有编译/执行栈也成功

**[事实]** [`ANEForge` README](https://github.com/sbryngelson/ANEForge)自述已在 M5 Pro 与 M1 Max 验证；其仓库还保存了 [M5 Pro / macOS 26.5.1](https://github.com/sbryngelson/ANEForge/blob/main/bench/results/rooflines/roofline-apple-m5-pro-Mac17_8-c38210cfc8ea-a154b89e.json)及 [M5 / macOS 26.5.2](https://github.com/sbryngelson/ANEForge/blob/main/bench/results/rooflines/roofline-apple-m5-Mac17_3-019d3ac27339-426ca052.json) 的可机器读取实测数据。

本次又在同一台 M5 Max / macOS 27.0 主机上，以未修改的 `ANEForge` commit `a0be5b5` 运行：

- 最小 1×1 conv 完成编译和执行，输出 shape `(1, 1, 4, 4)`、sum `16.0`。
- 上游 [`examples/quickstart.py`](https://github.com/sbryngelson/ANEForge/blob/main/examples/quickstart.py) 的 CNN 在 fp16/int8 下相对误差为 `0.0023/0.0112`，均通过。
- 同一 quickstart 的 RMSNorm + attention + FFN transformer encoder block 在 fp16/int8 下相对误差为 `0.0029/0.0087`，均通过。

ANEForge 的 [`ane_e5rt_dispatch.mm`](https://github.com/sbryngelson/ANEForge/blob/main/aneforge/_lib/ane_e5rt_dispatch.mm)使用私有 `e5rt_e5_compiler_*` 与 execution stream 符号。这是与 Espresso `_ANEClient` 路径不同的第二个直接 ANE 反例。

但它不是 Utter 的直接依赖候选：其图构建、lowering 和模型前端以 Python 为主，而且首次运行会本地编译 dylib。Utter 若复用，只适合把已验证的窄 C ABI / MIL 生成模式移植进构建期产物，不能在已签名应用内照搬运行时 Python 与动态编译流程。

### oMLX：Code 10 的具体回归样本

**[事实]** [`oMLX issue #3124`](https://github.com/jundot/omlx/issues/3124)提供了很有辨识度的矩阵：

- M5 Max / macOS 27 上 rc2 的 ANE procedure path 成功，rc3 在所有 split size 上 Code 10。
- M5 Pro / macOS 26.6.2 上同一 rc3 可以成功。
- M4 Max 和 M1 Ultra / macOS 27 也能复现 rc3，故失败不跟 M5 芯片本身绑定。
- 维护者定位到 rc3 给 `_ANEInMemoryModel` 调用 `setModelURL:`，触发 macOS 27 的 per-file bundle hash 校验；[commit `7d77098`](https://github.com/jundot/omlx/commit/7d77098ed83d7abcafeeaffaa4de1491820021d7)移除了该覆盖。

修复已在 macOS 26.5 验证，但 issue 中尚没有原 macOS 27 报告者的最终回测。因此“修复方向”有源码证据，“已在 macOS 27 完全收口”仍属**[未确认]**。

### ANE-LM：原版失败，但最小差分 PoC 跑通真实 Qwen

本次又在同一台 M5 Max / macOS 27.0 主机上检出 [`ANE-LM` commit
`04b1af1`](https://github.com/johnmai-dev/ANE-LM/commit/04b1af12aa30b3f280f511d286398469764b4326)，
使用官方 Qwen3-0.6B safetensors 做了端到端对照：

- **[事实] 未修改上游版本失败。** 原版可以编译并加载约 1.5 GB、28 层的模型权重，但在 layer 0
  的 `first_proj` 立即返回 `verifyBundleAtPath: invalid model` / Code 10；关闭 ANE compile
  cache、将提示缩到一个 token 后仍稳定复现。
- **[事实] 失败缩到了 fused-QKV 图。** 同机运行 maderix/ANE 原版
  `test_fused_qkv` 时，“三卷积 + concat”同样 Code 10，而三个独立 Q、K、V 卷积全部编译成功。
  这排除了 Qwen 权重、投影本身和 M5 权限，指向 macOS 27 私有编译器对该融合图的拒绝。
- **[事实] 全拆 kernel 可以越过 Code 10，但会在约 126 个程序附近触发 Code 54
  `no ANE resources`。** 因此把每个投影永久拆成独立 model 不是可用方案。
- **[事实] 临时差分 PoC 最终跑通。** PoC 将 MIL 更新为本机可接受的
  `program(1.3) / ios18` 形式，并在生成 MIL 前按输出通道拼接 Q/K/V 权重，让一个单输出
  convolution 自然产生连续的 Q、K、V 三段；Gate/Up 同样预拼成一个 convolution，激活和逐元素乘法
  留在 CPU，Down 保持独立 ANE projection。这样每层保持四个 ANE program，共 112 个 layer
  kernel；151,936 词表的 LM head 再分成 10 个 ANE chunk。
- **[事实] 完整中文生成成功。** 27 个提示 token 约为 `21.621 token/s`，22 个生成 token
  约为 `22.597 token/s`，模型初始化约 `6.16 s`。实际输出为：
  “苹果神经引擎（Apple Neural Engine）支持本地语言模型的运行，但需要通过特定的方式实现。”
- **[事实] 短内存循环未出现大幅逐轮增长。** 五轮同进程聊天在第一轮后的 RSS 为
  `1,309,760 KB`，随后为 `1,309,872`、`1,309,968`、`1,310,048`、
  `1,310,144 KB`，四轮累计约 `384 KB`。这只排除了明显的每轮大块泄漏，不能替代
  20–100 轮、取消、卸载和空闲回落验证。

随后已将 PoC 收敛进 [`IchenDEV/ANE-LM`](https://github.com/IchenDEV/ANE-LM) 的 SwiftPM C++ library：

- **[事实]** Utter 固定到不可变 revision `033472ec12ea796fc7ea4f8cefd7ed456f69900b`，不跟随移动分支；Swift 负责 tokenizer/chat template，C ABI 只暴露验证、加载、生成、重置和卸载。
- **[事实]** 模型保存前会解析 safetensors 头，校验全部 Qwen3 必需 tensor、shape 和 BF16 dtype；原生编译入口也拒绝空权重指针，避免坏目录绕过错误回退直接崩溃。
- **[事实]** 部分 ANE kernel 初始化失败会统一 unload 私有 model、释放已创建的 IOSurface、数组和 Objective-C 对象，并删除临时目录。
- **[事实]** Utter 产品路径完成了三次完整加载、生成和卸载，在三轮中共执行 20 次短生成，并在第三轮另行验证了一次取消；每轮生成期间的 RSS 增量分别为 `80 KB`、`32 KB` 和 `0 KB`。fork 将大块临时权重与 embedding 改为可精确 `munmap` 的映射分配后，每轮 unload 相对当轮峰值都释放超过 `512 MiB`。
- **[事实]** 三次 unload 后采样到的 RSS 低点分别为 `636,512 KB`、`150,928 KB` 和 `662,592 KB`，最终低点仅比第一次高 `26,080 KB`，低于测试强制的 `128 MiB` 跨生命周期上限。该结果没有出现随请求或切换次数单调累积的大块泄漏，但卸载后的 RSS 也没有稳定回到加载前 `54,368 KB` 基线。
- **[推断]** `vmmap` 和独立 1 GiB malloc 探针说明系统分配器的回收时机会造成一部分波动；现有测试尚未完全隔离 Apple framework 或私有 ANE runtime 是否也保留了内存，因此不能把全部残留确定归因于 allocator。Utter 在 ANE 选项旁只披露“切换后已释放内存可能不会立即从系统监视器中消失”，没有承诺立即回到基线。

这把“能不能修”从临时 PoC 升级为当前项目可选择的实验后端，但没有改变私有 API 的发布和跨版本风险。

## 其他开源项目能否直接替代

### 能证明 M5 可直连，但不能原样嵌入 Utter

- [`maderix/ANE`](https://github.com/maderix/ANE)：本机已验证 private ANE 可用；它是研究样例和训练 PoC，不是通用 Swift 模型运行时。
- [`ANEForge`](https://github.com/sbryngelson/ANEForge)：本机已验证 M5 Max / macOS 27；模型覆盖很广，但当前产品形态是 Python frontend + Objective-C++ bridge。
- [`oMLX`](https://github.com/jundot/omlx)：已有 M5 Max / macOS 27 rc2 成功证据，并给出 Code 10 的修复线索；它不是 Swift Package，也不是 Utter `.esp` bundle 的替代格式。
- [`ANE-LM`](https://github.com/johnmai-dev/ANE-LM)：原生 C++、MIT。原版 fused-QKV 在当前主机失败；本次的 [`IchenDEV fork`](https://github.com/IchenDEV/ANE-LM) 已整理出 Swift/C ABI 并完成 Qwen3-0.6B 生命周期验证。Qwen3.5 的上游代码没有接入本次 Swift product，因此不能宣称当前 Utter 支持。
- [`ane-infer`](https://github.com/thebasedcapital/ane-infer)：Rust + Objective-C + Metal 的 Qwen3.5 专用混合引擎，README 声称覆盖 M1–M5；同样缺少本次当前主机的真实模型复测，而且不是通用 Swift 库。

[`hollance/neural-engine`](https://github.com/hollance/neural-engine)主要是 ANE 架构与设备资料，不是运行时，不能当作替代实现。

### App Store 与长期稳定性边界没有改变

上述直接 ANE 项目都调用未公开 framework 或符号。即使当前 M5 能运行，它们仍没有 ABI 稳定承诺，也不适合 App Store 发布。Espresso 的 README 同样明确说明私有 ANE API 会触发 App Store 拒绝。公开 Core ML / Core AI 才是可发布、可获得系统兼容承诺的路径。

## Utter 的最小可行技术路径

### 已实施的实验路径：ANE-LM + 用户可控 fallback

Utter 现在允许用户选择普通本地 Qwen3 Hugging Face 目录，由修改后的 ANE-LM 在当前 M5 主机执行；默认允许失败后切换 MLX，用户可关闭。这样不会把私有 API 的一次系统回归变成语音输入不可用，同时保留错误可见性。

### 本次私有修复的边界

实现只承诺 Qwen3 safetensors 和本次实测的 Qwen3-0.6B。它没有证明 Qwen3.5、其他尺寸、M1–M4、普通 M5/M5 Pro、macOS 26 或后续 macOS 版本可用；这些组合仍需逐项做真实生成、取消、重复内存和卸载验证。即使验证通过，这条私有路径仍只适合实验、自签名或侧载版本。

### 受支持的长期路径

- **macOS 27+：优先 Core AI PoC。** 先转换一个 Utter 实际使用的小型 Qwen 模型，验证 state/KV cache、逐 token decode、内存、首 token 延迟和设备 placement。Apple 已把现代模型架构指向 Core AI，它比新写一套私有 ANE runtime 更可持续。
- **若必须覆盖 macOS 26 的 ANE：再做 Core ML PoC。** 需要把 decoder prefill/decode、KV cache 和 tokenizer/采样拆开；用 `MLComputePlan` 验证真实 placement，而不是只因设置 `.cpuAndNeuralEngine` 就宣称全模型在 ANE。
- **MLX 保持稳定底座。** 它走 CPU/GPU，不是 ANE，但当前模型资产、Swift 集成和产品稳定性已经得到验证，适合作为所有系统版本的 fallback。

最合理的双轨是：**短期把当前 ANE-LM fork 限定为可选择的实验后端；长期在 macOS 27 上用 Core AI 建立公开、可发布的 ANE 路径。** 不应把“Qwen3-0.6B 在一台 M5 Max 能运行”包装成跨设备、跨系统兼容承诺。

## 来源清单

### Apple

- [Core ML documentation](https://developer.apple.com/documentation/coreml)
- [MLComputeUnits](https://developer.apple.com/documentation/coreml/mlcomputeunits)
- [WWDC25: Discover machine learning & AI frameworks on Apple platforms](https://developer.apple.com/videos/play/wwdc2025/360/?time=675)
- [Core AI documentation](https://developer.apple.com/documentation/coreai)
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [WWDC26: Meet Core AI](https://developer.apple.com/videos/play/wwdc2026/324/)
- [Apple coreai-models](https://github.com/apple/coreai-models)

### 开源项目官方仓库

- [christopherkarani/Espresso](https://github.com/christopherkarani/Espresso)；[macOS 26 issue #18](https://github.com/christopherkarani/Espresso/issues/18)
- [maderix/ANE](https://github.com/maderix/ANE)；[`inmem_peak.m`](https://github.com/maderix/ANE/blob/main/inmem_peak.m)；[`test_classifier.m`](https://github.com/maderix/ANE/blob/main/training/test_classifier.m)
- [sbryngelson/ANEForge](https://github.com/sbryngelson/ANEForge)；[`e5rt` bridge](https://github.com/sbryngelson/ANEForge/blob/main/aneforge/_lib/ane_e5rt_dispatch.mm)；[`quickstart.py`](https://github.com/sbryngelson/ANEForge/blob/main/examples/quickstart.py)
- [jundot/oMLX issue #3124](https://github.com/jundot/omlx/issues/3124)；[修复 commit](https://github.com/jundot/omlx/commit/7d77098ed83d7abcafeeaffaa4de1491820021d7)
- [FluidInference/FluidAudio issue #667](https://github.com/FluidInference/FluidAudio/issues/667)；[PR #671](https://github.com/FluidInference/FluidAudio/pull/671)；[PR #849](https://github.com/FluidInference/FluidAudio/pull/849)
- [apple/coremltools issue #2687](https://github.com/apple/coremltools/issues/2687)
- [ml-explore/mlx](https://github.com/ml-explore/mlx)
- [johnmai-dev/ANE-LM](https://github.com/johnmai-dev/ANE-LM)
- [IchenDEV/ANE-LM fork](https://github.com/IchenDEV/ANE-LM)；[Utter 固定 revision `033472e`](https://github.com/IchenDEV/ANE-LM/commit/033472ec12ea796fc7ea4f8cefd7ed456f69900b)
- [thebasedcapital/ane-infer](https://github.com/thebasedcapital/ane-infer)
