// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MPTimer",
    products: [
        .library(
            name: "MPTimer",
            targets: ["MPTimer"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "MPTimer",
            dependencies: [])
    ]
)
