# Verification: 语音输入可靠性

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

实现进行中，以下是已运行的工程检查；本文件仍为草稿，尚未提交阶段验收。

| 范围 | 结果 | 验证边界 |
| --- | --- | --- |
| 数字、词库、自定义事实检查及评测 schema | Linux Swift 6.2：541 tests，0 failures | 便携模块；原生处理提供者已在 `6114cd2` 通过 |
| SDLC 与 diff 格式 | `sdlc-checks.sh`、`git diff --check` 通过 | 不证明运行行为 |
| 首批原生检查 `5019f5c` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37215917773)：应用构建通过；1032 tests，18 skips，12 assertions 失败 | 失败来自固定词库数量及旧提示词顺序的用例；随后在 `6114cd2` 修正并通过 |
| 回复路由与生成清理 | Linux 全套 546 tests，0 failures | 新原生 OCR 与服务生命周期测试待 CI；HUD 排除尚待桌面入口接线 |
| 原生检查 `6114cd2` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37216882852)：1041 tests，18 skips，0 failures；应用构建与 SDLC Gate 通过 | 合成中文/英文邮件 OCR、图像合成、取消及排除窗口身份契约通过；真实多屏 HUD 未验证 |
| 本地模型契约 | Linux 全套 552 tests，0 failures；官方 base、base.en、large-v3 分词器 JSON 均通过资产校验 | 未加载真实 Whisper/Gemma 权重，不证明实际断网识别或 EOS 停止 |
| 原生模型检查 `7599601` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37218159586)：1050 tests，18 skips，0 failures；应用构建与 SDLC Gate 通过 | 本地 tokenizer/EOS 配置、内存建议和拒绝下载契约通过；真实模型冷缓存断网与 EOS 未运行 |
| 交付事务、剪贴板及状态持久化 | Linux 全套 571 tests，0 failures；原生交付适配待 CI | 覆盖慢读取、三秒超时、第三方变化、取消 drain、不重试、范围校验、复制/写入证据、冻结设置及旧历史读取；真实应用确认与 UI 尚未验证 |
| `ci-basic-checks.sh` | 模块、资源、脚本与 plist 检查通过；在缺少 `PlistBuddy` 时停止 | 完整检查必须在 macOS 运行 |
| 真实模型质量 | 未运行 | 合成语料和宿主已建立，仍需明确的已安装模型 |
| 原生窗口、权限、麦克风与剪贴板 | 未运行 | 按约定由用户本机验证 |

读屏、离线加载、交付事务、手势及入口收敛仍在实施；当前检查点不能作为
全部 F1–F11 修复完成的结论。独立审阅和 verification 批准尚未进行。
