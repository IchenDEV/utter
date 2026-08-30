# Intent: Redesign the public website with a terminal-native bilingual theme

**Status:** approved
**Approved-by:** repo owner (interactive design review in chat)
**Approved-date:** 2026-08-31
**Upstream:** —

## Problem

The current landing page (terminal-style single window, English-only static copy) undersells the project: it reads as developer-only, has no Simplified Chinese presentation despite the app's bilingual UI, omits features that now exist (one-key translation, streaming recognition beta, memory/correction learning, Qwen3-ASR, Volc streaming), lists an outdated model catalog, and its install copy (bare `xattr` command) does not match the actual release signing reality.

## Outcome

A visitor to https://utter.idevlab.dev/ sees a page in the app's own visual language (terminal window, monospace, green-on-paper hairline aesthetic), can switch the whole page between English and 简体中文 and between light and dark themes (with system-preference defaults), reads copy that matches the shipped feature set (verified against `ModelCatalog.swift`, `DeviceCapability.swift`, `SpeechEngineProvider.swift`, `AppSettings.swift`, `scripts/build-app.sh`), and gets a correct three-step DMG install flow with an honest Gatekeeper note.

## Scope

- `docs/index.html` — full markup replacement (new design, old SEO head preserved).
- `docs/assets/styles.css` — rewritten for the new design (light + dark tokens).
- `docs/assets/demo.js` — rewritten: language toggle, theme toggle, sticky-nav state, copy button (old transcript demo retired).
- `docs/assets/AppIconLight.png`, `docs/assets/AppIconDark.png` — new copies of the real app icons for the nav brand and theme-aware favicon.

Non-goals: no app (Swift) code changes, no sitemap/robots/CNAME changes, no removal of `docs/assets/demos/` audio or other legacy assets, no new pages.

## Constraints

- Keep all existing SEO structure: canonical URL, Open Graph / Twitter cards, JSON-LD (SoftwareApplication / FAQPage / HowTo), updated to match the new copy.
- Keep the site dependency-free (single CSS + single JS file, no frameworks).
- Respect `prefers-color-scheme` and `prefers-reduced-motion`.
- Prototype lives untracked in `artifacts/website-prototype/` and must not be committed to main.

## Acceptance criteria

1. Page renders the terminal-window design at desktop and mobile widths in both light and dark themes.
2. Language toggle switches all copy EN ↔ 简体中文; choice persists (localStorage) and is reflected in `?lang=`; first visit follows browser language.
3. Theme toggle switches light/dark, persists, follows system preference on first visit, and swaps the nav brand icon and favicon between AppIconLight/AppIconDark.
4. Copy matches shipped reality: 9-model catalog with RAM/disk from `DeviceCapability.swift`, engines WhisperKit / Apple Speech / Qwen3-ASR / Volc, translation + streaming + memory features present.
5. Install section shows the real 3-step DMG flow and a conditional (not mandatory) Gatekeeper command matching `build-app.sh` behavior.
6. All JSON-LD blocks parse and match on-page content; existing meta/OG/canonical preserved.
7. `scripts/sdlc.py validate --worktree`, `scripts/sdlc-checks.sh`, `scripts/ci-basic-checks.sh`, and `swift test` pass.
