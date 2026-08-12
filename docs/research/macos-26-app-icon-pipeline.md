# macOS 26 app icon design and delivery

Date: 2026-08-12
Scope: Apple primary sources and the current Utter repository only

## Conclusion

For a native macOS 26 icon, the rounded-rectangle crop, enclosure treatment, and system visual effects should not be baked into the imported foreground artwork. Supply square, unmasked layers to Icon Composer; define the background in Icon Composer; and let Icon Composer and the operating system render the final mask, edge treatment, specular highlights, and shadows.

Apple's current HIG is explicit:

- iOS, iPadOS, and macOS receive square layers, and the system applies the final rounded-corner mask.
- Pre-masking layers harms specular highlights and can make edges jagged.
- The system should handle blur and other effects; source layers generally should not contain baked specular highlights, drop shadows between layers, bevels, blur, or glow.
- Icon Composer is where the background, layer placement, Liquid Glass effects, and appearance variants are defined.

Source: [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/).

Apple's Xcode documentation is even more specific about the handoff from an external design tool: remove blur, shadow, specular, opacity, translucency, background colors, and gradients from the exported artwork; do not export a canvas mask because the system applies it. Import the remaining SVG or PNG layers into Icon Composer, where the background and material properties are configured. The resulting `.icon` file is the app-icon source that Xcode includes, and the system renders the required platforms, appearances, and sizes from it. Source: [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer).

Therefore, for the specific elements in question:

| Element | Modern macOS 26 ownership |
| --- | --- |
| Rounded-rectangle crop | System mask; do not bake it into imported layers |
| Outer enclosure edge/highlight | System and Icon Composer material treatment |
| Outer/system shadow | System treatment; do not add a second raster shadow |
| Inter-layer shadow | Configure intentionally in Icon Composer, not in source PNG/SVG |
| Background color or gradient | Define in Icon Composer; an imported custom background is only needed for artwork Icon Composer cannot express |
| Foreground symbol | Square, unmasked SVG preferred; PNG is acceptable for raster-only artwork |

This matches Apple's production process for its own refreshed icons. Apple says Icon Composer is the tool it used to update its icons, and recommends keeping source artwork flat, opaque, and simple while adding blur, shadow, and specular highlights in Icon Composer. Source: [WWDC25: Create icons with Icon Composer](https://developer.apple.com/videos/play/wwdc2025/361/).

## Why a hand-rendered PNG can look heavier

The system icon is not merely a rounded square with a fixed black drop shadow. It is layered artwork whose material effects adapt to icon size, appearance, platform, system version, and environment. The HIG notes that these system effects can render differently between system versions. A static PNG can only capture one rendering and can then receive an additional system treatment.

Apple specifically advises reducing baked static effects because they can compete with the material recipe. In its macOS compatibility path, the system can mask or extend existing icons into the rounded-rectangle template; for uniquely shaped legacy icons, Apple says the system removes existing drop shadows before scaling the artwork into the new canvas. Source: [WWDC25: Say hello to the new look of app icons](https://developer.apple.com/videos/play/wwdc2025/220/).

This means tuning a hand-authored raster shadow from 24% to 15% addresses only the intensity of the extra static shadow. It does not fix the ownership problem: a fallback raster is still drawing its own enclosure, border, and shadow instead of allowing the native icon pipeline to produce them.

## Flattened and legacy fallback behavior

Layered Icon Composer artwork is the preferred path, but Apple still allows flattened images. The HIG says a flattened image can be provided, while layers provide the most control and receive responsive system effects. WWDC25 says a complex or illustrative icon may still be supplied as individual images and will receive the new system edge treatment, but it cannot offer the same per-layer control as Icon Composer. Sources: [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/) and [WWDC25: Create icons with Icon Composer](https://developer.apple.com/videos/play/wwdc2025/361/).

When a project supports older OS releases, Xcode automatically generates flattened app-icon images from the Icon Composer source at build time. Apple warns that these are a similar-looking fallback, not the preexisting legacy artwork; keeping an exact old icon on older releases requires continuing to use an asset catalog instead. Source: [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer).

For a traditional macOS bundle, `CFBundleIconName` identifies the asset-catalog icon. If that is absent, `CFBundleIconFile` identifies the icon file in the bundle; Apple's older Info.plist reference describes `CFBundleIconFile` as the legacy route and `.icns` as the multi-resolution macOS icon format. Sources: [CFBundleIconFile](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleiconfile) and [Core Foundation Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).

Practical implication: keep a generated `.icns` only as a bundle, Finder/LaunchServices, or older-renderer fallback when the packaging path needs it. Do not treat a manually shadowed `.icns` as the source of truth for the macOS 26 Liquid Glass rendering. The `.icon` file should be the design source, and the fallback should be generated from the same clean artwork rather than independently art-directed with a second enclosure shadow.

## Runtime `NSApp.applicationIconImage`

Apple documents `NSApplication.applicationIconImage` as a way to **temporarily change the icon in the Dock app tile**. The `NSImage` assigned to it is scaled to fit the tile; setting it to `nil` restores the app's original icon. Source: [`NSApplication.applicationIconImage`](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage).

Apple does not document this API as selecting an Icon Composer appearance or preserving a `.icon` file's layers. Consequently, the following is an evidence-based inference rather than an explicit API guarantee: assigning a flattened PNG through `applicationIconImage` replaces the Dock tile's bundle-provided icon with that flat `NSImage`, so it should not be expected to retain Icon Composer's layered, appearance-aware rendering. If there is no genuine need for a temporary Dock icon, leaving `applicationIconImage` unset — or restoring it to `nil` — allows the bundle icon to remain authoritative.

## Current Utter pipeline

The repository already contains a modern Icon Composer source at `Sources/Resources/AppIcon.icon` and compiles it with `actool` in `scripts/build-app.sh`, producing `Assets.car` and `AppIcon.icns`. `Resources/Info.plist` declares both `CFBundleIconName = AppIcon` and the `CFBundleIconFile = AppIcon` fallback. That is broadly the correct packaging shape for a manually assembled SwiftPM app bundle.

Two current paths undermine the native rendering:

1. `scripts/generate-icon.swift` creates the fallback PNG and ICNS by drawing its own inset rounded rectangle, background gradient, border, and outer black shadow. This is a complete static enclosure, not clean artwork for system rendering.
2. `Sources/App/AppIcon.swift` loads `AppIconLight.png` or `AppIconDark.png` and assigns it to `NSApp.applicationIconImage`. `OpenTypeApp.swift` invokes this at launch and on later appearance/window events. Per Apple's documented API behavior, this changes the Dock tile to the raster image; it therefore bypasses the bundle icon for the Dock while the app is running.

There is also a material-level mismatch in `Sources/Resources/AppIcon.icon/icon.json`: the foreground group currently sets `glass` to false, `specular` to false, and shadow opacity to zero. Those settings intentionally suppress the foreground's native material treatment. They may be a valid brand choice, but they do not reproduce the material behavior of Apple's current system icons.

Local inspection on macOS 26.6.1 reinforces the pipeline diagnosis: the `actool`-compiled icon has a clean top edge and a lighting-directed lower shadow, while the hand-rendered PNG has a more uniform halo around the enclosure. This observation is supporting evidence from the current build environment, not a claim that Apple publishes fixed shadow values; Apple's documented system effects are adaptive.

## Recommended direction for Utter

1. Treat `AppIcon.icon` as the single source of truth.
2. Import a clean, square, unmasked microphone foreground; do not include the outer rounded rectangle, border, or outer shadow in that image.
3. Define the icon background with Icon Composer's fill or gradient controls and tune the foreground material there while previewing macOS 26 at several Dock sizes and on light and dark desktop backgrounds.
4. Let `actool` compile the `.icon` source. Retain its generated `AppIcon.icns` as packaging fallback; avoid a separately hand-rendered shadow recipe.
5. Stop assigning flattened PNGs to `NSApp.applicationIconImage` for ordinary system/light/dark following. Reserve that API for an intentional temporary Dock-icon override, and restore the bundle icon with `nil` when the override ends.
6. Verify the built `.app`, not only standalone PNG files: inspect the Dock while the app is running, Finder/Launchpad while it is not, and the default, dark, clear, and tinted appearances supported by macOS.

The key correction is structural, not another shadow-opacity adjustment: the modern system should own the enclosure and its lighting.
