# AGENTS.md — project guide for AI sessions

Quick orientation for any future Codex/AI agent picking up this project.

---

## What this is

A macOS menu bar app that does **per-app volume control** via CoreAudio
Process Taps. The interesting part is `Sources/SonicFlow/Audio/*` — that's
where the real engineering lives.

---

## Build / run / iterate

```bash
# Always run these from the project root.
cd /Users/altuzar/tests/macapps/sonicflow-app

# Compile only
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release

# Full build → .app bundle → ad-hoc sign
make sign

# Launch as a normal user would
open build/SonicFlow.app

# With verbose stats to stderr (HAL snapshots + IOProc frame counters)
./build/SonicFlow.app/Contents/MacOS/SonicFlow --debug

# With a floating window (when the user's Ice/Bartender hides the menu bar icon)
./build/SonicFlow.app/Contents/MacOS/SonicFlow --preview-live
```

### Sandbox

SwiftPM uses `sandbox-exec` internally during manifest compilation. The
Codex outer sandbox blocks that. **All `swift build` and `make` calls
need `dangerouslyDisableSandbox: true` on the Bash tool.** The user can
manage these via `/sandbox`.

---

## Key files (and why)

| File | Role |
|---|---|
| `App/SonicFlowApp.swift` | `@main`, MenuBarExtra, engine selection |
| `App/AppDelegate.swift` | Signal cleanup, `--preview` floating window, `--debug` detector |
| `Models/AudioState.swift` | `@Observable @MainActor` single source of truth |
| `Models/AudioApp.swift` | Per-app data struct (note: `supportsVolumeControl`) |
| `Audio/AudioEngine.swift` | Protocol — `MockAudioEngine` / `CoreAudioEngine` plug in |
| `Audio/MockAudioEngine.swift` | 6-app fixture for design work (`--mock` / `--preview`) |
| `Audio/CoreAudioConstants.swift` | **FourCC constants** + typed wrappers + `ListenerHandle` RAII |
| `Audio/AudioProcessDetector.swift` | HAL enumeration + push listeners + 1 Hz poll fallback |
| `Audio/AppCategorizer.swift` | Bundle ID → category mapping (drives ducking) |
| `Audio/CoreAudioEngine.swift` | Live engine — wires detector → state → gain |
| `Audio/AudioGainController.swift` | Phase 3 orchestrator (manages capture+playback+ring) |
| `Audio/ProcessTap.swift` | `CATapDescription` + `AudioHardwareCreateProcessTap` wrapper |
| `Audio/AggregateOutputDevice.swift` | **Capture half** — taps → IOProc → ring buffer |
| `Audio/PlaybackDevice.swift` | **Playback half** — IOProc on default output → speakers |
| `Audio/RingBuffer.swift` | Wait-free SPSC float ring buffer |
| `Audio/AppleScriptVolume.swift` | Stopgap for scriptable apps + sync probe |
| `Audio/SystemVolumeListener.swift` | Watches system volume property; syncs master slider |
| `UI/FluidSlider.swift` | Custom slider, native-feel thumb geometry, haptic ticks |
| `UI/AppRowView.swift` | Per-app row: icon (click to mute), name, slider, mute glyph |
| `UI/ControlCenterView.swift` | Top-level panel with master + scroll list + ducking banner |

---

## Architecture invariants

- **One `AudioState` lives on `@MainActor`**. The IOProcs read gain values
  via raw pointers (`Float` is aligned-32-bit atomic on arm64/x86_64). Never
  touch main-actor state from an IOProc.
- **IOProc callbacks are realtime threads**: no `malloc`, no locks (use the
  ring buffer), no Swift main-actor calls. `withUnsafeTemporaryAllocation`
  for stack scratch space is fine.
- **The `FloatRingBuffer` is single-producer / single-consumer.** Capture
  IOProc writes; playback IOProc reads. Don't add a second producer.
- **Capture aggregate is `kAudioAggregateDeviceIsPrivateKey: 1`**. We do NOT
  set it as system default output — that was the broken approach. We now
  use a second IOProc on the user's *real* default output and mix in.

---

## Gotchas (these all bit me at least once)

1. **CoreAudio FourCC for `IsRunningOutput` is `'piro'`, not `'pio?'`.**
   The latter is plausible from the pattern of `kAudioProcessPropertyIsRunning`
   = `'pir?'` but it's wrong. Check `AudioHardware.h` in the SDK if any tap
   property seems "silently broken." Same for tap UID: `'tuid'`, not `'uid '`.

2. **`CATapDescription.privateTap` / `.exclusive` / `.mixdown`** got renamed
   to `isPrivate` / `isExclusive` / `isMixdown` in Swift. `muteBehavior` is
   `CATapMuteBehavior(rawValue: 2)` for `CATapMutedWhenTapped` because Swift
   can't infer the case from the `getter=isMuted` ObjC attribute.

3. **`MenuBarExtra` content's `.task` only fires when the user opens the
   menu.** If you put engine startup there and the user has a menu bar
   manager (Ice/Bartender) hiding the icon, the engine never starts. Use
   `init()` on the `@main App` instead — see `SonicFlowApp.swift`.

4. **Helper bundle IDs** (`com.apple.Music.helper`, `.gpu`, `.renderer`,
   `xpcservice`) show up in the process list. Dedupe them in
   `AudioProcessDetector.isHelperBundle` — they confuse users.

5. **AppleScript Automation permission** is per-app pair. Re-signing the
   bundle counts as a different app to macOS, so the user may need to
   re-grant. The probe at startup (in `applyGain`-adjacent code) triggers
   the prompt before the user drags a slider in anger.

6. **Setting our aggregate as system default output is a trap.** It works
   for output routing but `inputBuffers` becomes 0 in our IOProc — tap data
   stops showing up. That's why Phase 3 uses two separate IOProcs with the
   aggregate remaining private. If a future version reverts to "aggregate
   as default," confirm tap input still works.

7. **External-volume poll for AppleScript apps will fight the user's drag.**
   `CoreAudioEngine.lastUserWriteTime` suppresses the poll for 1.5 s after
   a user touch. Don't remove that without re-testing.

8. **macOS volume listener uses output scope, not global.**
   `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` = `'volm'`. The
   convenience `CAObject.addListener` uses global scope; use a direct
   `AudioObjectAddPropertyListenerBlock` call for volume (see
   `SystemVolumeListener.rebindVolumeListener`).

9. **Signal handlers are still installed** in `AppDelegate.installCrashCleanup`
   to restore the user's default output if the app crashes. Even though
   Phase 3 no longer switches the default, leave this in — cheap safety net.

10. **The `--preview` and `--preview-live` modes open a peer engine in a
    floating window.** This means TWO engines run when `--preview-live` is
    on (the MenuBarExtra's production engine + the preview's peer). Don't
    use this combo for accurate testing of singleton behavior.

---

## Conventions used in this codebase

- **Use `Edit` over `Write`** for incremental changes — preserves diffs.
- **No comments unless WHY is non-obvious.** Names should carry intent.
  Existing code follows this; preserve it.
- **Logging to stderr** via `FileHandle.standardError.write(Data(...utf8))`
  is fine in non-realtime paths. **Never** in IOProc callbacks.
- **`@unchecked Sendable`** is acceptable on classes whose mutable state is
  guarded by a private serial queue (see `AudioProcessDetector`).

---

## Testing

There are no XCTests yet — manual verification:

- `--debug` flag streams per-2s frame counters. `tap=X ring=Y playback=Z
  underrun=0` means audio is flowing. Look for `ring=0` (consumer keeps up)
  and `underrun=0` after the first interval.
- `--test-gain-cycle` programmatically cycles the first detected app's
  gain to 25 % / 100 % / mute / 100 % / 50 % at 3-second intervals.
  Listen for matching volume changes.
- For UI changes, `--preview-live` opens the panel in a floating window
  so you can screenshot it without fighting menu bar managers.

---

## Common operations

```bash
# Reset audio if SonicFlow crashed and left the system default pointed at
# a dead aggregate (rare now that we don't switch defaults, but the script
# is still useful for debugging):
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift \
  /tmp/Codex/sonicflow/reset-audio.swift

# Regenerate the app icon from SVG
cd Resources/Icon && rsvg-convert -w 1024 -h 1024 AppIcon.svg -o master.png
make icon

# Inspect SDK headers for any unknown FourCC
grep -rn 'kAudioProcessProperty' /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/
```

---

## What's deliberately NOT in this codebase

- No `XCTest` target — manual verification only.
- No CI — local builds.
- No Developer ID signing — ad-hoc only (`codesign --sign -`). Distribution
  is in `ROADMAP.md`.
- No persistence — per-app volumes reset on launch.
- No sandboxing — `com.apple.security.app-sandbox = false`. Process Taps
  require this.
