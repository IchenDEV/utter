# Spec: Terminal-native website redesign

**Status:** approved
**Approved-by:** repo owner (interactive design review in chat; four prototype variants reviewed, C selected and refined across three feedback rounds)
**Approved-date:** 2026-08-31
**Upstream:** intent.md

## Design

Static single-page site, zero dependencies, two files (`assets/styles.css`, `assets/demo.js`) plus markup in `index.html`.

### Visual language

- The whole page is framed as a macOS terminal window: canvas background (`#f2f2ee` light / `#101211` dark), window border + traffic lights + `utter — local voice input` title bar.
- Typography is monospace throughout (SF Mono stack); sans-serif is reserved for two deliberate moments: the "polished final text" in the hero mock and FAQ answers — mirroring the verbatim → smart-format contrast of the product.
- Green accent (`#176b2b` light / `#6fce8f` dark), hairline `#d1d3cf`/`#343834` rules, mono command kickers (`$ utter …`), `>_ ` capability rail, `fn` hotkey HUD — all carried over from the app/live-site identity.
- The hero mock is built from the app's real UI language: window chrome, `● 00:07` waveform, verbatim transcript line, smart-format result, Mail/Notes insert targets.
- Headline ends with a blinking green block cursor (CSS `::after`, respects reduced motion).

### Structure (top to bottom)

Hero (headline, CTAs, product mock, HUD, capability rail) → pipeline (5 rows + raw→final transform) → features (10 rows) → models (9-entry catalog grid) → stack (9 pills) → privacy (lead + 3-row checklist) → FAQ (7 items) → install (3 steps + conditional Gatekeeper command + copy button) → closing CTA band → footer.

### Behavior

- **Language toggle** (`#lang-toggle`): swaps `innerHTML` for all `[data-en]` elements from `data-zh`; updates `<html lang>`; persists via `localStorage["utter-lang"]`; shareable via `?lang=`; defaults from query → storage → `navigator.language`.
- **Theme toggle** (`#theme-toggle`): sets `<html data-theme>`; CSS custom-property overrides for dark; `prefers-color-scheme` drives the default; persists via `localStorage["utter-theme"]`; shareable via `?theme=`; swaps nav brand image (AppIconLight/AppIconDark) via CSS.
- **Sticky nav**: `position: sticky`; gains translucent background + hairline (`.scrolled`) after 24px of scroll.
- **Copy button**: writes the Gatekeeper command to the clipboard, flashes localized "copied ✓".

### Fidelity to shipped reality (sources of truth)

| Page claim | Source |
|---|---|
| 9-model catalog, RAM/disk figures | `Sources/Config/DeviceCapability.swift` `knownRequirements` |
| Model names/tiers | `Sources/Config/ModelCatalog.swift` `defaultLLMModels` |
| Engines: WhisperKit / Apple Speech / Qwen3-ASR / Volc | `Sources/Speech/SpeechEngineProvider.swift`, `QwenASRModel.swift` |
| One-key translation, streaming beta, memory/dictionary | `Sources/Config/AppSettings.swift`, `Sources/Prompts/PromptCatalog+Translation.swift` |
| Default hotkey fn; Ctrl/Shift/Option alternatives | `Sources/Config/AppSettings.swift` `HotkeyType` |
| macOS 26+ Apple Silicon | `Package.swift` platforms |
| Install flow, `Utter.app` name, notarization caveats | `scripts/build-app.sh`, `.github/workflows/release.yml` |

## Failure analysis

- JS disabled → all content still renders (server-side default copy is EN; toggles degrade to no-ops).
- `localStorage` unavailable (private mode) → try/catch guards; toggles still work per pageload.
- No layout depends on JS; the old audio demo is retired, so no media-loading failure paths.
- Dark theme tokens are scoped to `[data-theme="dark"]` and a `prefers-color-scheme` fallback; light values are the CSS defaults, so a parse error in one block cannot blank the page.

## Risk

Static marketing site only; no app code, no privacy/security/signing surface changes beyond public copy. Worst-case failure is a cosmetic site regression, reversible by reverting the commit.
