# Plan: Terminal-native website redesign

**Status:** approved
**Approved-by:** repo owner (chat instruction to proceed to push & deploy after final review)
**Approved-date:** 2026-08-31
**Upstream:** spec.md

## Work items

1. **Prototype (done, untracked).** Four radically different variants in `artifacts/website-prototype/index.html` behind a `?variant=` switcher; user selected the "Utter native" direction and iterated three rounds (immersive nav, terminal window framing, bilingual, themes, real app icons, copy refresh).
2. **Production CSS** — rewrite `docs/assets/styles.css`: light/dark token sets (`:root` + `[data-theme]` + `prefers-color-scheme` fallback), terminal-window frame, sticky nav, section scaffolding, mock, pipeline/feature rows, model grid, stack pills, privacy, FAQ, install, responsive + reduced-motion blocks.
3. **Production markup** — rewrite `docs/index.html`: keep the existing SEO head (meta, OG/Twitter, canonical, JSON-LD) with JSON-LD updated to match new copy/FAQ; new body per spec.
4. **Production JS** — rewrite `docs/assets/demo.js`: language toggle, theme toggle, sticky-nav sync, copy button; zero dependencies; guarded storage access.
5. **Icons** — copy `Sources/Resources/AppIconLight.png` / `AppIconDark.png` into `docs/assets/`.
6. **SDLC bundle** — this change directory.
7. **Verification** — run the contract checks; screenshot the live page locally (light/dark, EN/中文, mobile width) before and after push; watch the Pages deployment.

## Verification plan

- `bash scripts/sdlc-checks.sh` (the `scripts/sdlc.py` name in AGENTS.md is stale; this is the real gate)
- `bash scripts/sdlc-checks.sh`
- `bash scripts/ci-basic-checks.sh`
- `swift test`
- JSON-LD parse check (python `json.loads` on each `application/ld+json` block)
- Local render screenshots (browser): light+dark, EN+中文, desktop+mobile widths
- Post-push: GitHub Pages workflow run green; site live at https://utter.idevlab.dev/

## Rollback

Single revert of the website commit on `main` restores the previous page; GitHub Pages redeploys on the next `docs/**` push.
