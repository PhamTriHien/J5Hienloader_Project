# Platform Behavior

Windows, Android and iOS share the Flutter UI, session manager, viewport,
LCDUI dialogs and C++ VM. Platform code handles document pickers, audio,
HTTP transport and OS lifecycle integration.

## Configuration

- `UiScaleMode` stores fit, fitWidth, stretch, original1x, scale2x or scale3x.
- Legacy `ScreenScaleType` keeps the core meaning: 0 original, 1 fit, 2 stretch.
- `ScreenAutoMatch` matches the canvas to the available game viewport in fit mode.
  Fixed resolution presets disable it. Native text input and modal dialogs do not
  trigger canvas resizing. Rotation and window changes settle before resizing.
- Screen filter, touch input, FPS display, keypad shape, opacity and haptics are
  applied from the same profile on every platform.
- FPS limit 0 disables the FPS cap; the core retains a minimum 1 ms loop sleep.
- Restart applies dimensions before startApp and preserves pause and speed state.
- Restart also preserves the current FPS setting and applies pause before startup.
- Closing clone slots remain reserved until native cleanup finishes. Pending
  cleanup counts toward the session limit and memory-pressure recovery.
- The session manager polls native running/pause state once per second so a
  MIDlet that exits or pauses updates the foreground service count.
- MIDlet notifyDestroyed terminates its Java workers. A naturally exited engine
  joins its old thread before it can be started again.

## OS Integration

- Android runs background sessions with a foreground service.
  Its timed wake lock is renewed every five minutes while unpaused sessions exist.
  Process termination requires a user restart; a service notification cannot restore a VM.
- Hidden sessions publish at most one frame per second without changing their configured FPS.
  Canvas paint callbacks are throttled; games that draw directly through GameCanvas
  can still perform internal drawing at their own rate.
  New sessions are limited to eight on mobile and sixteen on desktop, and blocked
  after a memory pressure notification until all sessions are closed.
- The VM begins garbage collection at 100,000 objects instead of 400,000,
  then adapts to the live set. This is an object threshold, not a byte memory cap.
- Java workers reserve an 8 MB stack on Apple and Windows to accommodate
  the recursive interpreter. Engine destruction waits for worker cleanup.
- TCP uses keepalive, transient send retries and complete writes. Server disconnects
  still require the game's own reconnect/login handling; no protocol packets are replayed.
- Windows runs sessions while the process remains open.
- iOS pauses running sessions when the app enters the background and resumes
  only those sessions on return. Manually paused sessions remain paused.
  iOS suspension prevents continuous background game execution and may expire sockets.
- These safeguards do not establish 24-hour stability. Long-duration multi-session
  tests and physical Android battery/Doze tests are still required.
- Mobile JAR and screenshot export uses the OS document picker. Cancelling
  export leaves the source intact. Desktop export keeps the existing path behavior.

## Validation

Local Windows validation: Flutter analyze, Flutter tests, Windows release build,
native test_core with assertions enabled, Android ARM64 and x86_64 APK builds.
The Pixel 10 Pro emulator validates the x86_64 APK. An ARM64 APK build does not
replace testing on a physical Android phone.

The GitHub Actions workflow builds all three platforms. iOS device output is
unsigned and requires Apple signing before installation. iOS build and runtime
validation require macOS/Xcode and have not been run on this Windows workstation.

```powershell
flutter analyze
flutter test
flutter build windows --release
flutter build apk --debug --target-platform android-arm64,android-x64 --split-per-abi
```

## iOS Build and Test Environments

The `build-ios-ipa.yml` workflow uses a macOS runner and produces
`J5Hienloader-unsigned.ipa` for devices and `J5Hienloader-simulator.zip`
for simulator testing. The workflow must run on a commit containing the
desired local changes; dispatching it does not upload uncommitted files.

- Xcode Simulator on a Mac: build with `flutter build ios --simulator --debug`,
  then install `build/ios/iphonesimulator/Runner.app` in a booted simulator.
- Appetize browser testing: upload `J5Hienloader-simulator.zip`. Appetize
  accepts simulator `.app` bundles in ZIP files, not device IPA files.
  See https://docs.appetize.io/platform/app-management/uploading-apps/ios.
- Physical iPhone: the unsigned IPA needs signing with an appropriate
  certificate and provisioning profile before installation.

Runtime checks should cover startup, JAR import, game launch, portrait and
landscape input, audio, network access, RMS persistence, and background/resume.
Passing Flutter tests or producing an IPA does not establish iOS runtime success.
