// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "rated",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "rated", targets: ["rated"])
    ],
    targets: [
        .executableTarget(
            name: "rated"
        )
    ]
)
