// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeCreditWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeCreditWidget",
            path: "Sources/ClaudeCreditWidget",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
