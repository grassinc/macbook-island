import SwiftUI
import PillCore

struct PillRootView: View {
    @ObservedObject var model: PillViewModel
    @ObservedObject var audio: AudioOutputStore
    @ObservedObject var hud: HUDStore
    @ObservedObject var shelf: ShelfObservable
    @ObservedObject var battery: BatteryStore
    @ObservedObject var thermal: ThermalStore
    @ObservedObject var timer: TimerStore
    @ObservedObject var calendar: CalendarStore
    @ObservedObject var privacy: PrivacyStore
    @ObservedObject var email: EmailStore
    @ObservedObject var nowPlaying: NowPlayingStore
    @ObservedObject var network: NetworkStore

    /// The output list is a disclosure, not a permanent fixture: the sketch puts
    /// OUTPUT on the status row as one control, and an always-open device list
    /// made the panel twice as tall as everything else combined.
    @State private var outputExpanded = false

    var body: some View {
        ZStack {
            shape.fill(.black)
            shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            content
        }
        // Width is fixed; height comes from the content and is reported back,
        // so the panel can never clip what it is asked to show.
        .frame(width: model.size.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            model.setMeasuredHeight(height)
        }
        // Deliberately NOT animated here. The window controller animates the
        // panel frame; if SwiftUI animated the content too, onGeometryChange
        // would report intermediate heights and the window would chase its own
        // animation instead of settling.
        .animation(.easeInOut(duration: 0.18), value: model.activity)
        .contentShape(shape)
        .onHover { model.setHovered($0) }
        // Closing the panel resets the disclosure, so it always reopens compact.
        .onChange(of: model.presentation) { _, new in
            if new == .collapsed { outputExpanded = false }
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { shelf.isDropTargeted },
            set: { targeted in
                shelf.isDropTargeted = targeted
                model.setDragTargeted(targeted)
            }
        )) { providers in
            load(providers)
            return true
        }
    }

    /// File URLs arrive as data representations; loading is async, so hop back
    /// to the main actor before touching the shelf.
    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in model.addFiles?([url]) }
            }
        }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: model.presentation == .collapsed ? 19 : 26, style: .continuous)
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .collapsed: collapsed.padding(.horizontal, 14).frame(height: PillViewModel.collapsedSize.height)
        case .expanded:  expanded.padding(12)
        }
    }

    // MARK: - Collapsed

    @ViewBuilder
    private var collapsed: some View {
        if let activity = model.activity {
            HStack(spacing: 8) {
                Image(systemName: icon(for: activity))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 16)

                if let progress = activity.progress {
                    // A meter reads faster than a number at this size.
                    Meter(value: progress)
                } else {
                    Text(activity.title.isEmpty ? activity.id : activity.title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else {
            resting
        }
    }

    /// The pill at rest: charge and connectivity, nothing else.
    ///
    /// This is what is on screen most of the day, so it carries the two facts
    /// that are always true and cost nothing to know. A machine with no battery
    /// shows connectivity alone; one that can report neither falls back to a
    /// neutral bar rather than inventing a reading.
    @ViewBuilder
    private var resting: some View {
        let mac = battery.mac
        let alert = network.state == .offline || (mac?.isLow ?? false)

        if mac != nil || network.state == .offline {
            HStack(spacing: 8) {
                Image(systemName: mac?.symbol ?? "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text(StatusLine.text(batteryPercent: mac?.percent, network: network.state))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(alert ? .orange : .white)
            .frame(maxWidth: .infinity)
        } else {
            HStack {
                Spacer()
                Capsule().fill(.white.opacity(0.22)).frame(width: 34, height: 4)
                Spacer()
            }
        }
    }

    private func icon(for activity: Activity) -> String {
        switch activity.kind {
        case .audioOutput: return audioIcon
        case .hud:         return volumeIcon(for: activity)
        case .brightness:  return brightnessIcon(for: activity)
        case .screenshot:  return "camera.viewfinder"
        case .calendar:    return "calendar"
        case .timer:       return "timer"
        case .thermal:     return "thermometer.medium"
        case .battery:     return "battery.25"
        case .email:       return "envelope.fill"
        case .nowPlaying:  return "waveform"
        case .network:     return "wifi.slash"
        case .generic:     return "circle.fill"
        }
    }

    /// Mirrors the system's own stepping so the icon reads as familiar.
    private func volumeIcon(for activity: Activity) -> String {
        guard let level = activity.progress else { return "speaker.wave.2.fill" }
        if activity.title == "Muted" || level <= 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// Fills in as it gets brighter, the way the system glyph does.
    private func brightnessIcon(for activity: Activity) -> String {
        (activity.progress ?? 0) < 0.5 ? "sun.min.fill" : "sun.max.fill"
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

    /// One card, in the order the sketches put things: what the machine is
    /// doing, what it is playing, what is parked on the shelf, what is waiting
    /// in the inbox. Everything below that line is secondary and only appears
    /// when it has something to say.
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 9) {
            StatusRow(battery: battery, thermal: thermal, privacy: privacy,
                      network: network, audio: audio,
                      outputExpanded: $outputExpanded,
                      onToggleShare: { model.toggleScreenShare?() })

            if outputExpanded { outputList }

            NowPlayingRow(nowPlaying: nowPlaying,
                          onPlayPause: { model.mediaPlayPause?() },
                          onNext: { model.mediaNext?() },
                          onPrevious: { model.mediaPrevious?() })

            ShelfStrip(shelf: shelf,
                       onTransform: { action, item in model.runTransform?(action, item) },
                       onRemove: { model.removeShelfItem?($0) },
                       onClear: { model.clearShelf?() },
                       onDragStart: { model.beginShelfDrag?() })

            EmailRow(email: email,
                     redacted: privacy.isScreenSharing,
                     onSignIn: { model.connectEmail?() })

            // Neither sketch has a calendar prompt, timer chips or a
            // permission nag in it. While something is playing the panel is
            // the player, the shelf and the inbox — nothing else earns the
            // space. They come back the moment the music stops.
            if nowPlaying.playback == nil { secondary }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var outputList: some View {
        if audio.state.devices.isEmpty {
            Text("No output devices")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 26)
        } else {
            VStack(spacing: 2) {
                ForEach(audio.state.devices) { device in
                    DeviceRow(device: device,
                              isCurrent: device.id == audio.state.current?.id) {
                        model.selectDevice?(device)
                        outputExpanded = false
                    }
                }
            }
        }
    }

    /// Calendar, timers and the one permission prompt. Each hides itself when it
    /// has nothing to offer, so the resting panel stays short, and the whole
    /// group stands down while a player has the panel.
    @ViewBuilder
    private var secondary: some View {
        CalendarRow(calendar: calendar,
                    onRequestAccess: { model.requestCalendarAccess?() },
                    redacted: privacy.isScreenSharing)

        TimerRow(timer: timer,
                 onPomodoro: { model.startPomodoro?() },
                 onStart: { model.startTimer?($0) },
                 onTogglePause: { model.toggleTimerPause?() },
                 onCancel: { model.cancelTimer?() })

        // Shown only while it is actionable. SIP blocks disabling Apple's
        // OSD, so consuming the keys is the only way to replace it, and
        // that needs Accessibility.
        if !hud.isReplacingSystemHUD {
            Button { model.requestAccessibility?() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Replace system volume HUD")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(height: 22)
            }
            .buttonStyle(.plain)
        }
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


/// A slim capsule meter. Fill is drawn as an overlay mask so the track stays a
/// constant width while the value animates.
private struct Meter: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.20))
                Capsule()
                    .fill(.white)
                    .frame(width: max(3, geometry.size.width * value))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.16), value: value)
    }
}
