import SwiftUI

/// Top-level Control Center panel.
struct ControlCenterView: View {
    let engine: any AudioEngine
    @State private var showSettings = false

    var body: some View {
        @Bindable var state = engine.state

        VStack(spacing: 0) {
            HeaderView(state: state, showSettings: $showSettings)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

            Divider().opacity(0.3)

            if showSettings {
                SettingsView(state: state)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainPanel(engine: engine, state: state)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 340)
        .frame(minHeight: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSettings)
    }
}

private struct MainPanel: View {
    let engine: any AudioEngine
    @Bindable var state: AudioState

    var body: some View {
        // Only display apps that are actually producing audio right now —
        // matches user expectation ("apps playing"), removes the awkward
        // "No audio playing" + stale-rows mismatch, and avoids showing
        // washed-out dim rows. State still remembers paused apps' volumes.
        let visibleApps = state.apps.filter { $0.isActive }

        VStack(spacing: 0) {
            MasterControlView(state: state)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            if state.duckingEnabled && state.isAnyCommunicationActive {
                DuckingBanner(amount: state.duckingAmount)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().opacity(0.25)

            if visibleApps.isEmpty {
                EmptyStateView()
                    .padding(.vertical, 36)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visibleApps) { app in
                            AppRowView(app: app, state: state, engine: engine)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal:   .opacity.combined(with: .scale(scale: 0.96))
                                ))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 360)
            }

            FooterView(engine: engine)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.isAnyCommunicationActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: visibleApps.map(\.id))
        // Master/ducking changes affect every app's effective gain — re-push
        // to the realtime controller whenever any of these change.
        .onChange(of: state.masterVolume) { _, newValue in
            engine.resyncAllGains()
            if state.masterControlsSystemVolume {
                SystemVolume.set(state.isMasterMuted ? 0 : newValue)
            }
        }
        .onChange(of: state.isMasterMuted) { _, muted in
            engine.resyncAllGains()
            if state.masterControlsSystemVolume {
                SystemVolume.set(muted ? 0 : state.masterVolume)
            }
        }
        .onChange(of: state.duckingEnabled)           { _, _ in engine.resyncAllGains() }
        .onChange(of: state.duckingAmount)            { _, _ in engine.resyncAllGains() }
        .onChange(of: state.isAnyCommunicationActive) { _, _ in engine.resyncAllGains() }
    }
}

private struct EmptyStateView: View {
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(LinearGradient(
                        colors: [.cyan.opacity(0.4), .blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .opacity(pulse ? 0.6 : 1.0)
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .symbolEffect(.variableColor.iterative, options: .repeating, value: pulse)
            }
            .frame(height: 64)

            Text("Listening for audio…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 2)

            Text("Apps appear here the moment they start playing sound.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct HeaderView: View {
    @Bindable var state: AudioState
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Brand gradient mini-icon with the same waveform glyph as the bundle.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.88, blue: 1.00),
                                Color(red: 0.10, green: 0.30, blue: 1.00),
                                Color(red: 0.48, green: 0.12, blue: 1.00)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(color: .blue.opacity(0.30), radius: 6, y: 2)

                HStack(spacing: 1.5) {
                    Capsule().fill(.white).frame(width: 2, height: 8)
                    Capsule().fill(.white).frame(width: 2, height: 14)
                    Capsule().fill(.white).frame(width: 2, height: 18)
                    Capsule().fill(.white).frame(width: 2, height: 12)
                    Capsule().fill(.white).frame(width: 2, height: 6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SonicFlow")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.apps.contains(where: { $0.isActive }) ? .green : .secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "chevron.left" : "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(.quaternary)
                            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(showSettings ? "Back" : "Settings")
        }
    }

    private var statusText: String {
        let active = state.apps.filter { $0.isActive }.count
        if state.isMasterMuted { return "Master muted" }
        if active == 0         { return "Ready · no audio yet" }
        return "\(active) app\(active == 1 ? "" : "s") playing"
    }
}

private struct DuckingBanner: View {
    let amount: Float

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Ducking active · others lowered \(Int(amount * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.orange.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.orange.opacity(0.30), lineWidth: 0.5)
                )
        )
    }
}

private struct FooterView: View {
    let engine: any AudioEngine

    var body: some View {
        HStack(spacing: 8) {
            Text(footerLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            // Mock-only demo: flip "is playing" on each app.
            if let mock = engine as? MockAudioEngine {
                Menu {
                    ForEach(mock.state.apps) { app in
                        Button("\(app.isActive ? "Stop" : "Start") \(app.displayName)") {
                            mock.toggleActivity(for: app.id)
                        }
                    }
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Toggle which apps are 'playing audio'")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit SonicFlow")
        }
    }

    private var footerLabel: String {
        if engine is MockAudioEngine { return "Mock data" }
        return "Live audio detection"
    }
}
