#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_DIR="$SCRIPT_DIR/bin"
SOURCE="$SCRIPT_DIR/src/BorealRuntimeTest.c"
OUTPUT="$OUTPUT_DIR/BorealRuntimeTest.exe"
COMPILER=${CC_WINDOWS:-x86_64-w64-mingw32-gcc}

if ! command -v "$COMPILER" >/dev/null 2>&1; then
    echo "ERROR: Windows cross-compiler '$COMPILER' was not found." >&2
    echo "Install MinGW-w64 or set CC_WINDOWS to a compatible compiler." >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR"
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

echo "Built $OUTPUT"
