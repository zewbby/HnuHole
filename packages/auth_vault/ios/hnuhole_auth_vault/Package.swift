// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hnuhole_auth_vault",
    platforms: [.iOS("13.0")],
    products: [.library(name: "hnuhole-auth-vault", targets: ["hnuhole_auth_vault"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(name: "hnuhole_auth_vault", dependencies: [
            .product(name: "FlutterFramework", package: "FlutterFramework")
        ], linkerSettings: [.linkedFramework("Security")])
    ]
)
