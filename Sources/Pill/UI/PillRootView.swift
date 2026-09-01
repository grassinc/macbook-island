import SwiftUI
import PillCore

struct PillRootView: View {
    @ObservedObject var model: PillViewModel
    @ObservedObject var audio: AudioOutputStore

    var body: some View {
        ZStack {
            shape.fill(.black)
            shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            content
        }
        .frame(width: model.size.width, height: model.size.height)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: model.size)
        .animation(.easeInOut(duration: 0.18), value: model.activity)
        .contentShape(shape)
        .onHover { model.setHovered($0) }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: model.presentation == .collapsed ? 15 : 22, style: .continuous)
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .collapsed: collapsed.padding(.horizontal, 12)
        case .expanded:  expanded.padding(12)
        }
    }

    // MARK: - Collapsed

    @ViewBuilder
    private var collapsed: some View {
        if let activity = model.activity {
            HStack(spacing: 7) {
                Image(systemName: icon(for: activity))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(activity.title.isEmpty ? activity.id : activity.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .transition(.opacity)
        } else {
            // Idle: deliberately almost nothing. The pill should be easy to
            // ignore when it has nothing to say.
            HStack {
                Spacer()
                Capsule().fill(.white.opacity(0.22)).frame(width: 26, height: 3)
                Spacer()
            }
        }
    }

    private func icon(for activity: Activity) -> String {
        switch activity.kind {
        case .audioOutput: return audioIcon
        case .hud:         return "speaker.wave.2.fill"
        case .screenshot:  return "camera.viewfinder"
        case .generic:     return "circle.fill"
        }
    }

    private var audioIcon: String {
        switch audio.state.current?.transport {
        case .bluetooth: "airpods.pro"
        case .usb, .displayPort, .hdmi: "hifispeaker.fill"
        case .airPlay: "airplayaudio"
        default: "laptopcomputer"
        }
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OUTPUT")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .kerning(0.8)

            if audio.state.devices.isEmpty {
                Text("No output devices")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 30)
            } else {
                ForEach(audio.state.devices) { device in
                    DeviceRow(device: device,
                              isCurrent: device.id == audio.state.current?.id) {
                        model.selectDevice?(device)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DeviceRow: View {
    let device: AudioOutputDevice
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(device.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isCurrent ? .white : .white.opacity(0.72))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.14 : (isCurrent ? 0.08 : 0)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        switch device.transport {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "airpods.pro"
        case .usb, .displayPort, .hdmi: "hifispeaker.fill"
        case .airPlay: "airplayaudio"
        case .virtual: "waveform"
        case .unknown: "speaker.wave.2"
        }
    }
}
