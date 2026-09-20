// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleContactsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GoogleContactsKit", targets: ["GoogleContactsKit"])
    ],
    targets: [
        .target(name: "GoogleContactsKit"),
        .testTarget(
            name: "GoogleContactsKitTests",
            dependencies: ["GoogleContactsKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
