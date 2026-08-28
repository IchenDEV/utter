# Anthropic AI-Native SDLC 原文核验与 Utter 改造蓝图

日期：2026-08-25

范围：Anthropic/Claude 一手资料；Utter 改造前基线 commit `c5ee6a6525aae820329e034e64cbe835f1232712`；面向 macOS 26、Swift 6、SwiftUI/AppKit、Apple Silicon 的工程流程。

不在范围：本报告不证明某个 AI 工具在 Utter 上已经达到自治运行，也不把 Anthropic 的示例配置当成已部署产品。

基线说明：仓库事实均以该 immutable commit 为准，并链接到对应 GitHub permalink；同一工作树内随后发生的 SDLC 实施改动不倒灌进“改造前缺口”。

> 证据标记：**[事实]** 可由一手网页或当前仓库直接复核；**[推断]** 是面向 Utter 的工程判断；**[未确认]** 需要实际运行、组织选择或外部系统状态才能回答。

## 结论

用户提供的原文信息没有标题、日期或作者错误。官方页面标题确为 **The AI-Native SDLC playbook**，日期为 **August 21, 2026**，作者为 **Louis Claxton**；页面归类在 Enterprise AI / Claude Code，并把 Claude Enterprise、Claude Code、Claude Tag 列为相关产品。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

**[事实]** 原文真正提出的是一条受人工关口约束的 Artifact Chain：`intent.md → spec.md → plan.md → diff + tests → PR + review findings → incident record → 新 intent.md`。接受一个 Artifact 可以启动下一段；人继续对所有需要判断的决定负责，提交历史和 PR 历史共同组成审计线索。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

**[推断]** Utter 不应先追求“无人值守自动写代码”，而应先修复 Agent 加速后会放大的四个运行系统缺口：

1. 改造前的新工作缺少统一的 `intent → spec → plan → verification` 关联；
2. 改造前 PR CI 会构建 App，却没有执行 Swift 测试套件；
3. 原生 macOS UI、TCC 权限、模型质量和发布产物没有形成统一的可提交验证证据；
4. 改造前 tag 流程允许在签名或公证条件缺失时继续走向公开 Release，生产关口不够硬。

**[推断]** 推荐的终态不是把所有判断交给 Agent，而是：Agent 可以一直执行到明确的关口，确定性脚本和 CI 负责必须成立的规则，人审核意图、风险和发布授权。第一轮应当手动推进 Artifact；只有当门禁、Eval 和回滚都成熟后，才自动触发下一阶段。

## 一手原文核验

### 元数据与来源性质

- **[事实]** 标题、日期、作者与用户粘贴文一致；带有 `utm_source` 的链接只是跟踪参数，规范链接是 [`https://claude.com/blog/the-ai-native-sdlc-playbook`](https://claude.com/blog/the-ai-native-sdlc-playbook)。
- **[事实]** 原文说，这份指南介绍 Applied AI 团队将 Claude 融入 SDLC 的实践，受到客户工作的启发；结尾进一步说，它汇总了 Applied AI 团队每天为客户执行的许多真实最佳实践。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)
- **[边界]** 这能证明方法来自 Anthropic Applied AI 的客户实践，不能证明六个阶段的每个 Play 已经在 Anthropic 自身或每个客户处完整上线，也不能把文中的预期改进当成公开测量结果。
- **[边界]** “Code is no longer the bottleneck”是文章的核心判断和标题段落，不是一项在文中附带样本、基线与统计方法的行业研究结论。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

### 用户粘贴文中的关键主张

| 主张 | 核验结果 | 精确边界 |
| --- | --- | --- |
| 六阶段为 Plan、Design、Build、Test、Deploy、Maintain | **[事实] 已验证** | 原文称它们是 non-linear stages，不应重新解释成固定瀑布流程。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook) |
| 接受 Artifact 会触发下一阶段 | **[事实] 已验证** | 原文明说：接受 `intent.md` 启动设计，批准 `spec.md` 启动 plan mode，合并 PR 启动 pipeline，生产控制带越界写回新的 `intent.md`；同时建议先人工 prompt，终态才是自动触发。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook) |
| `intent.md` 包含 problem、outcome、users/systems、constraints、open questions | **[事实] 已验证** | 原文给出这些建议字段，并要求 Product Owner 修正 Agent 的理解后才能提交。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook) |
| `CLAUDE.md` 放项目上下文，Skill 放重复执行的组织知识 | **[事实] 已验证** | 官方文档也把 `CLAUDE.md` 定义为项目级共享上下文，把 Skill 定义为带触发描述的可复用知识/工作流。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[Claude Code memory](https://code.claude.com/docs/en/memory)、[Skills](https://code.claude.com/docs/en/skills) |
| Skill 是 advisory，Hook 是 deterministic layer | **[事实] 基本验证，但需收紧** | 原文确实这样表述；当前 Hook 文档还支持 prompt-based 和 agent-based hooks，因此严格的确定性门禁应采用 command/HTTP 规则、权限、sandbox、CI 和 branch protection，而不是泛指所有 Hook。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[Hooks guide](https://code.claude.com/docs/en/hooks-guide)、[Hooks reference](https://code.claude.com/docs/en/hooks) |
| Agent 需要 Build/Test/Screenshot 自反馈，UI 通常迭代两三轮 | **[事实] 已验证** | 原文区分了贯穿任务的 self-feedback loop 与最后在新 Context 中做结论的 verifier subagent。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[Subagents](https://code.claude.com/docs/en/sub-agents) |
| Verifier Agent 是独立产品 | **[事实] 原文不支持此强表述** | 原文提供的是自定义 `.claude/agents/verifier.md` 模式和示例；它不是一项单独列出的内置托管服务。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook) |
| Continuous Evals 从 20–50 个真实任务起步，事故变 Eval | **[事实] 已验证** | 原文给出自建 CI 示例：真实任务 + 接受检查；在 `CLAUDE.md`、Skill、Hook 等配置变化和定时任务上运行；生产事故成为长期回归项。它不是现成托管 Eval 产品。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook) |
| 1σ 记录、2σ 只读诊断、3σ 可动作 | **[事实] 已验证，但需收紧** | 确定性、版本化并有单测的检测脚本负责监视；Claude 越界后才被无状态唤起。3σ 也只能开 PR 进入审核或调用预批准 runbook，不代表自由改生产。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook) |
| OpenTelemetry 就是完整运行历史 / 生产监控 | **[事实] 不成立** | 官方 OTel 文档覆盖 Claude Code 用量、成本、工具活动和审计事件；异常检测、基线、跨 Session 关联与告警由组织自己的后端负责。Artifact、Git/PR、CI 记录仍需各自保存。[Monitoring](https://code.claude.com/docs/en/monitoring-usage) |
| 非工程人员可以从 Claude/Cowork 写入 GitHub | **[事实] 原文支持，但连接器要分清** | 原文建议经版本控制 connector 提交 Markdown。当前 Read & write 的 GitHub MCP connector 可以承担写入；旧 GitHub 内容集成文档描述的是只读文件与分支内容。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[GitHub MCP connector](https://claude.com/connectors/github)、[旧 GitHub integration](https://claude.com/docs/connectors/github) |

### 原文没有证明的扩展判断

- **[推断]** “Anthropic 正在争夺软件公司的工作运行层”“它已经是通用 Personal Harness”是有依据的产品方向解读，但不是原文中的可验证事实。
- **[未确认]** 粘贴文中的 Reddit 团队案例没有给出可核验的一手链接；它不应作为本项目改造的证据或指标基线。
- **[推断]** DeepSeek、Vercel 或其他 Harness 与本 Playbook 指向同一趋势，需要分别研究各家一手资料；不能由这篇 Anthropic 文章单独推出。
- **[事实]** 原文自己的最强治理边界是“Agent 做到生产关口为止，但不能越过关口”，并要求 branch protection、权限分层、sandbox、scoped credentials、人工发布授权和预先演练的 rollback。[原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[Permissions](https://code.claude.com/docs/en/permissions)、[Sandboxing](https://code.claude.com/docs/en/sandboxing)

## Utter 改造前运行系统审计

### 已经具备的基础

- **[事实]** 根目录 [`AGENTS.md`][baseline-agents] 已描述产品、模块、Swift 并发和本地化约定、构建/发布命令以及 Metal、TCC、Screen Recording、Apple Speech 的常见错误。这已经承担了 Playbook 中“新工程师需要知道什么”的大部分项目上下文职责。
- **[事实]** 基线已有分开的设计和实施文档，例如 [`docs/superpowers/specs`][baseline-specs] 与 [`docs/superpowers/plans`][baseline-plans]，说明 `spec` / `plan` Artifact 不是从零开始；但这些历史文件没有统一的 `work_id`、前置 `intent`、风险级别、审批人和最终 evidence 合约。
- **[事实]** [`scripts/ci-basic-checks.sh`][baseline-basic-checks] 已把 Info.plist、entitlements、本地化 key parity、资源、品牌兼容标识、冲突标记和坏 symlink 做成确定性检查；[`scripts/unit-test-coverage.sh`][baseline-unit-coverage] 已能运行 `swift test --enable-code-coverage` 并检查部分核心文件的覆盖率。
- **[事实]** [`scripts/build-app.sh`][baseline-build-app] 通过 `xcodebuild` 生成 arm64 Release App，复制 MLX 资源 bundle、编译 Icon Composer 资源，并签名/组装 DMG；这符合 [`AGENTS.md`][baseline-agents] 记录的“release 不能只用 bare `swift build`，否则 Metal shader 不完整”的项目约束。
- **[事实]** 语音质量已经有机器可读的 JSONL schema 和 CER/WER、术语、静音幻觉、数字/URL/email/path 保真与延迟指标实现，可作为产品 Eval 的起点。[`evaluate-voice-quality.py`][baseline-voice-eval]、[示例 corpus][baseline-voice-corpus]、[现有质量研究][baseline-voice-research]

### 会被 Agent 产出速度放大的缺口

- **[事实]** 基线 PR workflow 只执行 basic linked rules 和 `build-app.sh --app-only --sign=-`，没有调用 `swift test` 或 coverage script。[`.github/workflows/pr.yml`][baseline-pr-workflow]
- **[事实]** `build-and-run.sh --verify` 的验收条件只是打开 App 后等待同名进程出现，最多约 5 秒；它能证明进程存活，不能证明菜单栏、录音、转写、文本插入、TCC 或 UI 状态正确。[`scripts/build-and-run.sh`][baseline-build-run]
- **[事实]** 基线 PR build 生成 ad-hoc signed App 后即结束，没有把 `codesign --verify --deep --strict`、架构、`default.metallib`、关键资源或可启动性作为独立 required check。[`.github/workflows/pr.yml`][baseline-pr-workflow]、[`scripts/build-app.sh`][baseline-build-app]
- **[事实]** 基线 tag release 中，签名证书缺失时会回退到 ad-hoc；公证凭据缺失时跳过 notarize；随后仍可创建并上传公开 GitHub Release。`Verify artifacts` 只运行展示签名信息的 `codesign -dvv`，不是严格签名验证。[`.github/workflows/release.yml`][baseline-release-workflow]
- **[事实]** 基线 entitlements 涉及麦克风、Speech Recognition、Screen Recording、Apple Events Automation、JIT/unsigned executable memory/library validation，并关闭 App Sandbox；这些都是应当提升到高风险审批和真机验证的发布面。[`Resources/OpenType.entitlements`][baseline-entitlements]
- **[事实]** 基线 `.claude/settings.local.json` 只允许 `WebSearch`，没有项目级 Skill、Hook、sandbox 或审批门禁；同时仓库以 `AGENTS.md` 而非 `CLAUDE.md` 为共享 Agent 指令源。[`.claude/settings.local.json`][baseline-claude-settings]、[`AGENTS.md`][baseline-agents]
- **[边界]** 这不表示必须绑定 Claude。Claude 官方文档明确说 Claude Code 读取 `CLAUDE.md` 而不是 `AGENTS.md`，并建议让一个很薄的 `CLAUDE.md` 导入 `AGENTS.md`；Utter 可以继续把 `AGENTS.md` 作为跨 Agent 的唯一项目上下文源，只为特定工具增加适配层。[Claude Code memory: AGENTS.md](https://code.claude.com/docs/en/memory#agentsmd)

## 目标 SDLC：一个 Artifact 驱动、证据驱动、风险分级的循环

```text
Issue / user request / incident
            ↓
       intent.md (draft)
            ↓ Product gate
        spec.md (draft)
            ↓ Product + risk gate
        plan.md (draft)
            ↓ Engineering gate
   isolated implementation worktree
            ↓
 code + tests + verification evidence
            ↓
       PR + agent review
            ↓ Code owner / human risk gate
    signed release candidate
            ↓ Release manager gate
          release
            ↓
 deterministic monitoring / incident
            ↓
 incident.md + new intent.md + new eval
            ↺
```

**[推断]** “全面改造”应当改变状态和责任，而不只是增加文档模板：

- Artifact 是阶段输入、人工审核对象、Agent 执行输入和审计记录；
- CI/脚本根据 Artifact 字段决定必须跑哪些证据；
- Agent 可以创建草稿、实现、修复、复核，但不能批准自己的 Artifact 或生产发布；
- 高风险路径不因测试通过而自动降级；
- 事故同时更新代码、Eval 和项目知识，避免只修一次。

## Artifact 合约

### 新工作包

**[推断]** 新工作统一放在 `docs/sdlc/changes/<work-id>/`，同一目录保存完整语义链，避免在 ticket、聊天和多个文档目录间丢失关联：

```text
docs/sdlc/changes/2026-08-25-native-ui-verification/
├── state.json
├── intent.md
├── spec.md
├── plan.md
├── verification.md
└── incident.md       # 仅事故来源或发布后事故时存在
```

现有 `docs/superpowers/specs/` 和 `docs/superpowers/plans/` 不应批量移动或重写历史；新改动引用旧文件的 commit permalink，旧工作只有在重新进入开发时才补 `work_id` 和新 work package。

### `state.json`

**[推断]** 机器状态集中放在一个 JSON 文件，Markdown 负责可读内容，避免五个 frontmatter 互相漂移：

```json
{
  "schemaVersion": 1,
  "id": "2026-08-25-native-ui-verification",
  "title": "Verify native macOS UI changes",
  "risk": "medium",
  "status": "planned",
  "owners": ["github-handle"],
  "acceptanceCriteria": ["Observable criterion"],
  "artifacts": {
    "intent": "intent.md",
    "spec": "spec.md",
    "plan": "plan.md",
    "verification": "verification.md"
  }
}
```

**[推断]** 状态沿 `intent → designed → planned → implementing → verified → released → closed` 前进。CI 只验证 schema、路径、必需章节、风险对应的 Artifact 和允许的状态转换，不让 LLM 决定内容是否“足够好”。人类 acceptance 仍由 PR review、branch protection 和 protected environment 记录，Agent 不得把修改 JSON 当成人工批准。

### `intent.md`

必须让不读聊天的人理解：

- Problem 与证据；
- Proposed outcome；
- Affected users / systems；
- Constraints 与明确的 out of scope；
- Success metrics；
- Open questions；
- 数据、隐私、TCC、签名、分发影响初筛。

这与 Anthropic 的 proto-spec 字段一致，但增加了 Utter 必需的隐私/TCC/分发影响。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

### `spec.md`

必须回答：

- 用户流程与失败路径；
- 对 `App/Audio/Config/Hotkey/LLM/Output/Processing/Prompts/Screen/Speech/UI` 的影响；
- 状态、并发、数据生命周期和恢复策略；
- 中英文用户可见文案；
- 权限、隐私、网络、模型、签名与升级兼容性；
- 可测试的 acceptance criteria；
- 尚未解决的 concern 及其 policy owner。

### `plan.md`

必须回答：

- 要修改和明确不修改的文件；
- 步骤顺序与每步回滚点；
- 最危险步骤和备选方案；
- 测试、构建、原生 UI、TCC、模型、产物与发布证据矩阵；
- 并行任务的文件所有权；共享文件必须串行；
- 偏离 plan 时如何在同一 PR 内更新并重新审批。

Anthropic 也要求 plan 写明文件、顺序、风险和 proof，并在实现偏离时同步更新。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

### `verification.md`

**[推断]** 这是 Utter 改造前缺少的关键 Artifact。它只能记录实际执行结果，不能写“预计通过”：

- commit SHA、macOS/Xcode/Swift 版本；
- 每个验证命令、exit code、通过/失败/跳过数量；
- skipped integration test 的原因和对应责任人；
- UI 截图或录屏的文件/PR artifact 链接、窗口状态、light/dark、viewport；
- TCC 测试所用签名身份类型和权限状态；
- 模型 ID/revision、语料版本、质量/延迟结果；
- App/DMG hash、架构、签名、公证、staple 和关键资源检查；
- 未验证事项和发布前必须完成的人工检查。

## 风险分级与人工关口

| 级别 | Utter 示例 | 必需 Artifact | Agent 自治边界与人工关口 |
| --- | --- | --- | --- |
| Trivial | 纯文案文档、注释、无行为 copy typo | PR 描述 | 可走快速路径；仓库规则需要时仍由人 review |
| Low | 隔离实现或测试变化，无隐私、安全、数据、发布或 UI 行为影响 | intent、plan、verification | 可在 plan 后实施、自验证、开 PR；至少 maintainer 合并 |
| Medium | 一般功能、设置项、UI、模型/runtime 行为、依赖、自动化 | Low + spec | 可实施并运行完整相关证据；人接受 intent/design 与 PR，不得自行接受视觉或产品语义 |
| High | 权限、隐私、安全边界、签名、release、破坏性迁移、公共 API 兼容 | 完整 bundle + 独立验证 + rollback | 只在隔离 worktree/受限凭据行动；指定 owner、独立 verifier、真机证据和 protected production approval |

**[推断]** 公开发布始终是 High；“所有测试绿”不等于“可发布”。这与 Anthropic 的生产关口原则一致，也适配当前 App 的权限和签名面。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[`OpenType.entitlements`][baseline-entitlements]

## Agent Harness：建议、确定性规则和权限必须分层

### 1. 共享上下文

- `AGENTS.md` 继续是项目唯一事实源：架构、命令、约定、常见错误；删除陈旧或重复内容。
- 如果团队使用 Claude Code，提交一个只导入 `AGENTS.md` 的薄 `CLAUDE.md`；不要复制两份项目规则。[Claude Code memory](https://code.claude.com/docs/en/memory#agentsmd)
- 当同一错误重复出现两次，把短而稳定的纠正写回 `AGENTS.md`；过程型长说明进入 Skill 或脚本，而不是无限增长 always-on context。这个节奏来自 Playbook 的建议，不是自动门禁。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

### 2. 可复用 Skill

**[推断]** 第一批只建立项目特有且反复发生的四类 Skill：

1. `macos-native-ui-review`：真实 App、light/dark、初始/滚动、窄窗口、键盘与 VoiceOver 检查；
2. `tcc-and-signing-change`：麦克风、Speech、Screen Recording、Accessibility/Automation、稳定签名与 clean-user 验证；
3. `speech-quality-eval`：固定 corpus、模型 revision、CER/WER/实体保真/延迟和跳过边界；
4. `release-candidate-audit`：Xcode/Metal、bundle、架构、codesign、notarization、staple、DMG 安装与回滚演练。

Skill 只能提出做法；必须成立的检查由 `scripts/`、CI、branch protection 和环境保护规则执行。Anthropic 官方也把 Skill 定位为按描述触发的文件系统 Artifact，把 Hook/权限/sandbox 用作更强控制。[Skills](https://code.claude.com/docs/en/skills)、[Hooks guide](https://code.claude.com/docs/en/hooks-guide)、[Sandboxing](https://code.claude.com/docs/en/sandboxing)

### 3. 确定性门禁

**[推断]** 项目脚本应当是 Agent 无关的控制层；任何 Claude/Codex Hook 只调用同一脚本：

- 改动 `Resources/Info.plist` 或本地化任一语言时，强制 `ci-basic-checks.sh`；
- 改动 `Package.swift` / `Package.resolved` 时，强制依赖解析、许可证/来源差异和 Xcode app build；
- 改动 `Resources/OpenType.entitlements`、`.github/workflows/**`、`scripts/build-app.sh`、`scripts/create-signing-cert.sh` 时，要求 High 风险 Artifact 和 CODEOWNER；
- 防止凭据、模型权重、DMG、`.p12`、profile、日志和本机绝对路径进入 diff；
- Agent 不能直接 push `main`，不能创建/移动生产 tag，不能读取签名/公证 secret，不能把失败的 sandbox 命令改成无 sandbox 重试。

对 Claude Code，官方权限控制工具调用，sandbox 在 macOS 使用 Seatbelt 约束 Bash 子进程的文件和网络；二者是互补层，仍不能代替 CI 和 GitHub 分支保护。[Permissions](https://code.claude.com/docs/en/permissions)、[Sandboxing](https://code.claude.com/docs/en/sandboxing)

## Build/Test：把“完成”改成可复核证据

### 单一入口与分层验证

**[推断]** 新增一个稳定入口，例如 `scripts/verify-change.sh`，由 Artifact 风险和改动路径选择层级；`AGENTS.md` 写清命令和健康输出：

| 层级 | 触发 | 最低证据 |
| --- | --- | --- |
| Fast | 每次实现循环 | focused XCTest、`ci-basic-checks.sh`、`git diff --check` |
| Full | 所有 PR | `swift test`、basic checks、Xcode app build |
| Native UI | UI/权限/交互改动 | 已签名真实 App；light/dark；相关窗口初始/滚动/窄宽度；交互录屏或截图 |
| Model | ASR/LLM/Prompt/词典改动 | 固定 revision/corpus；质量、保真、延迟；offline/remote 边界；资源占用 |
| Release candidate | tag 前 | 严格 codesign、notarize/staple、bundle/Metal/arch/hash、DMG 安装、clean-user/TCC、rollback rehearsal |

### 立即修复 PR CI 缺口

**[推断]** `.github/workflows/pr.yml` 至少增加：

1. `swift test` required check；
2. 现有 basic linked rules；
3. 现有 Xcode/Metal App build；
4. 独立 artifact validation：`codesign --verify --deep --strict`、arm64、`default.metallib`、`Assets.car`、主 executable/CLI helper、Info.plist 与关键本地化资源；
5. SDLC `state.json` schema、Artifact path/heading、风险与状态 validator；
6. 对 UI/high-risk PR 输出待完成人工证据，而不是把未跑的真机检查伪装为通过。

基线 workflow 已有 2 和 3，缺 1、4、5、6。[`.github/workflows/pr.yml`][baseline-pr-workflow]

### Bug fix 合约

**[推断]** Bug 先变成可失败的回归测试或确定性 reproducer，再实施修复：

1. 在 `plan.md` 记录 reproduction；
2. 单独提交 failing regression test / fixture，并记录 commit；
3. 实现阶段不得修改该测试，除非人工批准并在 Artifact 解释原因；
4. 保存 red → green 命令输出；
5. verifier 在新 Context 只读复查改变行为和最近相邻流程，不负责修复。

这保留 Anthropic 所说的 self-feedback 与 fresh-context verifier 的区别。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

### 原生 macOS UI 证据

**[推断]** 浏览器/component test 不能作为 SwiftUI/AppKit 视觉验收。UI PR 必须对实际 `.app` 验证：

- 目标 macOS 版本与实际显示 scale；
- 系统 light/dark，必要时 high contrast / Reduce Transparency；
- 首次打开和滚动后的状态；
- 窄窗口与长本地化文本；
- menu bar、Settings、Onboarding、Overlay/HUD 的真实交互；
- TCC 未授权、拒绝、授权后、撤销后的状态；
- 截图标注 commit SHA 和构建签名。

基线 `build-and-run.sh --verify` 只能作为“App 进程启动”证据，不应更名解释成产品验证。[`scripts/build-and-run.sh`][baseline-build-run]

## Continuous Evals：分别测试产品和 Agent 配置

### 产品 Eval

**[推断]** 保留并扩展当前 voice-quality evaluator；将公开/合成小 corpus 放 CI，用户授权的真实语料只在受控本地或私有 runner 运行。Prompt、模型、词典、音频处理、streaming 或 cleanup 变化必须与固定基线对比，不能只证明“有输出”。现有 evaluator 已提供第一版 schema 和指标，不需要另起一套格式。[`evaluate-voice-quality.py`][baseline-voice-eval]、[质量研究][baseline-voice-research]

### Agent/Harness Eval

**[推断]** 建立与产品测试分离的 `agent-evals/`：

- 从最近真实 PR / bug / review 中选择 20–50 个已脱敏任务；
- 每项包含 prompt/intent、固定 repo fixture 或 commit、允许工具、接受检查和禁止行为；
- 覆盖本地化双语、Swift concurrency、Prompt/JSON contract、TCC、Metal packaging、release signing、UI evidence、隐私/凭据等项目高风险类别；
- `AGENTS.md`、Skill、Hook/permission、review policy、Agent model/prompt 变化时运行；
- 关键安全/发布 case 必须 100% 通过；其余使用与基线相比不退化的门禁；
- 每次逃逸缺陷或事故在修复后增加永久 case。

20–50 个真实任务、配置变更触发和事故转 Eval 来自 Anthropic 原文；具体目录、类别和门槛是 Utter 的实施建议。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

**[边界]** 不要一开始就在每个 PR 中运行昂贵的完整 Agent Eval。先在 nightly / 配置变更上跑，记录成本、方差和 flaky rate；在重复运行结果稳定后再设 required check。原文也允许某些团队按固定周期离线运行。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

## Review：Agent 做一致性扫描，人判断意图与风险

**[推断]** 新增 review policy，至少分四个 pass：

1. **Spec/plan compliance**：diff 是否解决 accepted intent，是否偏离 plan；
2. **Correctness**：状态、并发、失败恢复、边界、相邻回归；
3. **Privacy/security**：录音、屏幕、选择内容、历史、远程请求、日志、凭据、权限；
4. **macOS/release**：SwiftUI/AppKit 行为、TCC、签名、Metal、bundle、升级兼容。

Agent finding 必须有文件/行号、触发条件、影响和验证方法；style nit 限量。Agent 不批准自己的 PR，branch protection 仍要求 code owner。Anthropic 的 Code Review 也是 findings-only，不自动批准或阻断 PR，并支持 `REVIEW.md` 调整 review 行为。[Code Review](https://code.claude.com/docs/en/code-review)

**[推断]** review 中第二次出现同类 Agent 错误时：短项目事实进入 `AGENTS.md`，可复用过程进入 Skill，必须成立的规则进入脚本/CI。不要把所有 review comment 都堆进 always-on instructions。

## Deploy：硬化生产关口和回滚

### Release candidate 与生产发布分离

**[推断]** tag 不应同时代表“开始构建”和“已获准公开发布”。推荐：

1. 从已通过 required checks 的确定 commit 构建 release candidate；
2. 使用受保护 GitHub Environment，签名/公证 secret 只在该 job 注入；
3. 缺少 Developer ID 签名或完整公证凭据时 hard fail，禁止公开上传 ad-hoc DMG；
4. 严格验证 App 和 DMG，保存 hash、notary log、staple validation 和安装 smoke evidence；
5. release manager 审核 `verification.md` 后授权 publish；
6. Agent 可以生成 release notes、诊断失败、准备命令，不能创建 production tag 或越过 Environment approval。

这直接收紧基线 release workflow 的 optional signing/notarization 行为。[`.github/workflows/release.yml`][baseline-release-workflow] Anthropic 也要求 Agent 只能走到生产关口、生产凭据默认不常驻、rollback 预先演练。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)、[GitHub Actions](https://code.claude.com/docs/en/github-actions)

### 回滚不是一句“可以回退”

**[推断]** 对 GitHub 分发的桌面 App，至少演练并记录：

- 阻止有问题版本继续成为 latest；
- 恢复前一个已知良好 DMG 的可见性和下载链接；
- 对已经安装的用户给出不破坏历史/设置/模型缓存的降级说明；
- 如果将来有 auto-update，验证停止 rollout、channel pin 和 manifest rollback；
- 回滚后创建 `incident.md`、新 `intent.md` 和 Eval。

**[未确认]** 当前仓库快照没有在本报告中验证实际线上 GitHub Environment、branch protection、签名 secret、公证状态或未来 auto-update 服务；这些必须在实施发布门禁时查询实时 GitHub 配置。

## Maintain：先从 CI 和 Release 信号闭环，不拿用户隐私换自动化

**[推断]** Utter 是本地优先的桌面 App，不应为了套用服务器 5xx 示例而默认收集录音、屏幕、转写内容或输入历史。第一阶段只使用已有、低敏感的确定性信号：

- PR/release workflow failure rate 与时长；
- test flaky rate、first-pass CI success；
- release candidate 签名/公证/安装失败；
- 已有 GitHub issue / crash report 的人工分类；
- 在明确 opt-in、数据最小化和隐私设计完成后，才考虑匿名 crash-free sessions、模型延迟或失败率。

### 第一版控制带

```yaml
metric: release_workflow_failure_rate
baseline: rolling_30d
detection: deterministic_versioned_script
tiers:
  1sigma: log
  2sigma: read_only_diagnosis
  3sigma: open_pull_request_or_preapproved_runbook
production_publish: human_only
```

**[推断]** 先把控制带用于 CI/release，而不是 App 用户数据：数据现成、可审计、误动作爆炸半径小。检测脚本必须有单测；Claude 只在越界后读取有限日志；3σ 默认开 PR，只有经过演练的 release rollback 才能成为 runbook。这个权限边界与原文一致。[Anthropic/Claude 原文](https://claude.com/blog/the-ai-native-sdlc-playbook)

**[事实]** Claude Code 的 OTel 可以导出工具活动、权限决定、Hook 事件、用量和成本，但不会替 Utter 自动建立上述产品/发布控制带；检测和告警仍要自己实现。[Monitoring](https://code.claude.com/docs/en/monitoring-usage)

## 分阶段实施顺序

### Phase 0：先冻结真实基线

- 记录当前 required checks、真实 `swift test`、Xcode App build、release artifact、签名/公证和真机 UI/TCC 现状；
- 不把历史报告中的测试数量或发布状态当作当前结果；
- 定义 Trivial/Low/Medium/High path owners 和唯一 production release manager。

退出条件：一份当前 commit 的 baseline `verification.md`，所有 skip/未确认项明确列出。

### Phase 1：Artifact 和 PR 门禁

- 引入 `docs/sdlc/changes/<work-id>/`、`state.json` 与风险分级模板；
- PR template 强制链接 state/intent/spec/plan/verification；
- 增加 state/schema/path/heading/governed-diff validator；
- PR CI 加 `swift test`、严格 App artifact validation；
- 给 entitlements、release workflow、Package 与隐私敏感路径加 CODEOWNER。

退出条件：一个中等风险真实改动从 intent 到 merge 完整跑通；旧 specs/plans 未被破坏。

### Phase 2：验证反馈回路

- 建立单一 `verify-change` 入口和 Fast/Full/UI/Model/Release 层级；
- UI verification evidence 走真实 macOS App；
- 回归 test red → green 合约；
- fresh-context verifier 只读复核；
- release workflow 缺签名/公证即 hard fail，并加入人工 Environment gate。

退出条件：Agent 无需人逐条提醒就能产生可复核 verification evidence，但仍不能批准或发布。

### Phase 3：配置即代码与 Continuous Evals

- 收敛 `AGENTS.md`，按重复问题建立四个 Skill；
- 确定性规则进入脚本/CI，工具适配层只调用它们；
- 收集 20–50 个 Agent Eval；
- 配置变更和 nightly 运行，记录成本、方差、flaky rate；
- review finding 和 incident 形成知识/Skill/门禁/Eval 的分流。

退出条件：改变 Agent 配置时可以用真实任务回答“行为是否退化”。

### Phase 4：有限自动触发和维护闭环

- 先自动化 read-only CI failure triage；
- 再允许 Agent 开修复 PR，不直推 main；
- 建立 CI/release 确定性控制带；
- 演练 rollback 后才把它列为 3σ 预批准 runbook；
- 每次事故生成 `incident.md + intent.md + eval`。

退出条件：无人启动时系统可以发现、诊断并准备修复，但所有风险和发布关口仍由指定人批准。

## 度量与验收

| 目标 | 初始指标 | 数据源 |
| --- | --- | --- |
| Intent 不丢失 | 接受率；首次描述到 accepted intent 的时间；build 后修改 intent 的次数 | Git history / work package |
| Design 提前暴露风险 | plan 后修改 spec 的次数；open concern 在 build 前关闭率 | Artifact commits |
| Agent 自验证有效 | first-pass CI success；人工 review 前已有 verification 的 PR 占比 | CI / PR |
| Review 不被产出淹没 | time to first review；Important finding precision；rework cycles | PR history |
| Harness 不退化 | Agent Eval pass rate、方差、flaky rate、单位任务成本 | eval workflow |
| 产品质量不退化 | CER/WER、实体保真、静音幻觉、p50/p95 latency | voice corpus evaluator |
| 发布可信 | ad-hoc public release 数量必须为 0；RC 到授权时间；rollback rehearsal 新鲜度 | release workflow / verification |
| 事故真正闭环 | 事故到 intent 时间；事故到 permanent eval 时间；同类重复事故 | incident/work package/eval |

**[推断]** 第一阶段的硬验收应设为：所有 PR 跑 Swift tests；所有 Low/Medium/High 改动有风险分级的完整 work package；所有 UI 改动有真实 App 证据；所有公开 Release 都有非 ad-hoc 签名、成功公证与明确人工授权；所有事故都进入 Eval backlog。速度指标只能在这些质量门槛成立后优化。

## 一手资料索引

- [The AI-Native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
- [Claude Code: Project memory / CLAUDE.md / AGENTS.md](https://code.claude.com/docs/en/memory)
- [Claude Code: Skills](https://code.claude.com/docs/en/skills)
- [Claude Code: Hooks guide](https://code.claude.com/docs/en/hooks-guide)
- [Claude Code: Hooks reference](https://code.claude.com/docs/en/hooks)
- [Claude Code: Permissions](https://code.claude.com/docs/en/permissions)
- [Claude Code: Sandboxing](https://code.claude.com/docs/en/sandboxing)
- [Claude Code: Subagents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code: GitHub Actions](https://code.claude.com/docs/en/github-actions)
- [Claude Code: Code Review](https://code.claude.com/docs/en/code-review)
- [Claude Code: Monitoring / OpenTelemetry](https://code.claude.com/docs/en/monitoring-usage)
- [Claude Agent SDK overview](https://platform.claude.com/docs/en/agent-sdk/overview)

[baseline-agents]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/AGENTS.md
[baseline-basic-checks]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/scripts/ci-basic-checks.sh
[baseline-build-app]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/scripts/build-app.sh
[baseline-build-run]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/scripts/build-and-run.sh
[baseline-claude-settings]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/.claude/settings.local.json
[baseline-entitlements]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/Resources/OpenType.entitlements
[baseline-plans]: https://github.com/IchenDEV/utter/tree/c5ee6a6525aae820329e034e64cbe835f1232712/docs/superpowers/plans
[baseline-pr-workflow]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/.github/workflows/pr.yml
[baseline-release-workflow]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/.github/workflows/release.yml
[baseline-specs]: https://github.com/IchenDEV/utter/tree/c5ee6a6525aae820329e034e64cbe835f1232712/docs/superpowers/specs
[baseline-unit-coverage]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/scripts/unit-test-coverage.sh
[baseline-voice-corpus]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/docs/superpowers/specs/voice-quality-corpus.example.jsonl
[baseline-voice-eval]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/scripts/evaluate-voice-quality.py
[baseline-voice-research]: https://github.com/IchenDEV/utter/blob/c5ee6a6525aae820329e034e64cbe835f1232712/docs/superpowers/specs/2026-07-30-voice-quality-research.md
