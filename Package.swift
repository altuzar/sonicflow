// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SonicFlow",
    platforms: [
        // 14.2 is the floor for the AudioObjectID-per-process API
        // (kAudioHardwarePropertyProcessObjectList et al.).
        .macOS("14.2")
    ],
    products: [
        .executable(name: "SonicFlow", targets: ["SonicFlow"])
    ],
    targets: [
        .executableTarget(
            name: "SonicFlow",
            path: "Sources/SonicFlow",
            exclude: [
                "Resources/Info.plist",
                "Resources/SonicFlow.entitlements"
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
