// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "OnnxRuntimeWatch",
    platforms: [
        .watchOS("26.1"),
    ],
    products: [
        .library(
            name: "onnxruntime_watch",
            type: .static,
            targets: ["OnnxRuntimeWatchBindings"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "onnxruntime_watch_binary",
            url: "https://github.com/tryAGI/OnnxRuntimeWatch/releases/download/v0.1.0/OnnxRuntimeWatch.xcframework.zip",
            checksum: "3c5cd9abd30910a664fa37fa48962da3bfaca7a200051ad897847075253d01d8"
        ),
        .target(
            name: "OnnxRuntimeWatchBindings",
            dependencies: ["onnxruntime_watch_binary"],
            path: "objectivec",
            exclude: [
                "ReadMe.md",
                "format_objc.sh",
                "test",
                "docs",
                "ort_checkpoint.mm",
                "ort_checkpoint_internal.h",
                "ort_training_session_internal.h",
                "ort_training_session.mm",
                "include/ort_checkpoint.h",
                "include/ort_training_session.h",
                "include/onnxruntime_training.h",
            ],
            cxxSettings: [
                .headerSearchPath("c_headers"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
