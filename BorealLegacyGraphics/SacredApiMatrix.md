# Sacred API matrix

This matrix records the DirectDraw/D3D7 subset observed while launching Sacred
Gold through the Boreal Legacy Graphics proxy. It is based on the trace runs
used for this component, not on the complete DirectX 7 interface contract.
Numeric values below are the Direct3D 7 enum values emitted by Sacred.

## Observed entry points

| Interface | Calls observed | BLG status |
| --- | --- | --- |
| `IDirectDraw7` | `GetCaps`, `EnumDisplayModes`, `SetCooperativeLevel`, `SetDisplayMode`, `CreateSurface`, `GetDisplayMode`, `GetAvailableVidMem`, `TestCooperativeLevel`, `GetDeviceIdentifier` | Synthetic display/surface setup backed by the BLG device; COM lifetime and unselected methods remain safe wrappers. |
| `IDirect3D7` | `EnumDevices`, `CreateDevice`, `EnumZBufferFormats`, `EnumTextureFormats` | Synthetic device enumeration and Z/texture format descriptors; the advertised synthetic device exposes two texture stages and the currently implemented fixed-function operators; `CreateDevice` switches the selected path to D3D11. |
| `IDirect3DDevice7` | `GetCaps`, `EnumTextureFormats`, `BeginScene`, `EndScene`, `SetRenderTarget`, `Clear`, `SetTransform`, `SetViewport`, `SetMaterial`, `SetRenderState`, `SetTexture`, `SetTextureStageState`, `DrawPrimitive`, `DrawIndexedPrimitive` | Implemented for the observed Sacred path. State changes flush pending batches where changing the state would alter already-baked vertices. |
| `IDirectDrawSurface7` | Surfaces are created, locked for texture reads, unlocked, and retained as stage texture objects. | CPU-backed synthetic surfaces provide the texture pixels and version counter used by the cache. |

The captured draw distribution contains only `D3DPT_TRIANGLESTRIP` (`5`). A
representative trace also contains one large indexed strip used during device
initialization and repeated four-vertex strips for the menu/scene. No line,
point, or triangle-fan submission was observed in those runs.

## Observed vertex layouts

| FVF | Decoded layout | Representative use | BLG status |
| --- | --- | --- | --- |
| `0x112` | `XYZ + NORMAL + TEX1` | Indexed strip, 4096 vertices / 8192 indices | Supported; world/view/projection transform is applied on the CPU. The normal is accepted for layout compatibility; lighting is not enabled by the trace. |
| `0x1c4` | `XYZRHW + DIFFUSE + SPECULAR + TEX1` | Four-vertex strips | Supported; specular data is consumed for stride calculation and ignored because Sacred's observed lighting state does not require it. |
| `0x244` | `XYZRHW + DIFFUSE + TEX2` | Dominant four-vertex menu/scene strips | Supported; both UV sets are decoded. Stage 1's observed alpha operation is applied while baking vertex colors. |

The renderer converts strips to indexed triangle lists with alternating
winding, then coalesces compatible submissions into the dynamic ring buffers.

## Observed render states

| Numeric state | Direct3D 7 name | Values observed | Handling |
| ---: | --- | --- | --- |
| `7` | `ZENABLE` | `0`, `1` | Implemented by the cached D3D11 depth state. |
| `8` | `FILLMODE` | `3` (`SOLID`) | Accepted; the observed value is the fixed solid path. |
| `14` | `ZWRITEENABLE` | `0`, `1` | Implemented by the cached D3D11 depth state. |
| `15` | `ALPHATESTENABLE` | `0` | Captured and retained by the proxy; alpha test is not active in the observed scene. |
| `19` | `SRCBLEND` | `2` (`ONE`), `5` (`SRCALPHA`) | Implemented by the cached D3D11 blend state. |
| `20` | `DESTBLEND` | `2` (`ONE`), `6` (`INVSRCALPHA`) | Implemented by the cached D3D11 blend state. |
| `22` | `CULLMODE` | `3` (`CCW`) | Implemented through the D3D11 rasterizer state mapping. |
| `23` | `ZFUNC` | `4` (`LESSEQUAL`) | Implemented by the cached D3D11 depth state. |
| `24`, `25` | `ALPHAREF`, `ALPHAFUNC` | `0x40`, `5` | Captured; inactive while `ALPHATESTENABLE=0`. |
| `27` | `ALPHABLENDENABLE` | `0`, `1` | Implemented by the cached D3D11 blend state. |
| `29` | `SPECULARENABLE` | `0` | Accepted; lighting/specular output is not required by the observed path. |
| `52`–`56` | Stencil enable/operations/function | `0`, `1`, `3`, `6` | Captured; the observed device uses no active stencil test in the render target path. |
| `137` | `LIGHTING` | `0`, `1` | Captured; fixed-function lighting is not used by the observed FVF/state combination. |
| `141` | `COLORVERTEX` | `1` | Captured; diffuse vertex color is part of the active path. |

States outside this table remain forwarded/captured where the wrapper exposes
them, but are not silently mapped to an unrelated D3D11 behavior.

## Observed texture-stage state

| Stage | State | Values observed | Handling |
| ---: | --- | --- | --- |
| `0` | `COLOROP`, `COLORARG1`, `COLORARG2` | `MODULATE`, `TEXTURE`, `DIFFUSE` (`4`, `2`, `0`) | Implemented in the CPU vertex-bake path. |
| `0` | `ALPHAOP`, `ALPHAARG1`, `ALPHAARG2` | `MODULATE`, `TEXTURE`, `DIFFUSE` (`4`, `2`, `0`) | Implemented in the CPU vertex-bake path. |
| `0` | `TEXCOORDINDEX`, `ADDRESSU`, `ADDRESSV` | `0`, `1`, `1` | `TEXCOORDINDEX` selects the corresponding decoded UV pair; CPU sampling now honors wrap, mirror, clamp, border and mirror-once address modes. |
| `0`, `1` | `MAGFILTER`, `MINFILTER` | `POINT`/`LINEAR` (`1`/`2`) | Accepted for compatibility; CPU sampling currently uses the stable point sample. |
| `1` | `COLOROP`, `COLORARG1`, `COLORARG2` | `SELECTARG2`, `TEXTURE`, `CURRENT` (`3`, `2`, `1`) | Implemented for the observed TEX2 path; RGB remains the stage-0 current color. |
| `1` | `ALPHAOP`, `ALPHAARG1`, `ALPHAARG2` | `MODULATE`, `TEXTURE`, `CURRENT` (`4`, `2`, `1`) | Implemented; stage-1 texture alpha multiplies the stage-0 current alpha. |
| `1` | `TEXCOORDINDEX` | `1` | Selects the second UV pair from FVF `0x244` for stage-1 CPU sampling; stage 0/1 can explicitly select either decoded pair. |

The default Sacred profile uses `BLG_TEXTURE_SAMPLING=0`: surface texels stay
in the CPU cache and are baked into diffuse vertex colors before D3D11
submission. `BLG_TEXTURE_SAMPLING=1` remains a diagnostic stage-0 GPU path;
the DXMT host runtime currently exhibits large `Present` stalls when the pixel
shader reads an SRV, so it is not selected by the normal profile.

## Explicitly not observed / next generalization

The captured runs did not submit strided or vertex-buffer draws, point/line
primitives, active fog, active lighting output, color-key rendering, or a
required format beyond 16/24/32-bit surface reads. Their wrappers exist for
COM/API compatibility, but the synthetic backend returns unsupported for the
corresponding unimplemented draw forms rather than fabricating geometry.
Those features should be added only after a Sacred trace demonstrates that the
current game path needs them.
