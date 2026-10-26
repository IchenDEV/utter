# Native source selection verification, 2026-10-25

The user explicitly permitted opening `/private/tmp/UtterSourceQA.app` in this conversation. All app launches, clicks, menu choices, key presses and screenshots used CUA. No shell-based UI automation was used.

The host loads this worktree's test bundle and production `ModelManagementView` / `OnboardingView`. It uses `UtterSourceQA-t3-8ad22555` and `/private/tmp/utter-domestic-ui-models-t3-8ad22555`. Its lifecycle service cannot load or benchmark models. This verifies the production views and real Catalog download flow inside a fixture, not a packaged Utter application session.

## Observed interactions

1. The first launch exited while loading `libXCTestSwiftSupport.dylib`. Added the installed Xcode Developer/usr/lib run path to the temporary host. The same app then opened successfully. The host also received an ordinary Window menu and two fixture window buttons for navigation.
2. Models initially showed `Hugging Face（官网）`. Opened the native popup and chose `HF-Mirror（国内镜像）`. The visible value and mirror-domain help changed.
3. Switched to Onboarding. Its popup also showed the mirror. Its Download confirmation included the mirror and the isolated storage root. Cancel returned to the idle Download button.
4. Opened the source popup and pressed Up then Return. The source changed to the official site. Models then showed the official site too.
5. Changing the UI language exposed a defect: the new popup retained Chinese option labels while its visible label changed to English. Added `.id(settings.uiLanguage)` to invalidate the native menu on language changes. After recompilation and restart, tested Chinese and English changes again and inspected both open menu items in English.
6. The Skip button sat too near the onboarding divider. Added 12 pt bottom padding. In real 480 x 420 pt content windows, inspected English light, English dark, Chinese light and Chinese dark views after the fix. Source names and help remained visible, and Skip had clear space above the divider.
7. In English onboarding, the mirror Download confirmation displayed `Download source: HF-Mirror (China mirror)`. Confirmed Download. The actual Catalog entered `Downloading model…`, showed a Cancel button and kept the source popup enabled.
8. Clicked Cancel while the Catalog was downloading. The view showed `Download paused. Select Resume to continue from the files already saved.` and Retry.
9. Changed to `Hugging Face (official)` using Up and Return. Retry's confirmation displayed the official source. Confirmed Retry, observed the downloading state again, then cancelled it.
10. Changed back to the mirror in Chinese onboarding. Models displayed that same mirror value. In Models, opened the 0.8B Download confirmation, observed the mirror and isolated directory, then cancelled the confirmation.
11. The accessibility tree identified the new control as a popup button named `下载源` / `Download source`, with its selected value and the two real menu items. Full VoiceOver speech output and Tab-only focus traversal were not tested.
12. Finished the host normally, confirmed it was absent from the running-app inventory, and reopened it. Both Models and Onboarding still showed `HF-Mirror (China mirror)`. No download had started automatically. Clicked Skip and observed Continue become enabled, then finished the host normally.

CUA screenshots and AX snapshots are in this conversation. Static PNGs saved separately are explicitly headless renders, not saved CUA captures.

## Limits

No real transfer was held open while changing its source. Existing request tests cover two repository queries retaining their original source; they do not cover every file and redirect. The interactive attempts were cancelled, so they do not resolve the earlier mirror metadata failures or prove a complete Whisper/MLX download.

The fixture's pre-existing catalog captions and stored error strings can retain the language in which they were constructed. This run verifies the new source control's dynamic localization; it does not establish whole-application language switching behavior.

No packaged-app restart, model inference, permissions, signing, or release result is inferred from these interactions. Test settings and the small QA cache were retained in their named isolated locations.
