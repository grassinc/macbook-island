// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pill",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic. No AppKit, no window, no hardware — so it is testable
        // headlessly and fast. Everything that can live here, does.
        .target(name: "PillCore"),

        // The app shell: panel, SwiftUI views, and the event sources that
        // adapt real hardware onto PillCore's protocols.
        .executableTarget(
            name: "Pill",
            dependencies: ["PillCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
            ]
        ),

        // CLT ships no XCTest and no swift-testing (verified: only the private
        // XCTestSupport stub exists). Rather than require a 15 GB Xcode install
        // for an assertion function, the suite is a plain executable with a
        // minimal harness. Run it with: swift run PillCoreTests
        .executableTarget(
            name: "PillCoreTests",
            dependencies: ["PillCore"],
            path: "Tests/PillCoreTests"
        ),
    ]
)
