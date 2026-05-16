![SonicFlow — per-app volume for macOS](marketing/brand/lockup-banner.png)

# SonicFlow

> Per-app volume for macOS. Finally.

A free, open-source macOS menu bar app for **per-app volume control**.
Built in Swift 6 with SwiftUI + CoreAudio Process Taps.

[**Download v0.1**](https://github.com/altuzar/sonicflow/releases/latest) ·
[**Landing**](https://altuzar.github.io/sonicflow) ·
[**Roadmap**](ROADMAP.md) ·
[**Marketing kit**](marketing/)

---

## What it does

- 🎧 **Per-app audio detection** — every app currently producing audio shows
  up live in the menu bar panel.
- 🎚️ **Per-app volume slider** — adjust Music, Zoom, Chrome, Spotify
  independently. Changes apply in ~10 ms via a realtime IOProc.
- 🔇 **Click-to-mute** — tap any app's icon to mute it instantly.
- 📢 **Auto-ducking** — when a communication app (Zoom, Teams, Slack)
  actively outputs voice, other apps automatically lower by a configurable
  amount (default 50 %).
- 🎛️ **Master volume** — drives the macOS system volume; follows the
  keyboard volume keys (F11/F12).
- 🪟 **Menu bar only** — `LSUIElement = true`, no Dock icon, no window
  on launch.
- ⚡ **Low overhead** — < 1 % CPU at idle, 1–2 % under realtime audio
  processing.

---

## Architecture

Three layered phases, each behind the `AudioEngine` protocol so the UI is
unchanged across phases:

```
┌───────────────────────────────────────────────────────────────┐
│ SwiftUI MenuBarExtra panel                                     │
│   Observable AudioState → AppRowView · MasterControlView · …   │
└───────────────────────────────────────────────────────────────┘
                        ↑↓ any AudioEngine
┌───────────────────────────────────────────────────────────────┐
│ Phase 2: AudioProcessDetector                                  │
│   • kAudioHardwarePropertyProcessObjectList                    │
│   • kAudioProcessPropertyIsRunningOutput (piro) listener       │
│   • 1 Hz fallback poll for HAL state-change latency            │
└───────────────────────────────────────────────────────────────┘
                                ↓
┌───────────────────────────────────────────────────────────────┐
│ Phase 3: AudioGainController (per-app real-time gain)          │
│                                                                │
│   ProcessTap (one per app, CATapMutedWhenTapped)               │
│      ↓                                                         │
│   AggregateOutputDevice (private, captures taps)               │
│      IOProc: applies per-app gain, mixes stereo                │
│      ↓                                                         │
│   FloatRingBuffer (lock-free SPSC, 8192 samples)               │
│      ↓                                                         │
│   PlaybackDevice (IOProc on user's default output)             │
│      adds to outputData → speakers                             │
└───────────────────────────────────────────────────────────────┘
```

Tapped apps' direct path to the speakers is silenced (`CATapMutedWhenTapped`)
so we don't get double audio. Non-tapped apps flow through the system mixer
unchanged.

---

## Build & run

Requires **macOS 14.2+**, **Xcode 16+**, **Swift 6+**.

```bash
make sign           # build → wrap in .app → ad-hoc sign
open build/SonicFlow.app   # launch as menu bar app
```

For development:

```bash
make debug          # debug build
make run            # build + sign + open
make icon           # regenerate AppIcon.icns from SVG
```

### Runtime flags

| Flag | Effect |
|---|---|
| (none) | Production: Phase 3 enabled, menu bar only |
| `--no-gain` | Disable Phase 3 (detection only) |
| `--debug` | Verbose stats to stderr — HAL snapshots, frame counters |
| `--preview` | Mock engine in a floating window (design work) |
| `--preview-live` | Live engine in a floating window (useful when Ice hides the menu bar icon) |
| `--test-gain-cycle` | Auto-cycle the first active app through 25 % / 100 % / mute / 100 % / 50 % every 3 s |

---

## Permissions

- **AppleScript Automation** — for compatible apps (Music, Spotify, TV,
  Podcasts), SonicFlow uses AppleScript to also move the app's own volume
  slider. macOS will prompt "SonicFlow wants to control X" on first contact.
- **System Audio Capture (TCC)** — process taps may require explicit grant
  on macOS 14.4+ for system audio capture. The privacy string is in
  `Info.plist`.
- **No microphone permission requested** — the purple mic dot never appears.

---

## Project layout

```
sonicflow-app/
├── Package.swift                    SwiftPM, macOS 14.2+, Swift 6
├── Makefile                         build/sign/bundle helpers
├── README.md / CLAUDE.md / ROADMAP.md
├── Resources/Icon/                  AppIcon.svg → AppIcon.icns
├── Sources/SonicFlow/
│   ├── App/                         @main, AppDelegate, signal cleanup
│   ├── Models/                      AudioApp, AudioState (@Observable)
│   ├── Audio/                       Detector, Engine, GainController,
│   │                                ProcessTap, AggregateOutputDevice,
│   │                                PlaybackDevice, RingBuffer, …
│   ├── Services/PermissionsManager  Accessibility hooks (future hotkeys)
│   ├── UI/                          ControlCenterView, AppRowView,
│   │                                FluidSlider, SettingsView, …
│   └── Resources/Info.plist / SonicFlow.entitlements
└── build/SonicFlow.app              output bundle (832 KB)
```

---

## Honest status

- ✅ **Phase 1 — UI mockup** — done
- ✅ **Phase 2 — Live detection** — done, push + poll fallback
- ✅ **Phase 3 — Real per-app gain** — done, two-IOProc + ring buffer
- ⚠️ Not yet: real RMS meters from the IOProc, headphone hot-swap,
  persistence between launches, Developer ID signing.
- See [ROADMAP.md](ROADMAP.md) for the full open list.

---

## Acknowledgements

Inspired by the architecture used by SoundSource, BackgroundMusic, and
similar pro audio utilities. CoreAudio Process Tap API by Apple (macOS
14.2+).
