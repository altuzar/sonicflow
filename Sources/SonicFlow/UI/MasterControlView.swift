import SwiftUI

struct MasterControlView: View {
    @Bindable var state: AudioState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("MASTER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Spacer()
                Text(state.isMasterMuted ? "Muted" : "\(Int(state.masterVolume * 100))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(state.isMasterMuted ? .red : .primary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { state.isMasterMuted.toggle() }
                    HapticFeedback.tap()
                } label: {
                    Image(systemName: state.isMasterMuted ? "speaker.slash.fill" : iconForVolume(state.masterVolume))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(state.isMasterMuted ? .red : .primary)
                        .frame(width: 22, height: 22)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                FluidSlider(
                    value: Binding(
                        get: { Double(state.masterVolume) },
                        set: { state.masterVolume = Float($0) }
                    ),
                    height: 30,
                    accent: state.isMasterMuted
                        ? .red.opacity(0.4)
                        : Color(red: 0.12, green: 0.30, blue: 1.0)
                )
            }
        }
    }

    private func iconForVolume(_ v: Float) -> String {
        switch v {
        case 0:        return "speaker.fill"
        case ..<0.34:  return "speaker.wave.1.fill"
        case ..<0.67:  return "speaker.wave.2.fill"
        default:       return "speaker.wave.3.fill"
        }
    }
}
