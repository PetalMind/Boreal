# Boreal Legacy Graphics v0.1

This module is the first, intentionally narrow milestone of the Sacred compatibility work.

It builds an x86 Windows PE `ddraw.dll` that:

- supplies a synthetic `IDirectDraw7`/`IDirect3D7` path instead of entering Wine's
  legacy DDraw renderer;
- wraps `IDirectDraw7`, `IDirect3D7`, and `IDirect3DDevice7` COM interfaces;
- captures the DirectDraw, surface, D3D7 and D3DDevice7 state used by Sacred;
- creates a D3D11 device, swap chain, depth buffer and shader pipeline through
  the selected Wine graphics runtime (DXMT in the Boreal Sacred profile);
- supports the first real draw path: `XYZRHW + diffuse + TEX1/TEX2`, indexed or
  non-indexed primitives, alpha blending, depth state, surface `Lock/Unlock`,
  CPU texture caching and `Present`. Sacred defaults to a DXMT-safe vertex-baked
  texture mode: real cached texels are sampled on the CPU into diffuse vertex
  colors, while D3D11 performs the geometry, alpha, depth and presentation
  work without entering the DXMT shader-resource sampling path.
- uses a per-scene dynamic vertex/index ring with `WRITE_NO_OVERWRITE` after
  the first upload, avoiding a DXMT synchronization for every small draw;
- shares active CPU texels with the texture cache instead of copying the full
  image on every material activation;
- reuses the temporary vertex/index conversion buffers across Sacred's many
  small submissions and caches the finite blend/depth/rasterizer state set;
- uses a direct four-vertex quad path for Sacred's dominant transformed
  `TRIANGLESTRIP` submissions, avoiding a temporary strip-index allocation
  while preserving the same six triangle-list indices;
- coalesces consecutive `D3DPT_TRIANGLELIST` submissions with identical texture
  state into one indexed draw, flushing whenever Sacred changes render state;
- requests non-blocking `Present` with a compatibility fallback for runtimes
  that reject `DXGI_PRESENT_DO_NOT_WAIT`; DXMT may still wait in its own
  `PresentBoundary`, which the BLG telemetry reports separately.

The bridge is packaged as the bundled `BorealLegacyGraphics` component and is
staged beside Sacred by `LegacyWrapperManager`. It is only selected for the
32-bit DirectDraw profile; unrelated games continue to use their configured
wrapper or Wine path.
The Boreal Sacred launch plan explicitly selects the vertex-baked path,
disables the diagnostic software rasterizer, and pins the validated frame
latency of `16` so inherited shell environment cannot accidentally select a
slow or unstable diagnostic mode.

The component also carries `x64-unix/winemac.so`. This is the host-side Wine
11.17 compatibility shim required by the DXMT build used by the Sacred
profile: it exposes the macOS driver callbacks DXMT resolves dynamically and
uses the Wine window's content view during early swapchain creation. Boreal
installs that driver into the selected Wine snapshot as part of the same
transaction that publishes the managed wrapper. This is required because
Wine loads its macOS driver before DXMT resolves its callbacks; the selected
runtime is changed only at that one driver path and remains otherwise intact.

The bundled shim also configures the DXMT-hosted `CAMetalLayer` with display
synchronization disabled and a three-drawable queue. DXMT remains responsible
for frame pacing, while the host layer no longer serializes every legacy
`Present` against the display link.

The GPU texture-sampling variant remains available for diagnosis with
`BLG_TEXTURE_SAMPLING=1`. On the current DXMT/Wine runtime it is not the default:
Sacred reaches the scene, but repeated `Present` calls stall for hundreds of
milliseconds as soon as the pixel shader reads a texture resource. The default
vertex-baked path avoids that runtime boundary and keeps the actual Sacred
surface pixels in the rendering path.

For image-fidelity diagnosis, `BLG_SOFTWARE_RENDERING=1` selects the existing
CPU framebuffer/rasterizer. That path performs per-pixel point sampling for
stage 0 and stage 1, including the fixed-function color/alpha operations and
texture address modes, then uploads the completed frame to the D3D11
backbuffer. It is deliberately opt-in until its performance is measured on the
target machine; the normal Sacred profile remains the DXMT-safe vertex-baked
path.

The current implementation is intentionally honest about its boundary:
strided/vertex-buffer draws, fog, lighting, remaining multitexture operators
and additional pixel formats are traced or reported unsupported until a Sacred
trace demonstrates that they are required. They are the next generalization
step, not silently emulated with incorrect output.

The vertex-baked path also honors the observed stage-specific
`TEXCOORDINDEX` values when choosing between the two decoded UV pairs. The
concrete Sacred capture is documented in
[`SacredApiMatrix.md`](SacredApiMatrix.md). The observed `TEX2` path is a
two-stage fixed-function setup where stage 1 keeps the stage-0 RGB result and
modulates its alpha; the default CPU-baked renderer now handles that path.

## Build

The DLL must be compiled for 32-bit Windows, even when it is later run by WoW64 on Apple Silicon:

```sh
i686-w64-mingw32-g++ -std=c++20 -O2 -shared \
  -I BorealLegacyGraphics/include \
  BorealLegacyGraphics/src/blg_d3d11.cpp \
  BorealLegacyGraphics/src/blg_log.cpp \
  BorealLegacyGraphics/src/ddraw_proxy.cpp \
  -o /tmp/ddraw.dll \
  -lkernel32 -luser32 -luuid \
  -Wl,--kill-at
```

The same sources are available as a CMake target named `boreal_legacy_graphics`; configure it with an i686 MinGW-w64 toolchain.

On a development machine with Homebrew's MinGW-w64 toolchain, the reproducible shortcut is:

```sh
./BorealLegacyGraphics/build-x86.sh
```

The development build output `BorealLegacyGraphics/build/ddraw.dll` is
intentionally ignored by Git. The application resource package under
`Boreal/GraphicsComponents/BorealLegacyGraphics` contains the staged x86
component used by the app build. The Boreal Xcode target has an explicit
"Copy graphics components" build phase; it preserves the complete
`GraphicsComponents/BorealLegacyGraphics/{manifest.json,x86,x64-unix}` layout
under `Boreal.app/Contents/Resources`, including the host-side `winemac.so`
shim that cannot be linked into the Swift executable.

## Diagnostics

The default log is written to the Windows temporary directory as:

```text
BorealLegacyGraphics-<pid>.log
```

Set `BLG_LOG=trace` to include per-draw and state-setting calls. Set `BLG_LOG_PATH` to choose an exact log path. At `info` level, the renderer emits one line per telemetry window with FPS, scene/present time, draw count, texture-cache activity, and non-blocking present skips.
Set `BLG_TEXTURE_SAMPLING=1` only when diagnosing the experimental per-pixel
texture path described above; the default is the DXMT-safe vertex-baked mode.
With that diagnostic flag, `BLG_TEXTURE_STORAGE=dynamic-linear` selects DXMT's
buffer-backed linear texture allocation. It is retained as a diagnostic switch
because the current DXMT runtime still stalls in `Present` when a pixel shader
reads an SRV, regardless of the texture allocation mode. The vertex-baked
path also applies Sacred's observed stage-0 `COLOROP`/`ALPHAOP` operations,
including `MODULATE` and `SELECTARG1`, before submitting the draw.
`BLG_SOFTWARE_RENDERING=1` is a separate diagnostic mode for checking the
per-pixel CPU result without enabling a DXMT shader-resource view.
`BLG_FRAME_LATENCY=1..31` is an optional pacing diagnostic; the normal Sacred
profile keeps the validated value of `16`. Lower values can make DXMT wait in
`PresentBoundary` before the many small Sacred submissions have drained.
`BLG_PRESENT_INTERVAL_MS=1..1000` is an additional diagnostic cadence gate:
it limits how often the legacy `EndScene` path enters DXMT `Present`, while
intermediate scenes continue rendering into the current backbuffer. It is
disabled by the normal Sacred profile because the measured `33 ms` setting
did not remove the compositor stalls.
`BLG_SWAPCHAIN_MODE=flip-discard` probes DXMT's flip-model swapchain with three
buffers. It passes Sacred's bootstrap, but the measured runtime still waits in
the Metal drawable path, so the normal profile keeps the legacy discard chain.
`BLG_GEOMETRY_CULLING=1` enables conservative whole-primitive viewport culling
after D3D7 vertex conversion. It only drops a draw when every referenced
vertex is outside the same viewport edge; it is diagnostic until a complete
scene run confirms that it reduces workload without changing the visual path.

The bundled host shim is rebuilt from Wine 11.17 with the following required
configuration properties: x86_64 macOS driver, exported `get_win_data`,
`release_win_data`, `macdrv_view_create_metal_view`,
`macdrv_view_get_metal_layer`, and the early-swapchain content-view fallback.
The source change that disables host display-link pacing and keeps three
drawable slots is kept as [`winemac-dxmt.patch`](winemac-dxmt.patch). Apply it
to a clean Wine 11.17 tree before rebuilding the host driver:

```sh
cd /path/to/wine-11.17
patch -p1 < /path/to/BorealLegacyGraphics/winemac-dxmt.patch
make -C /path/to/wine-11.17-build dlls/winemac.drv/winemac.so
```

The bundled `winemac.so` is therefore tied to the Wine 11.17 ABI and must be
installed together with the matching Wine snapshot; the patch is not intended
to be applied to an arbitrary Wine version without checking its hunk context.
