# ONNX Runtime watchOS build

This folder contains the build contract for the reduced watchOS ONNX Runtime
binary target used by `OnnxRuntimeWatch`.

Microsoft's published SwiftPM package currently provides iOS/macOS binaries,
not watchOS. This folder builds the watchOS runtime published as this
repository's `OnnxRuntimeWatch.xcframework.zip` release asset.

## Build

```bash
third_party/onnxruntime/build-watchos.sh
```

The script targets ONNX Runtime `v1.24.2` by default and emits:

```text
vendor/OnnxRuntimeWatch.xcframework
```

It builds a reduced CPU-only runtime using `required_operators.config`, which is
derived from the bundled wake-word ONNX files:

- `melspectrogram.onnx`
- `embedding_model.onnx`
- `advantage.onnx`

The generated XCFramework is intentionally gitignored because it is a native
binary build product.

## Integration

- `Package.swift` wraps the release `OnnxRuntimeWatch.xcframework` and builds
  the Objective-C ORT bindings as `OnnxRuntimeWatchBindings`.
- Advantage uses the official Microsoft package on iOS/macOS and this wrapper
  on watchOS.
- Wake-word source gates on `canImport(OnnxRuntimeBindings) ||
  canImport(OnnxRuntimeWatchBindings)`, so watchOS selects `.onnxRuntime`
  automatically when the local package is present.
- The build script rewrites the dylib install name to
  `@rpath/libonnxruntime.dylib`.

## Verification

```bash
swift package dump-package
```

Consumers should verify their app embeds `libonnxruntime.dylib` for watchOS.
