# Default Steam client: steam-on-m1-wine 0.6

When `Steam on M1 Wine.app` (bundle ID `com.github.notpop.steam-on-m1-wine`) is installed in `~/Applications` or `/Applications`, Boreal uses it for Steam sign-in, installation, launch, and removal. Without that app, the existing managed/native Steam paths remain available.

The integration discovers the upstream repository from the app's generated `Contents/MacOS/launcher`. It reads library metadata from the v0.6 default prefix `~/.wine-steam`, including Windows drive mappings in `libraryfolders.vdf`. A game is installed only when its manifest has the FullyInstalled flag and its directory exists. Existing Boreal Steam environments are preserved; their installation records do not override the selected external client's manifests.

Boreal reuses the installed `scripts/launch-steam.sh` in memory, replacing its relative common-helper import, forwarding Steam arguments, and omitting the global Wine process reset and Chromium lock deletion. The remaining upstream setup, wrapper repair, DXMT overrides, Wine selection and virtual desktop behavior remain owned by steam-on-m1-wine. An incompatible script structure produces an actionable error instead of falling back to another client. No upstream file is modified.

Play invokes `steam.exe -applaunch <AppID>` through that launcher. Installation and removal forward `steam://install/<AppID>` and `steam://uninstall/<AppID>`. Additional game arguments are passed as separate process arguments. Boreal does not create, initialize, or configure another prefix for this client. The launch is a handoff to Steam: acceptance by the launcher does not prove the game is running, and these external sessions do not use Boreal's managed process monitoring, overlay or Stop control. Steam owns their lifecycle.

Logs: `~/Library/Logs/Boreal/steam-on-m1-wine-launcher.log` and `steam-on-m1-wine.log`.

Validation: macOS Debug build; integration verification of the installed v0.6 script with a substituted Wine command, covering open, play, install, uninstall, virtual desktop and literal argument forwarding. No live game session was started during verification.

## Sacred 2 Remaster (Steam 3906660)

Boreal 1.0.15 routes Play for this AppID to a private Steam prefix at
`<Boreal support>/ExternalSteam/3906660/prefix`, paired with an installed,
verified D3DMetal runtime. The selected host is recorded beside the prefix;
a changed host is rejected instead of silently rewriting the environment.
The default steam-on-m1-wine client remains responsible for other games.

The private prefix is initialized from scratch. Only Steam program executables,
DLLs, static client assets, code package manifests and library paths are read
from the installed client. Its account configuration, userdata, browser caches,
registry, login state and authentication files are never copied. First use
therefore requires sign-in in the separate Steam window. Game files stay in the
existing external Steam library; this is still a Steam `-applaunch 3906660`
launch, not direct execution of the game.

DXGI, D3D11 and D3D12 are forced to the selected host's builtin D3DMetal
implementation as a single stack. The private client retains the CEF wrapper
and disables Steam overlay injection. Its log is
`<Boreal support>/ExternalSteam/3906660/launch.log`.

The original failure's minidumps both identify `TheForge_OS.dll + 0x130793`,
exception `0xc0000005`, following rejected `IWineDXGIAdapter` queries from
DXMT's DXGI. A separate fresh-prefix probe with the selected D3DMetal runtime
successfully created a DXGI factory, enumerated an adapter and created a D3D12
device at feature level 12.0 (all HRESULTs `S_OK`). This verifies graphics device
initialization; it does not establish complete game compatibility or a passed
gameplay session.

### Steam startup on the GPTK Wine 7.7 host

The local GPTK host reports Wine 7.7 even with a newer D3DMetal payload. The
October 2026 Steam client additionally requires two compatibility paths:

- `BCRYPT_RNG_ALG_HANDLE`: normalize that Windows pseudo-handle to the host's
  existing system-preferred RNG call. Real algorithm handles and error returns
  retain the original implementation.
- `QueryUnbiasedInterruptTimePrecise`: supply the missing lookup through a
  companion DLL calling `QueryUnbiasedInterruptTime`, matching the underlying
  unbiased-clock implementation used by current Wine. The old API-set mapping
  otherwise resolves this module name to a kernelbase lacking that export.

`BorealSteamCompatibility.dll` is a version-API proxy placed only in the private
Steam directory and its CEF directories. It forwards version APIs to the system
DLL and qualifies the old Wine function prologues before installing process-local
compatibility hooks. All other procedure lookups retain their original paths.
`BorealRealtimeCompatibility.dll` lives only in that prefix's system32. Receipts
prevent replacing an unrelated pre-existing library. No host/runtime bundle or
shared Steam installation is patched.

Rebuild these two Windows DLLs with
`bash BorealRuntimeProbe/build-steam-compatibility.sh`. The companion integration
probe is `BorealRuntimeProbe/SteamD3DMetalProbe.c`; link with
`-ld3d12 -ldxgi -ldxguid -lbcrypt -lversion`. The verified run passed real-time
module/function resolution, monotonic clock behavior, version-API forwarding,
pseudo-handle/system-preferred/real-handle RNG calls, invalid-call error behavior,
and DXGI/D3D12 device initialization in one process. The private Steam client then
reported `BrowserReady` at 21:03:35 on 2026-10-16. Full game launch still requires
sign-in to that independently initialized client.
