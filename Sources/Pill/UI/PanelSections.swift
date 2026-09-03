import SwiftUI
import PillCore

/// Top strip: charge, connectivity, thermal warning, the screen-share switch,
/// and the output picker.
///
/// The sketch puts battery on the left and OUTPUT on the right of one line, so
/// that is the shape here. Everything between them is conditional and appears
/// only when it has something to report.
struct StatusRow: View {
    @ObservedObject var battery: BatteryStore
    @ObservedObject var thermal: ThermalStore
    @ObservedObject var privacy: PrivacyStore
    @ObservedObject var network: NetworkStore
    @ObservedObject var audio: AudioOutputStore
    @Binding var outputExpanded: Bool
    let onToggleShare: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if let mac = battery.mac {
                Label {
                    Text("\(mac.percent)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: mac.symbol).font(.system(size: 10))
                }
                .foregroundStyle(mac.isLow ? .orange : .white.opacity(0.78))
            }

            // Only worth a word when it is bad news; a permanent "Online" is
            // furniture and would be the first thing the eye learns to skip.
            if network.state == .offline {
                Label {
                    Text("Offline")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: "wifi.slash").font(.system(size: 10))
                }
                .foregroundStyle(.orange)
            }

            ForEach(battery.accessories) { accessory in
                Label {
                    Text("\(accessory.percent)%")
                        .font(.system(size: 11, design: .rounded))
                } icon: {
                    Image(systemName: "magicmouse").font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.6))
                .help(accessory.name)
            }

            // Named so an automatically-applied profile is never a mystery.
            if let profile = network.profile {
                Label {
                    Text(profile.name)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: "wifi").font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.6))
                .help("Network profile")
            }

            // Only shown when it is actionable, so it never becomes furniture.
            if thermal.level.shouldWarn {
                Label {
                    Text(thermal.level.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: "thermometer.high").font(.system(size: 10))
                }
                .foregroundStyle(.orange)
            }

            Spacer(minLength: 4)

            Button(action: onToggleShare) {
                Image(systemName: privacy.isScreenSharing ? "eye.slash.fill" : "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(privacy.isScreenSharing ? .red : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(privacy.isScreenSharing
                  ? "Screen-share mode ON — titles hidden"
                  : (privacy.conferencingAppDetected
                     ? "Screen-share mode (a conferencing app is running)"
                     : "Screen-share mode"))

            OutputChip(audio: audio, expanded: $outputExpanded)
        }
        .frame(height: 20)
    }
}

/// The OUTPUT control from the sketch: a labelled box that names the current
/// device and opens the picker.
private struct OutputChip: View {
    @ObservedObject var audio: AudioOutputStore
    @Binding var expanded: Bool

    @State private var hovering = false

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 5) {
                Text("OUTPUT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .kerning(0.7)
                    .foregroundStyle(.white.opacity(0.45))
                Text(audio.state.current?.name ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(hovering || expanded ? 0.14 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Switch audio output")
        .frame(maxWidth: 190, alignment: .trailing)
    }
}

/// Next event, with a one-click join when the event carries a meeting link.
struct CalendarRow: View {
    @ObservedObject var calendar: CalendarStore
    let onRequestAccess: () -> Void
    let redacted: Bool

    var body: some View {
        if let event = calendar.nextEvent {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                Text(redacted ? "Event" : event.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(calendar.countdown)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
                if let link = event.videoCallURL {
                    Button("Join") { NSWorkspace.shared.open(link) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(Capsule().fill(.blue.opacity(0.85)))
                }
            }
            .frame(height: 22)
        } else if !calendar.accessGranted && !calendar.accessDenied {
            Button(action: onRequestAccess) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 10))
                    Text("Show my next event")
                        .font(.system(size: 11, design: .rounded))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .frame(height: 22)
        }
    }
}

/// Pomodoro and quick countdowns.
struct TimerRow: View {
    @ObservedObject var timer: TimerStore
    let onPomodoro: () -> Void
    let onStart: (TimeInterval) -> Void
    let onTogglePause: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let running = timer.timer {
                Image(systemName: "timer").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Text(CountdownTimer.format(timer.remaining))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let phase = timer.phase {
                    Text(phase.label)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                pill(running.isPaused ? "play.fill" : "pause.fill", action: onTogglePause)
                pill("xmark", action: onCancel)
            } else {
                Text("Timer")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer(minLength: 0)
                chip("Pomodoro", action: onPomodoro)
                chip("5m") { onStart(5 * 60) }
                chip("25m") { onStart(25 * 60) }
            }
        }
        .frame(height: 24)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

/// What is currently making sound.
///
/// Laid out as the sketch draws it: artwork on the left, title and elapsed time
/// on one line, the scrubber under them, transport centred beneath. It degrades
/// in two steps — full transport for a player we can script, the track name for
/// one we can only read, the app name otherwise. Every step is truthful about
/// what it knows.
struct NowPlayingRow: View {
    @ObservedObject var nowPlaying: NowPlayingStore
    @StateObject private var artwork = ArtworkLoader()
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void

    var body: some View {
        if let playback = nowPlaying.playback {
            player(playback)
        } else if let source = nowPlaying.source {
            simple(source)
        }
    }

    // MARK: Full player

    /// The hero of the panel whenever something is playing, laid out as drawn:
    /// the app name over a large cover, the track beside it, elapsed time at the
    /// right, a full-width scrubber, and the transport centred underneath.
    private func player(_ playback: MediaPlayback) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(nowPlaying.source?.name ?? "Now Playing")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 12) {
                artworkView

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(playback.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(playback.positionText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Two lines rather than the sketch's single "Love by Him":
                    // real track names are long, and on one line the artist is
                    // the half that gets truncated away.
                    Text("by \(playback.artist)")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer(minLength: 0)

                    scrubber(playback.progress)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        control("backward.fill", size: 13, action: onPrevious)
                        control(playback.isPlaying ? "pause.fill" : "play.fill", size: 17, action: onPlayPause)
                        control("forward.fill", size: 13, action: onNext)
                        Spacer(minLength: 0)
                        Text(playback.durationText)
                            .font(.system(size: 10, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .padding(.top, 4)
                }
                .frame(height: 82)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .onAppear { artwork.load(playback.artworkURL) }
        .onChange(of: playback.artworkURL) { _, url in artwork.load(url) }
    }

    private var artworkView: some View {
        Group {
            if let image = artwork.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                // A neutral placeholder, so the layout does not jump when the
                // download lands.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.35)))
            }
        }
        .frame(width: 82, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func scrubber(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.white.opacity(0.85))
                    .frame(width: max(2, geometry.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 0.9), value: progress)
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 34, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Fallback

    private func simple(_ source: AudioSource) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            if let track = nowPlaying.track {
                Text(track)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1)
                Text(source.name)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            } else {
                Text(source.name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1)
                Text("playing")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }
}


/// Screenshot, recording and appearance — one click each, from the panel.
struct QuickActionsRow: View {
    @ObservedObject var actions: QuickActionsStore
    let onScreenshot: () -> Void
    let onRecord: () -> Void
    let onAppearance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                action("viewfinder", "Capture a region", tint: .white.opacity(0.85), do: onScreenshot)
                action(actions.isRecording ? "stop.fill" : "record.circle",
                       actions.isRecording ? "Stop recording" : "Record the screen",
                       tint: actions.isRecording ? .red : .white.opacity(0.85),
                       do: onRecord)
                action(actions.isDark ? "sun.max.fill" : "moon.fill",
                       actions.isDark ? "Switch to light" : "Switch to dark",
                       tint: .white.opacity(0.85), do: onAppearance)
                Spacer(minLength: 0)
                if actions.isRecording {
                    Text("Recording")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            if let error = actions.lastError {
                Text(error)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private func action(_ symbol: String, _ help: String, tint: Color,
                        do perform: @escaping () -> Void) -> some View {
        QuickActionButton(symbol: symbol, help: help, tint: tint, perform: perform)
    }
}

private struct QuickActionButton: View {
    let symbol: String
    let help: String
    let tint: Color
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(hovering ? 0.16 : 0.07))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
