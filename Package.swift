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

        .testTarget(name: "PillCoreTests", dependencies: ["PillCore"]),
    ]
)
