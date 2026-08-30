# Plan — 0001 bootstrap-ai-native-sdlc

**Stage:** Plan
**Status:** approved
**Approved-by:** chenli
**Approved-date:** 2026-08-31
**Upstream:** [spec.md](spec.md)

## Approach

纯文档与脚本变更，不触碰 Swift 代码。

## Tasks

- [x] 建立 `docs/sdlc/README.md` 与 `templates/`
- [x] 新增 `scripts/sdlc-checks.sh` 并接入 `scripts/ci-basic-checks.sh`
- [x] 创建本 change 目录作为首个真实变更
- [x] 更新 AGENTS.md / CLAUDE.md 的流程章节
- [x] 运行全部检查并记录证据到 verification.md

## Authorized scope

`docs/sdlc/`、`docs/AGENTS.md` 相关章节、`CLAUDE.md` 相关章节、`scripts/sdlc-checks.sh`、`scripts/ci-basic-checks.sh`、`.github/workflows/pr.yml`。
