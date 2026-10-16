# Graphics capabilities and memory pressure

Automatic renderer selection first checks the game's API, prefix architecture, runtime capabilities and required component files. Its default order is:

| Input to the renderer | Automatic preference |
| --- | --- |
| DirectDraw / Direct3D 1–7 without a wrapper | Wine's built-in compatibility path |
| DirectX 8 | DXVK when both `d3d8.dll` and `d3d9.dll` exist for the prefix architectures; otherwise WineD3D |
| DirectX 9 | DXVK, then WineD3D |
| DirectX 10 | DXVK, then DXMT, then WineD3D |
| DirectX 11 | DXMT, then DXVK, then D3DMetal, then WineD3D |
| DirectX 12 | D3DMetal, then VKD3D-Proton; no unsupported WineD3D fallback |
| OpenGL | Wine's native OpenGL path |

Selected legacy wrappers remain a separate layer. Dd7to9 supplies DirectX 9 to this resolver; dgVoodoo2 and Boreal Legacy Graphics supply DirectX 11. Wrapper activation still validates its actual package and supported input API. Boreal does not install an arbitrary wrapper automatically. Explicit backend choices and enforced game rules remain strict; available game-specific preferences override the default order.

Regular PE imports take precedence over delay imports for automatic API detection when they identify a single API. Diagnostics retain all candidates, distinguish delay imports, and report conflicting regular imports as ambiguous. Dropdown options stay visible and report API, runtime, GPTK or verification constraints. The configuration summary and fullscreen FSR eligibility use the shared resolver with installed runtime payloads.

`GraphicsBackend` identifies the renderer. `WineGraphicsBackend` remains a type alias so existing callers and persisted raw values remain compatible. `EnvironmentConfiguration.graphicsConfiguration` provides the backend, input API and fullscreen FSR configuration shared by prefix setup and process launch.

Runtime features may include a `graphicsCapabilities` dictionary keyed by backend raw value (for example `d3dMetal`). Each entry accepts optional booleans: `metal4`, `hdr`, `upscaling`, `frameGeneration`, `performanceInsights`, `metalHUD`, `gpuCapture`, and `metalSystemTrace`, plus the optional `fullscreenFSRSupport` level (`unsupported`, `candidate`, or `verified`). Missing means unverified; false means unsupported. Metadata must describe the actual packaged backend. Do not derive GPTK capabilities from the Wine version or the runtime's display name.

Apple describes Metal 4 support in GPTK 4: https://developer.apple.com/games/game-porting-toolkit/

These capabilities describe runtime support, not whether a game uses a feature. HDR, upscaling and frame generation require game/runtime integration; Boreal does not invent environment switches for them. Wine fullscreen FSR is a separate launch-time capability: runtime confidence is `declared`, `detected`, or `verified`, while the resolved graphics stack is `unsupported`, `candidate`, or `verified`. DXVK/VKD3D on macOS start as candidates and are not enabled until a concrete runtime path is verified. D3DMetal, DXMT and WineD3D are treated as unsupported until a runtime probe proves otherwise. The user's requested FSR preference is retained when a runtime or renderer cannot use it; only the effective launch configuration is disabled. Optional `WINE_FULLSCREEN_FSR_MODE`, `WINE_FULLSCREEN_FSR_STRENGTH` and `WINE_FULLSCREEN_FSR_CUSTOM_MODE` are emitted only when their capabilities are declared and validated. Launch telemetry uses Metal HUD capability for the resolved backend. Older GPTK imports without explicit capability metadata may use the HUD when the packaged D3DMetal payload is detected; the launch runner strips Xcode/GPUTools diagnostics before starting Wine so that telemetry cannot inherit the debugger's Metal validation layer.

`UpscalingResolver` keeps Wine FSR 1 separate from temporal paths. It detects native game interfaces (DLSS, FSR and XeSS) from game-side libraries, reports an OptiScaler temporal bridge only when its library is present, and reports a possible NGX-to-MetalFX path when a known forwarder or backend metadata is present. No bridge is enabled automatically; candidate and detected states are diagnostic until a macOS smoke test promotes them to verified.

The compatibility configurator exposes `NGX → MetalFX` as a per-game `TemporalUpscalingBridge`. Installing it creates an immutable snapshot under `Components/Upscaling/MetalFXBridge/<GPTK runtime>`, copying GPTK's `nvngx-on-metalfx.dll` as the managed `nvngx.dll` entry point, together with `nvapi64.dll` and an optional `x64-unix/nvngx.so`. The GPTK runtime remains untouched. At launch, only a game that explicitly selected the bridge receives `D3DM_ENABLE_METALFX=1`, a validated component `WINEDLLPATH`, and native NGX/NVAPI DLL overrides. Installation is not treated as verification; the UI remains experimental until a real launch smoke test confirms compatibility.

The overlay samples system-wide RAM, swap (`vm.swapusage`), memory pressure (`kern.memorystatus_vm_pressure_level`) and GPU mapped allocation (`Alloc system memory` in IOAccelerator statistics). GPU allocation shares RAM on Apple Silicon and is not added to RAM usage. Missing measurements display a dash. Driver allocation is not a game's dedicated VRAM usage.

Memory warnings appear only for macOS warning/critical pressure and disappear when the pressure clears or its measurement becomes unavailable. High RAM occupancy and existing swap alone do not trigger warnings. Boreal does not close applications or change game settings. The sysctl exports Dispatch pressure flags, not the kernel's internal level numbers: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c
