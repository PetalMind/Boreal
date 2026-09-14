#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_DIR="$SCRIPT_DIR/bin"
SOURCE="$SCRIPT_DIR/src/BorealRuntimeTest.c"
OUTPUT="$OUTPUT_DIR/BorealRuntimeTest.exe"
PROBE_SOURCE="$SCRIPT_DIR/src/BorealGraphicsProbe.c"
PROBE_DIR="$SCRIPT_DIR/../../BorealRuntimeProbe"
PROBE_OUTPUT_64="$PROBE_DIR/BorealGraphicsProbe.exe"
PROBE_OUTPUT_32="$PROBE_DIR/BorealGraphicsProbe32.exe"
COMPILER=${CC_WINDOWS:-x86_64-w64-mingw32-gcc}
COMPILER_32=${CC_WINDOWS_32:-i686-w64-mingw32-gcc}

if ! command -v "$COMPILER" >/dev/null 2>&1; then
    echo "ERROR: Windows cross-compiler '$COMPILER' was not found." >&2
    echo "Install MinGW-w64 or set CC_WINDOWS to a compatible compiler." >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR" "$PROBE_DIR"
"$COMPILER" \
    -std=c11 \
    -O2 \
    -Wall \
    -Wextra \
    -Werror \
    -mconsole \
    -o "$OUTPUT" \
    "$SOURCE" \
    -luser32

"$COMPILER" \
    -std=c11 \
    -O2 \
    -Wall \
    -Wextra \
    -Werror \
    -mconsole \
    -o "$PROBE_OUTPUT_64" \
    "$PROBE_SOURCE" \
    -ld3d11 \
    -ldxgi

if ! command -v "$COMPILER_32" >/dev/null 2>&1; then
    echo "ERROR: Windows 32-bit cross-compiler '$COMPILER_32' was not found." >&2
    echo "Install MinGW-w64 or set CC_WINDOWS_32 to a compatible compiler." >&2
    exit 2
fi

"$COMPILER_32" \
    -std=c11 \
    -O2 \
    -Wall \
    -Wextra \
    -Werror \
    -mconsole \
    -o "$PROBE_OUTPUT_32" \
    "$PROBE_SOURCE" \
    -ld3d11 \
    -ldxgi

echo "Built $OUTPUT"
echo "Built $PROBE_OUTPUT_64"
echo "Built $PROBE_OUTPUT_32"
