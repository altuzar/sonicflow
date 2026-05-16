import SwiftUI
import AppKit

struct AppRowView: View {
    let app: AudioApp
    @Bindable var state: AudioState
    let engine: any AudioEngine

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Larger 40px icon, click-to-mute target.
            AppIconView(
                icon: app.icon,
                isActive: app.isActive,
                level: app.levelMeter,
                isMuted: app.isMuted,
                tint: tint
            )
            .onTapGesture {
                guard app.supportsVolumeControl else { return }
                withAnimation(.snappy) { engine.setMuted(!app.isMuted, for: app.id) }
                HapticFeedback.tap()
            }
            .help(iconHelp)

            VStack(alignment: .leading, spacing: 6) {
                // Top line: name + comm badge + ... + % + lock badge
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if app.category == .communication {
                        Image(systemName: "person.wave.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .help("Communication app — triggers ducking when active")
                    }

                    Spacer(minLength: 0)

                    if !app.supportsVolumeControl {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange.opacity(0.85))
                            .help("Per-app volume not yet supported for this app")
                    }

                    Text(volumeText)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(app.isMuted ? .red.opacity(0.85) : .secondary)
                        .contentTransition(.numericText())
                }

                // Bottom line: mute glyph + slider
                HStack(spacing: 10) {
                    Button {
                        guard app.supportsVolumeControl else { return }
                        withAnimation(.snappy) { engine.setMuted(!app.isMuted, for: app.id) }
                        HapticFeedback.tap()
                    } label: {
                        Image(systemName: app.isMuted ? "speaker.slash.fill" : muteGlyph)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(app.isMuted ? .red : .secondary)
                            .frame(width: 14, height: 14)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .disabled(!app.supportsVolumeControl)

                    FluidSlider(
                        value: Binding(
                            get: { Double(app.volume) },
                            set: { engine.applyGain(Float($0), to: app.id) }
                        ),
                        height: 22,
                        accent: accentColor,
                        levelMeter: app.isActive ? Double(app.levelMeter) : 0
                    )
                    .disabled(!app.supportsVolumeControl)
                    .opacity(app.supportsVolumeControl ? 1.0 : 0.5)
                    .allowsHitTesting(app.supportsVolumeControl)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay(alignment: .leading) { activeMarker }
        .onHover { isHovered = $0 }
        .animation(.snappy, value: app.isActive)
        .animation(.snappy, value: app.isMuted)
        .contextMenu {
            Button(app.isMuted ? "Unmute" : "Mute") {
                engine.setMuted(!app.isMuted, for: app.id)
                HapticFeedback.tap()
            }
            .disabled(!app.supportsVolumeControl)
            Divider()
            Button("Show \(app.displayName)") { activateApp() }
                .disabled(app.pid == nil)
            Button("Quit \(app.displayName)") { quitApp() }
                .disabled(app.pid == nil)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var rowBackground: some View {
        if app.isMuted {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.red.opacity(0.18), lineWidth: 0.5))
        } else if isHovered {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var activeMarker: some View {
        if app.isActive && !app.isMuted {
            Capsule()
                .fill(LinearGradient(
                    colors: [.cyan, .blue],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 3, height: 22)
                .padding(.leading, 3)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private func activateApp() {
        guard let pid = app.pid,
              let running = NSRunningApplication(processIdentifier: pid) else { return }
        running.activate()
    }

    private func quitApp() {
        guard let pid = app.pid,
              let running = NSRunningApplication(processIdentifier: pid) else { return }
        running.terminate()
    }

    private var iconHelp: String {
        guard app.supportsVolumeControl else {
            return "Per-app volume control for \(app.displayName) not yet supported"
        }
        return app.isMuted ? "Unmute \(app.displayName)" : "Mute \(app.displayName)"
    }

    private var muteGlyph: String {
        let eff = state.effectiveVolume(for: app)
        switch eff {
        case 0:        return "speaker.fill"
        case ..<0.34:  return "speaker.wave.1.fill"
        case ..<0.67:  return "speaker.wave.2.fill"
        default:       return "speaker.wave.3.fill"
        }
    }

    private var volumeText: String {
        if !app.supportsVolumeControl { return "—" }
        if app.isMuted || state.isMasterMuted { return "Muted" }
        let eff = state.effectiveVolume(for: app)
        let pct = Int(eff * 100)
        if state.duckingEnabled, state.isAnyCommunicationActive, app.category != .communication {
            return "\(pct)%↓"
        }
        return "\(pct)%"
    }

    /// Color used for the icon's pulse ring + accent strokes.
    private var tint: Color {
        if app.isMuted { return .red.opacity(0.6) }
        switch app.category {
        case .communication: return .orange
        case .media:         return .cyan
        case .browser:       return .blue
        case .game:          return .purple
        case .other:         return .accentColor
        }
    }

    /// Slider gradient accent — varies by category for quick visual scan.
    private var accentColor: Color {
        if app.isMuted { return .red.opacity(0.55) }
        switch app.category {
        case .communication: return .orange
        case .media:         return Color(red: 0.12, green: 0.30, blue: 1.0)   // vivid SonicFlow blue
        case .browser:       return Color(red: 0.20, green: 0.50, blue: 1.0)
        case .game:          return Color(red: 0.50, green: 0.20, blue: 1.0)
        case .other:         return .accentColor
        }
    }
}

/// App icon with a brand-gradient ring when active + animated level meter.
/// Click target for mute toggle.
struct AppIconView: View {
    let icon: NSImage?
    let isActive: Bool
    let level: Float
    var isMuted: Bool = false
    var tint: Color = .accentColor

    private let size: CGFloat = 40
    private let inner: CGFloat = 32

    var body: some View {
        ZStack {
            // Active glow ring (gradient stroke that pulses with level).
            if isActive && !isMuted {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.cyan, .blue, .purple, .cyan],
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: size, height: size)
                    .scaleEffect(1.0 + Double(level) * 0.10)
                    .shadow(color: .cyan.opacity(0.4 + Double(level) * 0.4), radius: 4 + Double(level) * 4)
                    .animation(.easeOut(duration: 0.10), value: level)
            } else if !isActive && !isMuted {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: size, height: size)
            }

            // App icon proper.
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.tint.opacity(0.18))
                        Image(systemName: "app.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .frame(width: inner, height: inner)
            .grayscale(isMuted ? 0.85 : 0)
            .opacity(isMuted ? 0.55 : 1.0)
            .scaleEffect(isMuted ? 0.92 : 1.0)

            // Mute badge.
            if isMuted {
                Circle()
                    .fill(.red.gradient)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .red.opacity(0.5), radius: 4)
                    .offset(x: 13, y: 13)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.snappy, value: isMuted)
        .animation(.snappy, value: isActive)
    }
}
