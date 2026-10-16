#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
"${MINGW_CC:-/opt/homebrew/bin/x86_64-w64-mingw32-gcc}" -shared -O2 -static-libgcc SteamCompatibility.c SteamCompatibility.def -o BorealSteamCompatibility.dll -Wl,--dynamicbase -Wl,--nxcompat
"${MINGW_CC:-/opt/homebrew/bin/x86_64-w64-mingw32-gcc}" -shared -O2 -static-libgcc RealtimeCompatibility.c RealtimeCompatibility.def -o BorealRealtimeCompatibility.dll -Wl,--dynamicbase -Wl,--nxcompat
