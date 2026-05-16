# SonicFlow Roadmap

Honest list of what's done, what's pending polish, and what's a real
investment.

---

## ✅ Shipped

### Phase 1 — UI mockup (done)
- SwiftUI `MenuBarExtra(.window)` panel
- `LSUIElement = true` (menu-bar-only, no Dock icon)
- Master slider, per-app rows with icon/name/slider/mute/level meter
- Custom `FluidSlider` with macOS-native thumb geometry + haptic ticks
- Liquid Glass aesthetic (`ultraThinMaterial`)
- Light/dark mode
- App icon: SVG → ICNS pipeline (waveform-pattern on gradient squircle)
- Empty state, settings sub-panel, ducking banner

### Phase 2 — Live detection (done)
- `kAudioHardwarePropertyProcessObjectList` enumeration
- Per-process property listeners on `kAudioProcessPropertyIsRunningOutput`
- 1 Hz fallback poll for HAL listener latency
- Helper-bundle filtering (`.helper`, `.gpu`, `.renderer`, `xpcservice`)
- System-process hide-list (CoreSpeech, audiomxd, accessibility daemons…)
- App categorization (communication / browser / media / game) driving ducking
- Cold-cache app icon + display-name resolution via `NSRunningApplication`

### Phase 3 — Per-app gain (done)
- `CATapDescription` + `AudioHardwareCreateProcessTap` per active app
- Capture path: private aggregate device → IOProc applies per-app gain →
  mixes stereo → writes to ring buffer
- Lock-free SPSC `FloatRingBuffer` (8192 samples, ~85 ms @ 48 kHz)
- Playback path: IOProc on user's real default output → reads ring buffer
  → adds to outputData (mixes with non-tapped apps)
- Realtime callbacks are allocation-free and lock-free
- Gain values: aligned-32-bit `Float` written by main, read by IOProc
- Ducking: state-driven, `.onChange(isAnyCommunicationActive)` re-syncs gains
- Click-to-mute on icon + mute glyph + context menu
- System-volume sync (master slider follows F11/F12)
- AppleScript fallback for Music/Spotify/TV/Podcasts (also updates the
  app's own visible volume slider)
- Crash-safe: signal handler restores default output (legacy from when we
  changed it; still installed as cheap safety net)

### Quality of life
- `make sign / make run / make debug / make icon` workflow
- `--debug`, `--preview`, `--preview-live`, `--mock`, `--test-gain-cycle`
  diagnostic flags
- All 4 reported UX bugs from the dev loop fixed (slider overshoot, window
  drag, ducking false positive, "Helper" rows)

---

## 🪒 Polish (small)

| Task | Effort | Value |
|---|---|---|
| Real **RMS level meters** from the IOProc, published via a second SPSC ring | low | medium |
| **Headphone hot-swap** — listen for `kAudioHardwarePropertyDefaultOutputDevice` change, rebind playback IOProc to new device | low | high |
| **Sample-rate handling** — query device nominal sample rate, resample if tap and output disagree | low-med | medium |
| **Mute click suppression** — fade gain over 5–10 ms instead of instant 0 (avoids audible click on fast transitions) | low | medium |
| **Row entry/exit animations** — already partially present, could be smoother | low | low |
| **Settings panel expansion** — ducking attack/release sliders, output-device picker | low | medium |
| **Custom monochrome menu bar icon** asset matching the bundle icon at 16/32 px (currently SF Symbol `waveform`) | low | low |

---

## 🛠 Real work (medium)

| Task | Effort | Value |
|---|---|---|
| **Global hotkeys** — system-wide volume cmd+up/down with Accessibility permission | medium | high |
| **Persistence** — remember per-app volumes across launches via `UserDefaults`, restore on app re-launch | medium | high |
| **Auto-launch at login** via `SMAppService.mainApp` | low-med | medium |
| **Permissions UI** — proper in-app onboarding for AppleScript Automation + System Audio Capture (currently silent failures with log messages) | medium | high |
| **Multiple output device support** — explicit picker, per-app routing | medium-high | medium |
| **App allowlist** — let user choose which apps SonicFlow controls (not auto-tap everything) | medium | low-med |
| **Tap re-creation strategy** — current design tears down + rebuilds the entire aggregate when the active set changes. Smoother to add/remove taps in place. | medium | medium |
| **Crash diagnostics** — symbolicated reports, optional opt-in | medium | low |

---

## 🚢 Distribution (big)

| Task | Effort | Value |
|---|---|---|
| **Developer ID code signing** + Notarization — currently ad-hoc, only runs on this Mac | medium | required for ship |
| **DMG installer** (or .pkg) with a license screen | low-med | medium |
| **Sparkle auto-update** integration | medium | high (post-launch) |
| **Privacy policy + website** — required for Notarization, helpful for users | low | required |
| **App Store submission** — *would require sandboxing, which breaks Process Taps. Probably not viable.* | n/a | n/a |
| **Pricing / licensing** — free? Set Apps Inc-style? donation-ware? | n/a | n/a |
| **Marketing site** — feature page, demo video, comparison vs SoundSource | high | high |

---

## 🧪 Things to test / verify

- Phase 3 audio on a multi-channel device (USB DAC, audio interface)
- Phase 3 audio on AirPods / Bluetooth output
- Multiple comm apps active simultaneously (Zoom + Teams)
- Apps with non-stereo output (mono → stereo upmix)
- Performance under stress (10+ concurrent audio apps)
- Behavior when CoreAudio HAL restarts (e.g. after a sample-rate change)
- macOS 15 Sequoia / 26 (whatever lands) — the orange audio-capture
  indicator behavior may change

---

## 🗂 Out of scope (for now)

- iOS / iPadOS port — Process Tap API isn't available there
- Cross-fade / EQ / effects beyond simple gain — that's a different
  product (and what Audio Hijack already does well)
- A free-form audio router — see Loopback

---

## Honest current state

This is a **functional MVP**. The Phase 3 audio pipeline is genuinely
working with two IOProcs and a ring buffer, proven via stats
(`tap=400k ring=0 playback=200k underrun=0` per 2 s).

For one user on one Mac, it works. For shipping to other users, the
distribution column above is mandatory work.
