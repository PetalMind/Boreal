#!/bin/zsh

set -euo pipefail

script_root="${0:A:h}"
compiler="${DAO_SMART_HIGHLIGHT_CXX:-i686-w64-mingw32-g++}"
output="$script_root/DAO_SmartHighlightTool.exe"

if ! command -v "$compiler" >/dev/null 2>&1; then
  print -u2 "Missing compiler: $compiler"
  exit 69
fi

"$compiler" \
  -std=c++17 \
  -O2 \
  -Wall \
  -Wextra \
  -municode \
  -static \
  -static-libgcc \
  -static-libstdc++ \
  "$script_root/src/SmartHighlight.cpp" \
  -o "$output" \
  -luser32 \
  -ladvapi32 \
  -lshell32

print "Built $output"
