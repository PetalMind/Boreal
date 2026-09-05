# Graphics capabilities and memory pressure

`GraphicsBackend` identifies the renderer. `WineGraphicsBackend` remains a type alias so existing callers and persisted raw values remain compatible. `EnvironmentConfiguration.graphicsConfiguration` provides the backend, input API and fullscreen FSR configuration shared by prefix setup and process launch.

Runtime features may include a `graphicsCapabilities` dictionary keyed by backend raw value (for example `d3dMetal`). Each entry accepts optional booleans: `metal4`, `hdr`, `upscaling`, `frameGeneration`, `performanceInsights`, `metalHUD`, `gpuCapture`, and `metalSystemTrace`. Missing means unverified; false means unsupported. Metadata must describe the actual packaged backend. Do not derive GPTK capabilities from the Wine version or the runtime's display name.

Apple describes Metal 4 support in GPTK 4: https://developer.apple.com/games/game-porting-toolkit/

These capabilities describe runtime support, not whether a game uses a feature. HDR, upscaling and frame generation require game/runtime integration; Boreal does not invent environment switches for them. Existing Wine fullscreen FSR remains a separate configuration. Launch telemetry uses Metal HUD capability for the resolved backend instead of the runtime engine label. Existing D3DMetal HUD support supplies a default only when the metadata does not override it.

The overlay samples system-wide RAM, swap (`vm.swapusage`), memory pressure (`kern.memorystatus_vm_pressure_level`) and GPU mapped allocation (`Alloc system memory` in IOAccelerator statistics). GPU allocation shares RAM on Apple Silicon and is not added to RAM usage. Missing measurements display a dash. Driver allocation is not a game's dedicated VRAM usage.

Memory warnings appear only for macOS warning/critical pressure and disappear when the pressure clears or its measurement becomes unavailable. High RAM occupancy and existing swap alone do not trigger warnings. Boreal does not close applications or change game settings. The sysctl exports Dispatch pressure flags, not the kernel's internal level numbers: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c
