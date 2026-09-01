import CoreGraphics
import Foundation

/// Reads and writes display brightness.
///
/// The public IOKit path is read-only on Apple Silicon: `IODisplayParameters`
/// exposes a brightness value, but `IODisplaySetFloatParameter` returns
/// kIOReturnUnsupported (-536870201) on this machine. Verified, not assumed.
///
/// So writing goes through the private DisplayServices framework, loaded with
/// `dlopen` rather than linked, so a future macOS that removes or renames the
/// symbols degrades to "brightness HUD unavailable" instead of failing to launch.
///
/// This carries the same category of risk as MediaRemote: Apple can gate it. The
/// difference is that MediaRemote is *already* gated, whereas DisplayServices
/// currently works. If it stops working the keys are simply not consumed and
/// macOS handles brightness itself.
enum BrightnessController {

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private struct Symbols {
        let get: GetBrightness
        let set: SetBrightness
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ) else { return nil }
        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return Symbols(get: unsafeBitCast(getSymbol, to: GetBrightness.self),
                       set: unsafeBitCast(setSymbol, to: SetBrightness.self))
    }()

    /// Whether brightness control is available at all on this system.
    static var isAvailable: Bool { symbols != nil }

    static func brightness(of display: CGDirectDisplayID = CGMainDisplayID()) -> Double? {
        guard let symbols else { return nil }
        var value: Float = 0
        guard symbols.get(display, &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    static func setBrightness(_ level: Double, on display: CGDirectDisplayID = CGMainDisplayID()) -> Bool {
        guard let symbols else { return false }
        let clamped = Float(min(max(level, 0), 1))
        return symbols.set(display, clamped) == 0
    }
}
