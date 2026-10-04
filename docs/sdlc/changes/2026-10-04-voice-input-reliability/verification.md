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
| 原生交付检查 `36b34df` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37219757108)：SwiftUI 标题组件的 private 访问域阻断编译，单元测试未运行 | 已将共享标题组件移至独立文件；修正结果待下一次 CI |
| 原生交付修正 `94972dd` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37220871988)：应用构建通过；1071 tests，18 skips，1 failure | 失败为 Darwin 允许半个 UTF-16 代理对的范围转换；已改为显式边界检查，待下一次 CI 确认 |
| 组合键、采集与取消契约 | Linux 全套 585 tests，0 failures | 覆盖即时启动、1000ms 分类与录音中的晚切换、同一 job/捕获 ID、迟到停止、单调时钟、回调 drain、尾部预算及停止 waiter；新增原生冷准备和设备错误用例待 CI |
| 原生组合键检查 `983d831` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37223097651)：热键入口缺少 Foundation 导入，阻断编译；测试未运行 | 已修正导入；下一检查点确认原生采集、手势及 UTF-16 修正 |
| 翻译语言与交付门槛 | Linux 全套 593 tests，0 failures | 覆盖 0.7/0.2 门槛、非语言内容、目标证明和旧决策读取；系统语言识别及共享会话拒绝写入待 macOS CI |
| 原生翻译检查 `e0bf4d1` | [macOS CI](https://github.com/IchenDEV/utter/actions/runs/37224413746)：应用构建通过；1102 tests，18 skips，4 failures | 系统语言识别、UTF-16 和采集新用例通过；三处撤权结果错归为失败、一处测试未捕获预期失败已修正，待下次 CI |
| 队列前采集、计时和呈现投影 | Linux 全套 603 tests，0 failures | 覆盖首段音频选择、首个停止时间、分段计时、默认无正文记录和交付状态投影；原生模型锁期间采集及读屏错误用例待 CI |
| `ci-basic-checks.sh` | 模块、资源、脚本与 plist 检查通过；在缺少 `PlistBuddy` 时停止 | 完整检查必须在 macOS 运行 |
| 真实模型质量 | 未运行 | 合成语料和宿主已建立，仍需明确的已安装模型 |
| 原生窗口、权限、麦克风与剪贴板 | 未运行 | 按约定由用户本机验证 |

读屏、离线加载、交付事务、手势及入口收敛仍在实施；当前检查点不能作为
全部 F1–F11 修复完成的结论。独立审阅和 verification 批准尚未进行。
