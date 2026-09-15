#!/bin/sh

set -eu

module_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_directory="$module_root/build"
output="$output_directory/ddraw.dll"

mkdir -p "$output_directory"

exec i686-w64-mingw32-g++ \
    -std=c++20 \
    -O2 \
    -Wall \
    -Wextra \
    -Wpedantic \
    -Wno-cast-function-type \
    -static \
    -static-libgcc \
    -static-libstdc++ \
    -shared \
    -I "$module_root/include" \
    "$module_root/src/blg_d3d11.cpp" \
    "$module_root/src/blg_log.cpp" \
    "$module_root/src/ddraw_proxy.cpp" \
    -o "$output" \
    -lkernel32 \
    -luser32 \
    -luuid \
    -Wl,-Bstatic \
    -lwinpthread \
    -Wl,--kill-at
