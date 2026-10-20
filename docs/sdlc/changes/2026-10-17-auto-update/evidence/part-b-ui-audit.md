# Part B native interface audit

Recorded 2026-10-21, Asia/Singapore. The changed settings and update-offer
surfaces passed the language/appearance matrix. Keyboard/focus and permission
acceptance remain partial.

The complete 1599-line `/Users/chenli/.codex/ANTI_SLOP.md` was reread before
handoff. Each point was checked for applicability to the changed native
Settings and update interface. The approved product direction uses SwiftUI,
AppKit, system typography and native controls. It takes precedence over the
document's marketing-page examples where those would replace native behavior.

## Applicable checks

| Concern | Evidence and result |
|---|---|
| Real controls and command routing | The app menu Settings command and `Cmd+,` open the owned Settings window. The shortcut also worked after restart. A regression test verifies original command restoration when the host closes. |
| Visible navigation | Automatic styling hid all navigation behind toolbar overflow. Grouped native tabs now show all eight English labels in the 760-point window, with About reachable by one click. |
| Language changes and clipping | English to Chinese originally produced ellipses. Replacing the hosting view exposed all eight complete Chinese labels without reopening. Chinese to English also passed in the live Aqua window. General and About were inspected and the selected General section survived the switch. |
| Text legibility | The update privacy footnote changed from tertiary to secondary foreground. English wrapped into two complete lines and Chinese was fully visible in observed light and dark windows. No numerical contrast measurement is claimed. |
| Text padding and boundaries | The inspected General/About content and privacy text stayed inside the fixed window with visible margins. No glyphs or controls were shaved by a custom clip. A narrower resizable Settings layout does not exist. |
| Alignment and hierarchy | The native tab row, settings sections and small check button use the existing Settings layout. The observed update header, status and control remained aligned. No new comparison cards or independent columns were added. |
| Typography | Existing system fonts and semantic SwiftUI text styles remain. No downloaded display face, tracking treatment, mono labels or gradient-filled text was introduced. Small-text accessibility at larger system text settings remains unverified. |
| Color and material | The correction uses native tab styling and semantic secondary foreground. No custom palette, glow, shadow, gradient, texture, border, blur or glass effect was added. The app follows the existing system appearance. |
| Icons | Existing SF Symbols identify settings sections and update status. No fabricated logo, icon tile, decorative badge or generic illustration was added. Native platform conventions are the product direction. |
| Content visible by default | No entrance animation or opacity gate controls the new content. All observed tab labels and update text were visible immediately after the layout refresh. |
| Motion and hover | No custom motion, hover lift, animated underline, floating object or reveal was added. Native controls retain platform behavior. Reduced-motion behavior was not separately exercised. |
| Working update actions | Actual manual checks produced up-to-date, available and failure states. Consent led to download, extraction and a separate Install and Relaunch action. The updated native app showed the new version. |
| Automatic checks | The actual toggle persisted off across restart. A controlled due check made zero requests for 434.3 seconds while disabled. Enabling made one feed request and displayed availability without downloading an archive. |
| Failure and recovery feedback | Unsigned feed, bad archive signature and tampered archive paths showed native Sparkle errors and left the executable unchanged. One post-host-exit installer interruption left a signed, launchable bundle. |
| Configuration visibility | The separately signed remote-HTTP fixture omitted the Updates section and check action. No dead disabled updater surface was displayed for that configuration. |
| Localization | App strings use the existing localization system. Settings and Sparkle update offers were inspected in all four language/appearance combinations. Sparkle initially stayed English under a Chinese OS preference because the main bundle declared no localizations. CFBundleLocalizations now declares the app's manually handled en/zh-Hans languages. Native Chinese update and install/relaunch text passed after rebuilding. Sparkle follows the process's native language selection, independently of live custom uiLanguage changes. The command regression does not test locale refresh. |
| Keyboard and focus | `Cmd+,` works. `Ctrl+Tab` did not change the selected tab. Complete keyboard navigation and focus restoration after a language change remain pending. No global keyboard-access settings were changed. |
| Permissions and privacy | The microphone request action was clicked; the tool refused UserNotificationCenter access. The owner then deferred permission tests. At exit the microphone showed granted, without the agent clicking a system Allow control. The exact temporary bundle's Microphone grant was reset and a fresh About inspection showed Grant again. No recording was started. Granted-permission retention and real busy restart remain pending. No App Management prompt appeared on the writable fixture path. |
| Light/dark coverage | Settings About and Sparkle update offers have native CUA screenshots in English/Chinese and light/dark. Light mode used a separately signed Aqua-only clone; no global appearance setting changed. Updating that clone replaced its Aqua-only metadata with the normal signed 0.0.57 app, which relaunched in system dark appearance. |
| Lifecycle ownership | Independent source review found no concrete command, observer-lifetime, restoration or locale-refresh ownership issue. The host retains its settings state and window while replacing only content on a language transition. GUI behavior was observed by the parent, not independently repeated by reviewers. |

## Points outside this interface

The document's hero, first-fold, pricing, testimonial, logo-wall, newsletter,
image-card, footer-wordmark, social-proof and landing-page compositions do not
apply to a native settings window. None was added. Its fictional metrics,
customer names, fake product-window props and decorative quotation concerns
were checked against the update text: the rehearsal uses explicit test versions
and literal release notes rather than marketing claims.

The font catalog, licensed display typography, atmospheric backgrounds, custom
silhouettes, full-page depth, photographic seams, image masks, SVG geometry,
grain, aurora, halo and shadow recipes were checked for changes. This correction
introduces none of them. Adding these marketing treatments would conflict with
the approved native Settings direction. Existing system-rendered window chrome
and native selected-tab tint are retained.

React, Tailwind, icon packages and animation libraries are outside the SwiftUI
application. No dependency or handcrafted replacement control was introduced.
The applicable principle is met through the actual native TabView, Toggle,
Button, NSMenuItem, NSWindow and Sparkle UI.

## Remaining acceptance work

The final localization-metadata candidate completed a real 0.0.56 to 0.0.57
download, consent, installation and relaunch. About showed 0.0.57 and deep
strict signature verification passed. The four combinations above cover the
changed Settings/About and update-offer surfaces, not every pre-existing
Settings section or every Sparkle error dialog.

Complete keyboard/focus operation, granted TCC and enabled-login persistence,
real recording-busy restart and protected-path App Management remain pending.
The microphone request was triggered. The native tool refused to access
UserNotificationCenter with "for safety reasons". The owner explicitly declined
further permissions and requested preserving the remaining tests. The temporary
microphone grant observed at exit was revoked and the result verified in the
real About window. The isolated app and servers are stopped, temporary private
keys/keychains are deleted, and signed samples/logs remain. No production-update
acceptance is recorded.
