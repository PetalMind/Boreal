#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
"${MINGW_CC32:-i686-w64-mingw32-gcc}" -O2 -Wall -Wextra -Werror -static-libgcc -municode DrakensangSteamTicket.c -o BorealDrakensangTicket.exe
"${MINGW_CC:-x86_64-w64-mingw32-gcc}" -shared -O2 -Wall -Wextra -Werror -static-libgcc DrakensangCursor.c DrakensangCursor.def -o BorealDrakensangCursor.dll -luser32 -Wl,--dynamicbase -Wl,--nxcompat
