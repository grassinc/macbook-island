import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ o: TimeInterval) -> Date { t0.addingTimeInterval(o) }

func runWidgetTests(_ r: TestRunner) {

    // MARK: Countdown / Pomodoro

    r.test("a countdown reports the time left") { r in
        let timer = CountdownTimer(duration: 300, startedAt: t0)
        r.expectEqual(timer.remaining(at: at(60)), 240, "five minutes less one")
    }

    r.test("a countdown stops at zero rather than going negative") { r in
        let timer = CountdownTimer(duration: 60, startedAt: t0)
        r.expectEqual(timer.remaining(at: at(90)), 0, "clamped at zero")
        r.expect(timer.isFinished(at: at(90)), "reports finished")
        r.expect(timer.isFinished(at: at(30)) == false, "not finished early")
    }

    // A paused timer must not bleed away while the user is not looking.
    r.test("a paused countdown holds its remaining time") { r in
        var timer = CountdownTimer(duration: 300, startedAt: t0)
        timer.pause(at: at(60))
        r.expectEqual(timer.remaining(at: at(600)), 240, "time does not run while paused")
    }

    r.test("resuming continues from where it paused") { r in
        var timer = CountdownTimer(duration: 300, startedAt: t0)
        timer.pause(at: at(60))
        timer.resume(at: at(600))
        r.expectEqual(timer.remaining(at: at(660)), 180, "another minute elapsed after resuming")
    }

    r.test("countdowns format as minutes and seconds") { r in
        r.expectEqual(CountdownTimer.format(0), "0:00", "zero")
        r.expectEqual(CountdownTimer.format(9), "0:09", "seconds are padded")
        r.expectEqual(CountdownTimer.format(65), "1:05", "a minute and change")
        r.expectEqual(CountdownTimer.format(1500), "25:00", "a pomodoro")
        r.expectEqual(CountdownTimer.format(3600), "60:00", "an hour stays in minutes")
    }

    r.test("pomodoro alternates work and breaks, with a long break every fourth") { r in
        r.expect(PomodoroCycle.phase(afterCompleted: 0) == .work, "starts with work")
        r.expect(PomodoroCycle.phase(afterCompleted: 1) == .shortBreak, "break after one work block")
        r.expect(PomodoroCycle.phase(afterCompleted: 2) == .work, "back to work")
        r.expect(PomodoroCycle.phase(afterCompleted: 7) == .longBreak, "long break after the fourth work block")
    }

    // MARK: Thermal

    r.test("thermal levels only warn when they matter") { r in
        r.expect(ThermalLevel.nominal.shouldWarn == false, "nominal is silent")
        r.expect(ThermalLevel.fair.shouldWarn == false, "fair is silent")
        r.expect(ThermalLevel.serious.shouldWarn, "serious warns")
        r.expect(ThermalLevel.critical.shouldWarn, "critical warns")
    }

    r.test("every thermal level has a label") { r in
        for level in ThermalLevel.allCases { r.expect(level.label.isEmpty == false, "\(level) labelled") }
    }

    // MARK: Battery

    r.test("battery reports a whole percentage") { r in
        let battery = BatteryState(level: 0.494, isCharging: false, source: .internalBattery, name: "MacBook Air")
        r.expectEqual(battery.percent, 49, "rounds to a whole number")
    }

    r.test("a low battery is only low when it is not charging") { r in
        let draining = BatteryState(level: 0.15, isCharging: false, source: .internalBattery, name: "Mac")
        let charging = BatteryState(level: 0.15, isCharging: true, source: .internalBattery, name: "Mac")
        r.expect(draining.isLow, "15% and draining is low")
        r.expect(charging.isLow == false, "15% but charging is not an alarm")
    }

    r.test("battery icon reflects the level") { r in
        func symbol(_ level: Double, charging: Bool = false) -> String {
            BatteryState(level: level, isCharging: charging, source: .internalBattery, name: "m").symbol
        }
        r.expectEqual(symbol(1.0), "battery.100", "full")
        r.expectEqual(symbol(0.5), "battery.50", "half")
        r.expectEqual(symbol(0.05), "battery.0", "nearly empty")
        r.expectEqual(symbol(0.5, charging: true), "battery.100.bolt", "charging shows a bolt")
    }
}
