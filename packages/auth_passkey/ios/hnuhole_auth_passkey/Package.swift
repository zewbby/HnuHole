// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hnuhole_auth_passkey",
    platforms: [.iOS("13.0")],
    products: [.library(name: "hnuhole-auth-passkey", targets: ["hnuhole_auth_passkey"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(name: "hnuhole_auth_passkey", dependencies: [
            .product(name: "FlutterFramework", package: "FlutterFramework")
        ], linkerSettings: [.linkedFramework("AuthenticationServices")]),
        .testTarget(name: "HnuholePasskeyCodecTests", dependencies: ["hnuhole_auth_passkey"])
    ]
)
