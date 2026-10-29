// swift-tools-version: 5.9
import PackageDescription

// No third-party dependencies and no XCTest/Swift Testing: the macOS 26 SDK's
// SwiftUI macros (@State, #Preview) and both test frameworks' macros need Xcode's
// plugins, which the Command Line Tools don't ship. Tests live in the
// `LingTipChecks` executable (`swift run LingTipChecks`), which @testable-imports
// the core library in debug builds.
let package = Package(
    name: "LingTip",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LingTipCore",
            path: "Sources/LingTipCore",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "LingTip",
            dependencies: ["LingTipCore"],
            path: "Sources/LingTip"
        ),
        .executableTarget(
            name: "LingTipChecks",
            dependencies: ["LingTipCore"],
            path: "Sources/LingTipChecks"
        ),
    ]
)
