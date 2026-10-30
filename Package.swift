// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TomatoBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TomatoBar", targets: ["TomatoBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin", exact: "5.0.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
        .package(url: "https://github.com/ReactKit/SwiftState", branch: "swift/5.0")
    ],
    targets: [
        .executableTarget(
            name: "TomatoBar",
            dependencies: [
                "LaunchAtLogin",
                "KeyboardShortcuts",
                "SwiftState"
            ],
            path: "TomatoBar",
            exclude: [
                "Info.plist",
                "TomatoBar.entitlements",
                "Assets.xcassets"
            ],
            resources: [
                .process("en.lproj"),
                .process("zh-Hans.lproj"),
                .process("ko.lproj")
            ]
        )
    ]
)
