import SwiftUI

struct SettingsView: View {
    @Bindable var state: AudioState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section(title: "Ducking", icon: "waveform.badge.mic") {
                    Toggle("Auto-duck when someone speaks", isOn: $state.duckingEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 13, weight: .medium))

                    Text("Comm apps (Zoom, Teams, Slack) automatically lower everything else when they're outputting voice.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)

                    LabeledControl(label: "Lower by", value: "\(Int(state.duckingAmount * 100))%") {
                        FluidSlider(
                            value: Binding(
                                get: { Double(state.duckingAmount) },
                                set: { state.duckingAmount = Float($0) }
                            ),
                            height: 18,
                            accent: .orange
                        )
                    }
                    .disabled(!state.duckingEnabled)
                    .opacity(state.duckingEnabled ? 1 : 0.5)
                }

                section(title: "System integration", icon: "speaker.wave.2.fill") {
                    Toggle("Master slider drives system volume", isOn: $state.masterControlsSystemVolume)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 13, weight: .medium))

                    Text("Sync the master slider with the macOS output volume so F11/F12 work both ways.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                section(title: "About", icon: "sparkles") {
                    InfoLine(label: "Version", value: "0.1.0")
                    InfoLine(label: "Engine", value: "CoreAudio Process Taps")
                    InfoLine(label: "CPU target", value: "< 1%")
                    InfoLine(label: "License", value: "MIT · Free + open source")

                    HStack(spacing: 8) {
                        Link(destination: URL(string: "https://github.com/altuzar/sonicflow")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("GitHub")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.tint)
                        }
                        Link(destination: URL(string: "https://github.com/altuzar/sonicflow/issues")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "ladybug")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Report a bug")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.tint)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            content()
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LabeledControl<Content: View>: View {
    let label: String
    let value: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.tint)
            }
            content()
        }
    }
}

private struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium))
        }
    }
}
