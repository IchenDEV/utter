# Intent — 0001 bootstrap-ai-native-sdlc

**Stage:** Intent
**Status:** approved
**Approved-by:** chenli（本任务即用户明确提出）
**Approved-date:** 2026-08-31

## Why

项目此前只有 `docs/superpowers/` 下的历史 spec/plan，没有贯穿意图、验收、验证与发布审批的连续流程。需要引入 AI 原生 SDLC，且每个阶段必须显式批准后才能推进。

## Outcome

- 新变更沿 Intent -> Spec -> Plan -> Build -> Verification -> Release 推进，每段有可定位的 Artifact 与审批字段。
- 阶段顺序与审批字段由 CI 确定性检查，而非仅靠说明文字。

## Constraints

- 复用现有 CI（pr.yml + ci-basic-checks.sh），不新建第二套流程。
- 旧文档 `docs/superpowers/` 归档只读，不迁移重写。

## Non-goals

- 不引入部署监控/事故值班系统（本仓库为桌面应用，无生产服务）。
- 不改动业务代码。
