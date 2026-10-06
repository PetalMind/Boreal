# Dragon Age: Origins — OpenGL performance baseline

## Evidence (2026-10-02)

The installed GOG game is `1949616134`. Its active environment is
`853CB30C-FD13-4EB1-A26E-9F6725CB03F1`, running
`local-wine-devel-11-16-x86_64-r1` with WineD3D/OpenGL on Apple M4.
The runtime manifest advertises neither ESync nor MSync.

The most recent existing launch log,
`launch-54200b36-8a20-4dcf-b433-ce078e01e183.stderr.log`, contains 991
`wglSwapBuffers` FPS samples. Their median is 26.85 FPS; 142 are below
20 FPS and 73 below 16 FPS. These are pre-change readings from the entire
session, including possible menus/loading. They are not a benchmark of a
specific gameplay scene and do not establish post-change performance.

The game has an existing OpenGL framebuffer compatibility repair. Earlier
logs contain framebuffer errors and exception failures; the built-in game
profile records a Vulkan buffer-creation failure. Keep that compatibility
path while reducing rendering load.

Wine 11.16 already enables its multithreaded command stream by default:
https://github.com/wine-mirror/wine/blob/wine-11.16/dlls/wined3d/wined3d_main.c
Enabling CSMT alone would not establish an improvement. Wine also tracks
slow DAO rendering with experimental WoW64/OpenGL as bug 55981:
https://list.winehq.org/hyperkitty/list/wine-bugs%40list.winehq.org/2026/8/?count=10&page=7&view=threads
That report concerns a different platform/runtime and is contextual evidence,
not proof of the local bottleneck.

The installed `data/DAOriginsConfig.xml` defines the actual INI keys:
`UseVSync`, `GraphicsDetailLevel` (0 low, 1 medium, 2 high, 3 very high),
`ResolutionWidth`, `ResolutionHeight`, and the framebuffer safety settings.
The live INI could not be read through the terminal because Wine's Documents
directory links to the macOS Documents directory, protected by privacy access.

## Behavior in Boreal 1.0.4 (5)

Both existing GOG/direct launch paths run the OpenGL settings repair before
starting DAO. In addition to the existing framebuffer safety values, the
first launch applies:

- VSync off, to remove refresh-interval throttling when rendering is slow.
- Graphics detail capped at medium; existing low detail remains low.
- Explicit resolutions larger than 1600 × 1000 are scaled down to fit that
  bounding box while preserving aspect ratio. Existing smaller resolutions
  and automatic/unknown resolution settings remain unchanged.

The performance changes are applied once, marked by
`[Boreal] OpenGLPerformanceVersion=1` in `DragonAge.ini`. Subsequent changes
to resolution, graphics detail and VSync made in the game/configurator are
preserved. The existing AA/MRT/framebuffer safety repair remains enforced.
Textures, sound, controls, mods and saves are not changed.

Before writing an existing INI, Boreal retains
`DragonAge.ini.boreal-before-opengl-performance-v1` beside it. The original
framebuffer backup is also preserved. Reads that fail due to access or
encoding errors now abort instead of replacing the INI with an empty file.
UTF-8 and BOM-marked UTF-16 configurations are supported.

A persisted Vulkan fallback is cleared for this GOG title so it cannot
reconfigure the next launch away from OpenGL. The selected Wine runtime
remains pinned as before.

## Validation boundary

The performance improvement requires launching DAO through the updated
Boreal. No post-change gameplay FPS was measured in this session, and no
specific FPS increase is promised. The tradeoff is lower rendering detail
and potentially lower resolution; disabling VSync may introduce tearing.
No new unit tests were added for this settings change.
