# Verification: 语音输入可靠性

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

实现进行中，以下是已运行的工程检查；本文件仍为草稿，尚未提交阶段验收。

| 范围 | 结果 | 验证边界 |
| --- | --- | --- |
| 数字、词库、自定义事实检查及评测 schema | Linux Swift 6.2：541 tests，0 failures | 便携模块；原生处理提供者测试待 macOS CI |
| SDLC 与 diff 格式 | `sdlc-checks.sh`、`git diff --check` 通过 | 不证明运行行为 |
| 首批原生检查 `5019f5c` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37215917773)：应用构建通过；1032 tests，18 skips，12 assertions 失败 | 失败来自固定词库数量及旧提示词顺序的用例；正在修正，尚无全绿结论 |
| 回复路由与生成清理 | Linux 全套 546 tests，0 failures | 新原生 OCR 与服务生命周期测试待 CI；HUD 排除尚待桌面入口接线 |
| `ci-basic-checks.sh` | 模块、资源、脚本与 plist 检查通过；在缺少 `PlistBuddy` 时停止 | 完整检查必须在 macOS 运行 |
| 真实模型质量 | 未运行 | 合成语料和宿主已建立，仍需明确的已安装模型 |
| 原生窗口、权限、麦克风与剪贴板 | 未运行 | 按约定由用户本机验证 |

读屏、离线加载、交付事务、手势及入口收敛仍在实施；当前检查点不能作为
全部 F1–F11 修复完成的结论。独立审阅和 verification 批准尚未进行。
