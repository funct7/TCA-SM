// swift-tools-version: 6.1
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "StateMachine",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "StateMachine", targets: ["StateMachine"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.25.5"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.7.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"605.0.0"),
    ],
    targets: [
        .macro(
            name: "StateMachineMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "StateMachine",
            dependencies: [
                "StateMachineMacros",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "CasePaths", package: "swift-case-paths"),
            ]
        ),
        .testTarget(
            name: "StateMachineMacrosTests",
            dependencies: [
                "StateMachineMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        )
    ]
)
