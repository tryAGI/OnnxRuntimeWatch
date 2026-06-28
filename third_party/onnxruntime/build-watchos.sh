#!/usr/bin/env bash
set -euo pipefail

# Experimental ONNX Runtime watchOS builder for Advantage wake-word models.
#
# Official ONNX Runtime Apple builds support iOS/macOS, but not watchOS. This
# script keeps the repo-side build contract explicit and repeatable while we
# carry the watchOS patch locally. It builds a reduced CPU-only ORT containing
# only the operators required by:
#   - melspectrogram.onnx
#   - embedding_model.onnx
#   - advantage.onnx
#
# Outputs:
#   vendor/OnnxRuntimeWatch.xcframework
#
# Usage:
#   third_party/onnxruntime/build-watchos.sh
#   ORT_VERSION=v1.24.2 third_party/onnxruntime/build-watchos.sh

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

ORT_VERSION="${ORT_VERSION:-v1.24.2}"
WATCHOS_MIN="${WATCHOS_MIN:-9.0}"
CONFIGURATION="${CONFIGURATION:-MinSizeRel}"
ORT_REFRESH="${ORT_REFRESH:-0}"

WORK_DIR="$REPO_ROOT/third_party/onnxruntime/work"
SOURCE_DIR="$WORK_DIR/onnxruntime-$ORT_VERSION"
BUILD_DIR="$WORK_DIR/build"
DIST_DIR="$WORK_DIR/dist"
HEADERS_DIR="$WORK_DIR/Headers"
OUT_DIR="$REPO_ROOT/vendor"
OUT_XCFRAMEWORK="$OUT_DIR/OnnxRuntimeWatch.xcframework"
OPS_CONFIG="$REPO_ROOT/third_party/onnxruntime/required_operators.config"
PYTHON_VENV_DIR="$WORK_DIR/python-venv"

ensure_python_dependencies() {
    mkdir -p "$WORK_DIR"

    if [[ ! -x "$PYTHON_VENV_DIR/bin/python" ]]; then
        python3 -m venv --system-site-packages "$PYTHON_VENV_DIR"
    fi

    if ! "$PYTHON_VENV_DIR/bin/python" -c 'import flatbuffers' >/dev/null 2>&1; then
        "$PYTHON_VENV_DIR/bin/python" -m pip install --quiet 'flatbuffers>=25.2.10'
    fi
    "$PYTHON_VENV_DIR/bin/python" - <<'PY'
import flatbuffers
PY

    export PATH="$PYTHON_VENV_DIR/bin:$PATH"
}

clone_source() {
    if [[ -d "$SOURCE_DIR/.git" ]]; then
        if [[ "$ORT_REFRESH" == "1" ]]; then
            git -C "$SOURCE_DIR" fetch --tags --quiet
        fi
        git -C "$SOURCE_DIR" checkout --quiet "$ORT_VERSION"
        return
    fi

    mkdir -p "$WORK_DIR"
    git clone --depth 1 --branch "$ORT_VERSION" https://github.com/microsoft/onnxruntime.git "$SOURCE_DIR"
}

patch_source() {
    local detect_file="$SOURCE_DIR/cmake/detect_onnxruntime_target_platform.cmake"
    local mlas_file="$SOURCE_DIR/cmake/onnxruntime_mlas.cmake"

    python3 - "$detect_file" "$mlas_file" <<'PY'
from pathlib import Path
import sys

detect_path = Path(sys.argv[1])
detect_text = detect_path.read_text(encoding="utf-8")
detect_patch = '''\
    if(onnxruntime_target_platform STREQUAL "arm64_32")
      # watchOS device builds use the arm64_32 ABI but need the same MLAS
      # ARM64 kernel source selection as other Apple ARM64 platforms.
      set(onnxruntime_target_platform "ARM64")
    endif()
'''
detect_needle = "    endif()\n  else()\n    set(onnxruntime_target_platform ${CMAKE_SYSTEM_PROCESSOR})\n"
if detect_patch not in detect_text:
    detect_text = detect_text.replace(
        detect_needle,
        "    endif()\n" + detect_patch + "  else()\n    set(onnxruntime_target_platform ${CMAKE_SYSTEM_PROCESSOR})\n",
        1,
    )
    detect_path.write_text(detect_text, encoding="utf-8")

mlas_path = Path(sys.argv[2])
mlas_text = mlas_path.read_text(encoding="utf-8")
mlas_needle = '''\
        elseif (OSX_ARCH STREQUAL "arm64e")
            set(ARM64 TRUE)
        elseif (OSX_ARCH STREQUAL "arm")
'''
mlas_patch = '''\
        elseif (OSX_ARCH STREQUAL "arm64e")
            set(ARM64 TRUE)
        elseif (OSX_ARCH STREQUAL "arm64_32")
            # watchOS device ABI still runs on ARM64-class cores.
            set(ARM64 TRUE)
        elseif (OSX_ARCH STREQUAL "arm")
'''
if mlas_patch not in mlas_text:
    mlas_text = mlas_text.replace(mlas_needle, mlas_patch, 1)
    mlas_path.write_text(mlas_text, encoding="utf-8")
PY
}

build_one() {
    local sdk="$1"
    local arch="$2"
    local name="$3"
    local platform_flag="$4"
    local min_flag="$5"

    local sdk_path
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

    local build_root="$BUILD_DIR/$name"
    rm -rf "$build_root"

    "$SOURCE_DIR/build.sh" \
        --config "$CONFIGURATION" \
        --use_xcode \
        --build_shared_lib \
        --minimal_build extended \
        --compile_no_warning_as_error \
        --no_kleidiai \
        --no_sve \
        --disable_ml_ops \
        --disable_exceptions \
        --include_ops_by_config "$OPS_CONFIG" \
        --skip_tests \
        --parallel \
        --target onnxruntime \
        --build_dir "$build_root" \
        --cmake_extra_defines \
            CMAKE_SYSTEM_NAME="$platform_flag" \
            CMAKE_OSX_SYSROOT="$sdk_path" \
            CMAKE_OSX_ARCHITECTURES="$arch" \
            CMAKE_OSX_DEPLOYMENT_TARGET="$WATCHOS_MIN" \
            CMAKE_C_FLAGS="$min_flag -Wno-error=asm-operand-widths" \
            CMAKE_CXX_FLAGS="$min_flag -Wno-error=asm-operand-widths" \
            CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
            CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
            CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
            CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
            onnxruntime_ENABLE_CPUINFO=OFF \
            FLATBUFFERS_BUILD_FLATC=OFF \
            FLATBUFFERS_BUILD_FLATHASH=OFF \
            FLATBUFFERS_BUILD_TESTS=OFF \
            FLATBUFFERS_INSTALL=OFF

    local dylib
    dylib="$(find "$build_root" \( -name 'libonnxruntime.*.dylib' -o -name 'libonnxruntime.dylib' \) -print -quit)"
    if [[ -z "$dylib" || ! -f "$dylib" ]]; then
        echo "ONNX Runtime dylib not found for $name" >&2
        exit 1
    fi

    mkdir -p "$DIST_DIR/$name"
    cp "$dylib" "$DIST_DIR/$name/libonnxruntime.dylib"
    install_name_tool -id @rpath/libonnxruntime.dylib "$DIST_DIR/$name/libonnxruntime.dylib"
}

merge_universal() {
    local output="$1"
    shift
    mkdir -p "$(dirname "$output")"
    lipo -create "$@" -output "$output"
}

prepare_headers() {
    rm -rf "$HEADERS_DIR"
    mkdir -p "$HEADERS_DIR"
    cp -R "$SOURCE_DIR/include/onnxruntime/core/session/"*.h "$HEADERS_DIR/"
}

create_xcframework() {
    merge_universal "$DIST_DIR/watchos-universal/libonnxruntime.dylib" \
        "$DIST_DIR/watchos-arm64_32/libonnxruntime.dylib" \
        "$DIST_DIR/watchos-arm64/libonnxruntime.dylib"

    merge_universal "$DIST_DIR/watchsim-universal/libonnxruntime.dylib" \
        "$DIST_DIR/watchsim-arm64/libonnxruntime.dylib" \
        "$DIST_DIR/watchsim-x86_64/libonnxruntime.dylib"

    mkdir -p "$OUT_DIR"
    rm -rf "$OUT_XCFRAMEWORK"
    xcodebuild -create-xcframework \
        -library "$DIST_DIR/watchos-universal/libonnxruntime.dylib" -headers "$HEADERS_DIR" \
        -library "$DIST_DIR/watchsim-universal/libonnxruntime.dylib" -headers "$HEADERS_DIR" \
        -output "$OUT_XCFRAMEWORK"
}

main() {
    if [[ ! -f "$OPS_CONFIG" ]]; then
        echo "Required operators config missing: $OPS_CONFIG" >&2
        exit 1
    fi

    clone_source
    patch_source
    ensure_python_dependencies
    prepare_headers

    rm -rf "$BUILD_DIR" "$DIST_DIR"
    mkdir -p "$BUILD_DIR" "$DIST_DIR"

    build_one watchos arm64_32 watchos-arm64_32 watchOS "-mwatchos-version-min=$WATCHOS_MIN"
    build_one watchos arm64 watchos-arm64 watchOS "-mwatchos-version-min=$WATCHOS_MIN"
    build_one watchsimulator arm64 watchsim-arm64 watchOS "-mwatchos-simulator-version-min=$WATCHOS_MIN"
    build_one watchsimulator x86_64 watchsim-x86_64 watchOS "-mwatchos-simulator-version-min=$WATCHOS_MIN"

    create_xcframework

    echo "Built $OUT_XCFRAMEWORK"
    echo "Next: zip the XCFramework and update Package.swift with its checksum."
}

main "$@"
