// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MacGoldTrader",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MacGoldTrader", targets: ["MacGoldTrader"])
    ],
    targets: [
        .executableTarget(
            name: "MacGoldTrader"
        )
    ]
)
