import SwiftUI
import PillCore

/// Compact top strip: battery, thermal warning, and the screen-share switch.
struct StatusRow: View {
    @ObservedObject var battery: BatteryStore
    @ObservedObject var thermal: ThermalStore
    @ObservedObject var privacy: PrivacyStore
    let onToggleShare: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let mac = battery.mac {
                Label {
                    Text("\(mac.percent)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: mac.symbol).font(.system(size: 10))
                }
                .foregroundStyle(mac.isLow ? .orange : .white.opacity(0.75))
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

            Spacer(minLength: 0)

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
        }
        .frame(height: 18)
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
                Text("TIMER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .kerning(0.8)
                Spacer(minLength: 0)
                chip("Pomodoro", action: onPomodoro)
                chip("5m") { onStart(5 * 60) }
                chip("25m") { onStart(25 * 60) }
            }
        }
        .frame(height: 26)
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
