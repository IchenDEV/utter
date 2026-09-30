# Verification: Fix FireRedASR2 (小红书) model download completeness

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-09-30
**Upstream:** docs/sdlc/changes/2026-09-30-firered-asr-download-completeness/plan.md
**Risk:** medium — model/runtime behavior

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Regression test on pre-fix list | Fails (bug reproduced) | 3 assertion failures: `["config.json", "tokenizer.json"]` vs expected list; `asrRepoContainsRequiredFiles` returned `true`/`false` incorrectly |
| `swift test --filter testFireRedASRCompletenessMatchesUpstreamManifest` | Pass | `Executed 1 test, with 0 failures` |
| `swift test` | Pass | `Executed 794 tests, with 18 tests skipped and 0 failures` |
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Pass | all checks passed |

Reproduced failure before the fix:

```text
ConfigurationTests.swift:155: XCTAssertEqual failed: ("["config.json", "tokenizer.json"]") is not equal to ("["config.json", "cmvn.json", "dict.txt", "model.safetensors"]")
ConfigurationTests.swift:156: XCTAssertFalse failed
ConfigurationTests.swift:166: XCTAssertTrue failed
```

Upstream manifest cross-checked through the Hugging Face tree API for
`mlx-community/FireRedASR2-AED-mlx`: `.gitattributes`, `cmvn.json`,
`config.json`, `dict.txt`, `model.safetensors`, `train_bpe1000.model`. The
pinned `mlx-audio-swift` 0.1.3 `FireRedASR2Model.fromDirectory` reads
`config.json`, `*.safetensors`, `cmvn.json`, and `dict.txt`.

## Acceptance criteria

- Required list equals `["config.json", "cmvn.json", "dict.txt", "model.safetensors"]` and omits `tokenizer.json` — pass (test assertion).
- `asrRepoContainsRequiredFiles` is `false` before the weights exist and `true`
  with the upstream manifest — pass (test assertions).
- Regression test fails on the previous list and passes on the corrected one —
  pass (pre-fix run failed, post-fix run passed).

## Residual risk

- `Mega-ASR-6bit` still requires only `["config.json", "tokenizer_config.json"]`.
  Both files exist upstream, so its download completes; tightening its list to
  include weights is out of scope for this change and listed here as residual
  risk with owner `chenli`.
- `train_bpe1000.model` is intentionally not required because the Swift runtime
  does not read it.

## Decision

Ready for review. Human approval is recorded separately.
