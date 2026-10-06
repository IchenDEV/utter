# Utter iPhone and iPad development

Requires Xcode 27 and the iOS 27 Simulator runtime. The native app, keyboard and Live Activity link the root Swift package; `Package.resolved` remains the dependency authority.

The product targets iPhone and iPad natively (device families 1 and 2). Compact windows use Voice / Models / Settings tabs; regular-width iPad windows use a sidebar. Settings include recognition language, recording limit, sensitivity, industry vocabulary, personal dictionary, shared keyboard haptics and key sounds. The dictionary and model library do not require microphone permission. Haptics need hardware support; a simulator or iPad cannot establish the tactile experience on iPhone.

The Models page uses the desktop model catalog and download/validation services. Whisper tiny, base and small are the compact choices; download, progress, cancellation, retry, selection and deletion use real local assets. Qwen and Confucius variants come from the shared registry and are explicitly marked experimental on mobile. Selecting or deleting the active model disables the current voice session first. No download starts merely by opening the app.

**The keyboard recording feasibility gate is blocked.** On the tested Air simulator, both a plain native Intent button and the prepared command button execute inside the keyboard extension, despite `.main` metadata. They do not dispatch capture to the app. Release therefore does not offer keyboard recording; Debug keeps the failing path for reproduction. Main-app synthetic tests and bridge file checks pass independently of this gate.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/build-ios.sh --simulator
bash scripts/build-ios.sh --simulator Release
xcrun simctl install SIMULATOR_UUID .build-ios/simulator/Build/Products/Debug-iphonesimulator/Utter.app
xcrun simctl launch SIMULATOR_UUID com.ichendev.utter.ios
bash scripts/check-ios-bridge.sh
```

The simulator build uses the standard local simulator signing identity to preserve App Group entitlements. It needs no developer team or certificate. `--device` builds against iPhoneOS with signing disabled; it does not install on a phone. No signing failure falls back to another identity.

In the simulator, add Utter in Settings → General → Keyboard → Keyboards. Full Access is required for the App Group bridge; without it, Delete, Space, Return and keyboard switching remain available. Only fixed test text should be used during diagnostic checks.

For main-app E2E without speech assets, launch the **Debug** app with `--bridge-diagnostic`, then select the explicitly marked diagnostic action. This mounts the real shared Session workflow with synthetic input and no microphone.

For keyboard transport E2E, add `--simulator-bridge-host`:

```sh
xcrun simctl launch SIMULATOR_UUID com.ichendev.utter.ios --bridge-diagnostic --simulator-bridge-host
```

This explicit simulator-only host reads real App Group commands while the app is foregrounded, for at most 600 seconds and 128 commands. Keyboard leases, Session execution, dictionary preparation, result consumption and native text insertion remain real. It bypasses system Intent dispatch, so it does not verify background wake-up, recognition, microphone shutdown or PiP coexistence. The host and delayed-cancel fault injection are excluded from device and Release builds. Synthetic activation is excluded from Release. `testSimulatorDelayedCancelDoesNotStopNextSession` adds `--simulator-delayed-cancel` to reproduce a late command from an earlier recording; normal simulator use does not need that flag.

Run the independently verified transport and Live Activity flows explicitly:

```sh
bash scripts/test-ios.sh SIMULATOR_UUID \
  -only-testing:UtterSimulatorFlow/UtterSimulatorFlow/testSimulatorKeyboardTransportAndEditing \
  -only-testing:UtterSimulatorFlow/UtterSimulatorFlow/testLiveActivityStopAndCancel
```

These tests enable synthetic input themselves. They exercise real keyboard insertion and Springboard Live Activity Stop/Cancel, not speech recognition or keyboard background wake-up. The app reuses the existing native Utter icon asset.

The full suite currently fails. Reproduce the native wake gate with `-only-testing:UtterSimulatorFlow/UtterSimulatorFlow/testKeyboardEndToEnd` and the unfiltered accessibility report with `-only-testing:UtterSimulatorFlow/UtterSimulatorFlow/testNativeAccessibilityAudit`. Actual maximum-size scrolling/navigation is checked separately by `testLargeTextNavigationEvidence`; visible scaling does not mean the automatic audit passed.

The microphone-denial test requires `xcrun simctl privacy SIMULATOR_UUID revoke microphone com.ichendev.utter.ios` first; it never records audio. `testKeyboardEditsWithoutFullAccess` requires Full Access off in the designated test simulator and skips if access is on. Restore its prior permission state after that check. Language changes, the Chinese interface, dictionary replacement/deletion and real copy/paste have separate native interaction tests.

## Device setup

An isolated standby experiment is available through `bash scripts/build-ios-standby-probe.sh`; it builds a copied Debug Simulator project without changing the product entry point. The tested Air simulator reports both video-call and ordinary video PiP unsupported. Its plain background synthetic Start/Stop/insertion control passes, which does not establish keepalive or native Intent dispatch. See [standby-experiment.md](../docs/sdlc/changes/2026-10-04-ios-support/standby-experiment.md) for reproduction, evidence and required restoration after testing.

Create the ignored `iOS/Development.local.xcconfig` with your registered values:

```xcconfig
UTTER_DEVELOPMENT_TEAM = YOUR_TEAM_ID
UTTER_BUNDLE_PREFIX = YOUR_REGISTERED_BUNDLE_PREFIX
UTTER_APP_GROUP = group.YOUR_REGISTERED_GROUP
```

Use the `UtteriOS` scheme in Xcode and the connected phone for normal development signing. Register matching app, keyboard and Live Activity identifiers and enable the App Group for each. Do not store certificates, account passwords or provisioning profiles in this repository.

For the isolated physical PiP start/stop gate (no microphone or keyboard Full Access):

```sh
UTTER_DEVELOPMENT_TEAM=YOUR_TEAM_ID bash scripts/build-ios-standby-probe.sh --device DEVICE_UDID
xcodebuild -xctestrun .build-ios/standby-device-probe/build/Build/Products/UtteriOS_iphoneos27.0-arm64.xctestrun \
  -destination 'id=DEVICE_UDID' -parallel-testing-enabled NO \
  -only-testing:UtterSimulatorFlow/UtterSimulatorFlow/testPiPStartAndStop test-without-building
```

For paired 75-second background observations, select `testDevicePiPBackgroundTicks` and `testDevicePlainBackgroundTicks` instead. Their counters cover the complete UIKit background interval, including first/last gaps, and record the actual PiP state on return. On iPad mini (A17 Pro) / iPadOS 27.2, both groups continued running with a 0.28-second maximum gap; this does not establish a PiP keepalive advantage. Sampled screenshots showed no visible PiP window, not proof of continuous invisibility or coexistence.

Keep the device unlocked and dismiss floating windows before testing. This builds only the device probe and runner; the separate video host remains simulator-only, so do not run its full suite on a device. Both the copied probe and current product support device families 1 and 2. Restore the normal app after testing. A start/stop pass does not establish background execution, invisible presentation, microphone reactivation or coexistence.

## Current inference boundary

The workflow supports Apple's on-device SpeechAnalyzer, locally installed Whisper models, and experimental shared Qwen/Confucius ASR backends, with the shared local dictionary/text preparation services. Preparing an Apple language can download system language assets. Missing local capability reports an error; speech is not uploaded as a fallback. History is not committed by the mobile workflow. Recording files live in the app's protected temporary directory, and the keyboard only receives short-lived status/results. The configured recording limit ends capture and transcribes the captured audio; explicit cancellation discards it. The same limit path is covered by a 30-second synthetic-session UI regression without accessing the microphone.

The model registry currently offers Qwen3-ASR 1.7B and Confucius 8-bit, not the smaller research candidates. Downloads being available is not a device performance qualification. Their recognition quality, peak memory, heat and background execution require physical measurements, especially on iPhone Air. Foundation Models, a bundled LLM and optional cloud paths remain later work. No cloud client or credentials service is mounted.

The device acceptance matrix, independent review and current gaps are recorded in [verification.md](../docs/sdlc/changes/2026-10-04-ios-support/verification.md). Simulator success cannot pass the Air microphone/background/PiP gate.
