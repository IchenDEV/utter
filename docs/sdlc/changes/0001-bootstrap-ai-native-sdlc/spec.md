# Spec — 0001 bootstrap-ai-native-sdlc

**Stage:** Spec
**Status:** approved
**Approved-by:** chenli
**Approved-date:** 2026-08-31
**Upstream:** [intent.md](intent.md)

## What must be true

1. `docs/sdlc/` 存在流程说明（README.md）与 intent/spec/plan/verification/release/incident 模板。
2. 每个变更目录包含五个阶段 Artifact；`Status` 只允许 draft / pending approval / approved / rejected / blocked。
3. 后一阶段 Artifact 不得先于前一阶段 approved；approved 必须带 `Approved-by` 与 `Approved-date`。
4. 上述规则由 `scripts/sdlc-checks.sh` 确定性检查，并接入 PR CI。
5. AGENTS.md 与 CLAUDE.md 指向 `docs/sdlc/`，声明每阶段需人工批准；`docs/superpowers/` 标注为历史归档。

## Risks

- 模板字段格式被手写改坏 → 由检查脚本拦截并报具体文件。
