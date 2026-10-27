# Intent: VoiceCursor 调研与 Utter 语音编辑

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** 用户整体授权，根线程转达“都允许”；普通阶段可推进，验收未代签
**Risk:** 后续选区写入、上下文隐私和签名发布按 High lane 审查

## Problem

用户希望选中文字，用语音描述修改，并在原宿主改善原文。桌面已有相关处理能力，但当前选区编辑的预览和原文恢复边界尚未闭合；移动端的原位录音与返回仍受原生产线 T0 闸门约束。

## Outcome and scope

本轮完成官方证据、当前实现和 Apple 平台边界核对，提供一个可审阅的行为建议和后续 workflow。研究结论见 [research](research.md)，来源见 [source evidence](source-evidence.md)。本轮不创建产品 UI，不修改 Swift，不安装/注册/付费，不操作共享 iPad，不提交或发布。

下一候选范围建议先验证 macOS 普通可编辑纯文本选区。移动跨应用原位语音编辑须依赖生产负责人关闭录音、焦点返回和生命周期闸门，不以手动返回替代。

## Acceptance criteria

- 每项竞品事实对应官方来源、获取日期和证据等级；明确未实测。
- 核对新 HEAD、原工作区差异与最近 durable 游标，旧成功证据不能证明新方案。
- 对照桌面和移动能力，并明确失败保护、确认和恢复原文的要求。
- workflow 每阶段有负责人、依赖、产物、可检查验收、状态和 human gate。
- 本轮到原生 startedAt 加 10 分钟前结束，子任务终态核对，无后台遗留。

## Current authorization (supersedes first-round pending decision)

用户整体授权已到达。桌面首闭环与移动目标按 spec/plan/workflow 推进；未声称用户已经审阅尚未生成的设计，实际验证仍为独立闸门。上文“本轮仅研究”属于首轮历史范围。

## Current completion authorization — 2026-10-14

用户直接要求取消旧时间限制、将整体桌面与移动语音编辑完成并提交PR。当前任务范围是实际原生审阅/明确Apply/Cancel/一次原文恢复及各端安全流程，不止首轮研究。原始研究阶段限定保留为历史，不限制已授权本地实现与验证。用户随后确认iPad暂不可用，设备查询/预约/安装/启动暂停，真机验收延后；不将延期标为通过。


## Combined Draft delivery authorization

The user now explicitly requests publication after the exact mobile import and current writer settlement, with failed and pending checks disclosed. Continue fixes on this same Draft PR. This changes delivery order and does not approve verification, merge, release, or legal material.
