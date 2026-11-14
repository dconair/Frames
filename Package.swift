// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Frames",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FramesCore", targets: ["FramesCore"]),
        .library(name: "FramesUI", targets: ["FramesUI"]),
    ],
    targets: [
        // Stremio-Konto, Addon-Protokoll, Stream-Auswertung. Ohne UI, läuft auch unter Linux.
        .target(name: "FramesCore"),
        // Signal-Design und alle Screens in SwiftUI.
        .target(
            name: "FramesUI",
            dependencies: ["FramesCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FramesCoreTests",
            dependencies: ["FramesCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
