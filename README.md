# OnnxRuntimeWatch

SwiftPM wrapper for a reduced watchOS ONNX Runtime build used by the Advantage
wake-word detector.

The package exposes `onnxruntime_watch` with the `OnnxRuntimeWatchBindings`
module. The native `OnnxRuntimeWatch.xcframework` is distributed as a GitHub
release asset so consumers do not rebuild ONNX Runtime during normal package
resolution.

## Usage

```swift
.package(url: "https://github.com/tryAGI/OnnxRuntimeWatch", exact: "0.1.0")
```

## Rebuilding OnnxRuntimeWatch.xcframework

Use the manual **Release XCFramework** GitHub Actions workflow for normal binary
refreshes. It rebuilds `vendor/OnnxRuntimeWatch.xcframework`, zips the
framework as the archive root, computes the SwiftPM checksum, and publishes the
release asset.

The reduced ONNX Runtime watchOS build script and operator config are under
`third_party/onnxruntime/`:

```bash
third_party/onnxruntime/build-watchos.sh
```

Release artifacts must be zipped with the XCFramework directory as the archive
root:

```bash
ditto -c -k --sequesterRsrc --keepParent vendor/OnnxRuntimeWatch.xcframework OnnxRuntimeWatch.xcframework.zip
swift package compute-checksum OnnxRuntimeWatch.xcframework.zip
```
