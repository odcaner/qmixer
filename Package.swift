// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Qmixer",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "Qmixer",
            path: "Sources/Qmixer",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
