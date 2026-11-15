// swift-tools-version: 5.9
import PackageDescription

var dependencies: [Package.Dependency] = []
var uiDependencies: [Target.Dependency] = ["FramesCore"]

// Die Player-Engine gibt es nur für Apple-Plattformen. Unter Linux, wo die Tests des Kerns laufen,
// bleibt sie außen vor.
#if !os(Linux)
dependencies.append(.package(url: "https://github.com/superuser404notfound/AetherEngine", from: "7.67.0"))
uiDependencies.append(.product(name: "AetherEngine", package: "AetherEngine"))
#endif

let package = Package(
    name: "Frames",
    defaultLocalization: "de",
    platforms: [.iOS("18.0"), .tvOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "FramesCore", targets: ["FramesCore"]),
        .library(name: "FramesUI", targets: ["FramesUI"]),
    ],
    dependencies: dependencies,
    targets: [
        // Stremio-Konto, Addon-Protokoll, Stream-Auswertung. Ohne UI, läuft auch unter Linux.
        .target(name: "FramesCore"),
        // Signal-Design, alle Screens und der Player in SwiftUI.
        .target(
            name: "FramesUI",
            dependencies: uiDependencies,
            resources: [.process("Resources")]
        ),
        // Prüft die Anbindung gegen die echten Server: swift run frames-check
        .executableTarget(name: "frames-check", dependencies: ["FramesCore"]),
        .testTarget(
            name: "FramesCoreTests",
            dependencies: ["FramesCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
