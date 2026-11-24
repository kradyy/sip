// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sip",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic: scheduling, XP, streaks, achievements. No AppKit, fully testable.
        .target(name: "SipCore"),
        .executableTarget(
            name: "Sip",
            dependencies: ["SipCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SipCoreTests", dependencies: ["SipCore"]),
    ]
)
