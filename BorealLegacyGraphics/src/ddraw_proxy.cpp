#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define INITGUID

#include "blg_log.h"
#include "blg_d3d11.h"

#include <windows.h>
#include <ddraw.h>
#include <d3d.h>

#include <cstdint>
#include <cstring>

namespace {

enum class InterfaceKind : uint32_t {
    directDraw7,
    directDrawSurface7,
    direct3D7,
    direct3DDevice7,
};

struct SurfaceState {
    DDSURFACEDESC2 description;
    SurfaceState *attached;
    BYTE *pixels;
    LONG references;
    DWORD version;
    bool locked;
    bool primary;
    bool ownsPixels;
};

struct Wrapper {
    void **vtable;
    void *real;
    void **realVtable;
    void *backend;
    InterfaceKind kind;
    ULONG references;
    size_t vtableCount;
    bool synthetic;
    void *textures[8];
    bool textureIsWrapper[8];
    void *renderTarget;
    D3DVIEWPORT7 viewport;
    D3DMATRIX transforms[4];
    DWORD renderStates[256];
    bool renderStateSet[256];
    DWORD textureStageStates[8][32];
    D3DMATERIAL7 material;
    D3DCLIPSTATUS clipStatus;
};

using QueryInterfaceProc = HRESULT (STDMETHODCALLTYPE *)(void *, REFIID, void **);
using AddRefProc = ULONG (STDMETHODCALLTYPE *)(void *);
using ReleaseProc = ULONG (STDMETHODCALLTYPE *)(void *);

constexpr size_t kDirectDraw7VtableCount = 30;
constexpr size_t kDirectDrawSurface7VtableCount = 49;
constexpr size_t kDirect3D7VtableCount = 8;
constexpr size_t kDirect3DDevice7VtableCount = 49;

template <typename Function>
void *functionPointer(Function pointer) {
    return reinterpret_cast<void *>(reinterpret_cast<uintptr_t>(pointer));
}

HRESULT STDMETHODCALLTYPE wrapperQueryInterface(Wrapper *, REFIID, void **);
ULONG STDMETHODCALLTYPE wrapperAddRef(Wrapper *);
ULONG STDMETHODCALLTYPE wrapperRelease(Wrapper *);

void releaseRaw(void *object) {
    if (object == nullptr) {
        return;
    }
    auto *vtable = *reinterpret_cast<void ***>(object);
    reinterpret_cast<ReleaseProc>(vtable[2])(object);
}

void releaseTextureReference(Wrapper *wrapper, DWORD stage = 0) {
    if (wrapper == nullptr || stage >= ARRAYSIZE(wrapper->textures) || wrapper->textures[stage] == nullptr) return;
    if (wrapper->textureIsWrapper[stage]) {
        wrapperRelease(static_cast<Wrapper *>(wrapper->textures[stage]));
    } else {
        releaseRaw(wrapper->textures[stage]);
    }
    wrapper->textures[stage] = nullptr;
    wrapper->textureIsWrapper[stage] = false;
}

HMODULE builtinDirectDraw();

void releaseSurfaceState(SurfaceState *state) {
    if (state == nullptr || InterlockedDecrement(&state->references) != 0) return;
    if (state->attached != nullptr && InterlockedDecrement(&state->attached->references) == 0) {
        if (state->attached->ownsPixels) HeapFree(GetProcessHeap(), 0, state->attached->pixels);
        HeapFree(GetProcessHeap(), 0, state->attached);
    }
    if (state->ownsPixels) HeapFree(GetProcessHeap(), 0, state->pixels);
    HeapFree(GetProcessHeap(), 0, state);
}

void logIID(const char *operation, REFIID iid) {
    blg::log(
        "%s iid=%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        operation,
        static_cast<unsigned long>(iid.Data1),
        static_cast<unsigned int>(iid.Data2),
        static_cast<unsigned int>(iid.Data3),
        iid.Data4[0], iid.Data4[1], iid.Data4[2], iid.Data4[3],
        iid.Data4[4], iid.Data4[5], iid.Data4[6], iid.Data4[7]
    );
}

ULONG realAddRef(Wrapper *wrapper) {
    if (wrapper->synthetic) {
        return static_cast<ULONG>(InterlockedIncrement(reinterpret_cast<volatile LONG *>(&wrapper->references)));
    }
    auto function = reinterpret_cast<AddRefProc>(wrapper->realVtable[1]);
    ULONG result = function(wrapper->real);
    InterlockedIncrement(reinterpret_cast<volatile LONG *>(&wrapper->references));
    return result;
}

ULONG realRelease(Wrapper *wrapper) {
    if (wrapper->synthetic) {
        LONG references = InterlockedDecrement(reinterpret_cast<volatile LONG *>(&wrapper->references));
        if (references == 0) {
            if (wrapper->kind == InterfaceKind::directDrawSurface7) {
                releaseSurfaceState(static_cast<SurfaceState *>(wrapper->backend));
            }
            if (wrapper->kind == InterfaceKind::direct3DDevice7) {
                for (DWORD stage = 0; stage < ARRAYSIZE(wrapper->textures); ++stage) {
                    releaseTextureReference(wrapper, stage);
                }
                if (wrapper->renderTarget != nullptr) wrapperRelease(static_cast<Wrapper *>(wrapper->renderTarget));
            }
            HeapFree(GetProcessHeap(), 0, wrapper->vtable);
            HeapFree(GetProcessHeap(), 0, wrapper);
            return 0;
        }
        return static_cast<ULONG>(references);
    }
    auto function = reinterpret_cast<ReleaseProc>(wrapper->realVtable[2]);
    ULONG result = function(wrapper->real);
    LONG references = InterlockedDecrement(reinterpret_cast<volatile LONG *>(&wrapper->references));
    if (references == 0) {
        if (wrapper->kind == InterfaceKind::directDrawSurface7) {
            releaseSurfaceState(static_cast<SurfaceState *>(wrapper->backend));
        }
        HeapFree(GetProcessHeap(), 0, wrapper->vtable);
        HeapFree(GetProcessHeap(), 0, wrapper);
    }
    return result;
}

void installWrapperMethods(Wrapper *wrapper);

HRESULT STDMETHODCALLTYPE ddrawCreateSurface(
    Wrapper *,
    LPDDSURFACEDESC2,
    LPDIRECTDRAWSURFACE7 *,
    IUnknown *
);
HRESULT STDMETHODCALLTYPE ddrawSetCooperativeLevel(Wrapper *, HWND, DWORD);
HRESULT STDMETHODCALLTYPE ddrawSetDisplayMode(Wrapper *, DWORD, DWORD, DWORD, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE ddrawEnumDisplayModes(Wrapper *, DWORD, LPDDSURFACEDESC2, LPVOID, LPDDENUMMODESCALLBACK2);
HRESULT STDMETHODCALLTYPE ddrawGetCaps(Wrapper *, LPDDCAPS, LPDDCAPS);
HRESULT STDMETHODCALLTYPE ddrawGetDisplayMode(Wrapper *, LPDDSURFACEDESC2);
HRESULT STDMETHODCALLTYPE ddrawGetAvailableVidMem(Wrapper *, LPDDSCAPS2, LPDWORD, LPDWORD);
HRESULT STDMETHODCALLTYPE ddrawTestCooperativeLevel(Wrapper *);
HRESULT STDMETHODCALLTYPE ddrawGetDeviceIdentifier(Wrapper *, LPDDDEVICEIDENTIFIER2, DWORD);
HRESULT STDMETHODCALLTYPE surfaceBlt(Wrapper *, LPRECT, LPDIRECTDRAWSURFACE7, LPRECT, DWORD, LPDDBLTFX);
HRESULT STDMETHODCALLTYPE surfaceFlip(Wrapper *, LPDIRECTDRAWSURFACE7, DWORD);
HRESULT STDMETHODCALLTYPE surfaceGetAttachedSurface(Wrapper *, LPDDSCAPS2, LPDIRECTDRAWSURFACE7 *);
HRESULT STDMETHODCALLTYPE surfaceGetCaps(Wrapper *, LPDDSCAPS2);
HRESULT STDMETHODCALLTYPE surfaceGetSurfaceDesc(Wrapper *, LPDDSURFACEDESC2);
HRESULT STDMETHODCALLTYPE surfaceIsLost(Wrapper *);
HRESULT STDMETHODCALLTYPE surfaceLock(Wrapper *, LPRECT, LPDDSURFACEDESC2, DWORD, HANDLE);
HRESULT STDMETHODCALLTYPE surfaceUnlock(Wrapper *, LPRECT);

HRESULT STDMETHODCALLTYPE d3dEnumDevices(Wrapper *, LPD3DENUMDEVICESCALLBACK7, void *);
HRESULT STDMETHODCALLTYPE d3dCreateDevice(Wrapper *, REFCLSID, IDirectDrawSurface7 *, IDirect3DDevice7 **);
HRESULT STDMETHODCALLTYPE d3dCreateVertexBuffer(Wrapper *, D3DVERTEXBUFFERDESC *, IDirect3DVertexBuffer7 **, DWORD);
HRESULT STDMETHODCALLTYPE d3dEnumZBufferFormats(Wrapper *, REFCLSID, LPD3DENUMPIXELFORMATSCALLBACK, void *);
HRESULT STDMETHODCALLTYPE d3dEvictManagedTextures(Wrapper *);

HRESULT STDMETHODCALLTYPE deviceGetCaps(Wrapper *, D3DDEVICEDESC7 *);
HRESULT STDMETHODCALLTYPE deviceEnumTextureFormats(Wrapper *, LPD3DENUMPIXELFORMATSCALLBACK, void *);
HRESULT STDMETHODCALLTYPE deviceBeginScene(Wrapper *);
HRESULT STDMETHODCALLTYPE deviceEndScene(Wrapper *);
HRESULT STDMETHODCALLTYPE deviceGetDirect3D(Wrapper *, IDirect3D7 **);
HRESULT STDMETHODCALLTYPE deviceSetRenderTarget(Wrapper *, IDirectDrawSurface7 *, DWORD);
HRESULT STDMETHODCALLTYPE deviceGetRenderTarget(Wrapper *, IDirectDrawSurface7 **);
HRESULT STDMETHODCALLTYPE deviceClear(Wrapper *, DWORD, D3DRECT *, DWORD, D3DCOLOR, D3DVALUE, DWORD);
HRESULT STDMETHODCALLTYPE deviceSetTransform(Wrapper *, D3DTRANSFORMSTATETYPE, D3DMATRIX *);
HRESULT STDMETHODCALLTYPE deviceGetTransform(Wrapper *, D3DTRANSFORMSTATETYPE, D3DMATRIX *);
HRESULT STDMETHODCALLTYPE deviceSetViewport(Wrapper *, D3DVIEWPORT7 *);
HRESULT STDMETHODCALLTYPE deviceMultiplyTransform(Wrapper *, D3DTRANSFORMSTATETYPE, D3DMATRIX *);
HRESULT STDMETHODCALLTYPE deviceGetViewport(Wrapper *, D3DVIEWPORT7 *);
HRESULT STDMETHODCALLTYPE deviceSetMaterial(Wrapper *, D3DMATERIAL7 *);
HRESULT STDMETHODCALLTYPE deviceGetMaterial(Wrapper *, D3DMATERIAL7 *);
HRESULT STDMETHODCALLTYPE deviceSetLight(Wrapper *, DWORD, D3DLIGHT7 *);
HRESULT STDMETHODCALLTYPE deviceGetLight(Wrapper *, DWORD, D3DLIGHT7 *);
HRESULT STDMETHODCALLTYPE deviceSetRenderState(Wrapper *, D3DRENDERSTATETYPE, DWORD);
HRESULT STDMETHODCALLTYPE deviceGetRenderState(Wrapper *, D3DRENDERSTATETYPE, DWORD *);
HRESULT STDMETHODCALLTYPE deviceBeginStateBlock(Wrapper *);
HRESULT STDMETHODCALLTYPE deviceEndStateBlock(Wrapper *, DWORD *);
HRESULT STDMETHODCALLTYPE devicePreLoad(Wrapper *, IDirectDrawSurface7 *);
HRESULT STDMETHODCALLTYPE deviceDrawPrimitive(Wrapper *, D3DPRIMITIVETYPE, DWORD, void *, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE deviceDrawIndexedPrimitive(Wrapper *, D3DPRIMITIVETYPE, DWORD, void *, DWORD, WORD *, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE deviceSetClipStatus(Wrapper *, D3DCLIPSTATUS *);
HRESULT STDMETHODCALLTYPE deviceGetClipStatus(Wrapper *, D3DCLIPSTATUS *);
HRESULT STDMETHODCALLTYPE deviceDrawPrimitiveStrided(Wrapper *, D3DPRIMITIVETYPE, DWORD, D3DDRAWPRIMITIVESTRIDEDDATA *, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE deviceDrawIndexedPrimitiveStrided(Wrapper *, D3DPRIMITIVETYPE, DWORD, D3DDRAWPRIMITIVESTRIDEDDATA *, DWORD, WORD *, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE deviceDrawPrimitiveVB(Wrapper *, D3DPRIMITIVETYPE, IDirect3DVertexBuffer7 *, DWORD, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE deviceDrawIndexedPrimitiveVB(Wrapper *, D3DPRIMITIVETYPE, IDirect3DVertexBuffer7 *, DWORD, DWORD, WORD *, DWORD, DWORD);
HRESULT STDMETHODCALLTYPE deviceComputeSphereVisibility(Wrapper *, D3DVECTOR *, D3DVALUE *, DWORD, DWORD, DWORD *);
HRESULT STDMETHODCALLTYPE deviceGetTexture(Wrapper *, DWORD, IDirectDrawSurface7 **);
HRESULT STDMETHODCALLTYPE deviceSetTexture(Wrapper *, DWORD, IDirectDrawSurface7 *);
HRESULT STDMETHODCALLTYPE deviceGetTextureStageState(Wrapper *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD *);
HRESULT STDMETHODCALLTYPE deviceSetTextureStageState(Wrapper *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD);
HRESULT STDMETHODCALLTYPE deviceValidate(Wrapper *, DWORD *);
HRESULT STDMETHODCALLTYPE deviceApplyStateBlock(Wrapper *, DWORD);
HRESULT STDMETHODCALLTYPE deviceCaptureStateBlock(Wrapper *, DWORD);
HRESULT STDMETHODCALLTYPE deviceDeleteStateBlock(Wrapper *, DWORD);
HRESULT STDMETHODCALLTYPE deviceCreateStateBlock(Wrapper *, D3DSTATEBLOCKTYPE, DWORD *);
HRESULT STDMETHODCALLTYPE deviceLoad(Wrapper *, IDirectDrawSurface7 *, POINT *, IDirectDrawSurface7 *, RECT *, DWORD);
HRESULT STDMETHODCALLTYPE deviceLightEnable(Wrapper *, DWORD, WINBOOL);
HRESULT STDMETHODCALLTYPE deviceGetLightEnable(Wrapper *, DWORD, WINBOOL *);
HRESULT STDMETHODCALLTYPE deviceSetClipPlane(Wrapper *, DWORD, D3DVALUE *);
HRESULT STDMETHODCALLTYPE deviceGetClipPlane(Wrapper *, DWORD, D3DVALUE *);
HRESULT STDMETHODCALLTYPE deviceGetInfo(Wrapper *, DWORD, void *, DWORD);

size_t vtableCount(InterfaceKind kind) {
    switch (kind) {
    case InterfaceKind::directDraw7: return kDirectDraw7VtableCount;
    case InterfaceKind::directDrawSurface7: return kDirectDrawSurface7VtableCount;
    case InterfaceKind::direct3D7: return kDirect3D7VtableCount;
    case InterfaceKind::direct3DDevice7: return kDirect3DDevice7VtableCount;
    }
    return 0;
}

void installWrapperMethods(Wrapper *wrapper) {
    wrapper->vtable[0] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, REFIID, void **)>(&wrapperQueryInterface));
    wrapper->vtable[1] = functionPointer(static_cast<ULONG (STDMETHODCALLTYPE *)(Wrapper *)>(&wrapperAddRef));
    wrapper->vtable[2] = functionPointer(static_cast<ULONG (STDMETHODCALLTYPE *)(Wrapper *)>(&wrapperRelease));

    switch (wrapper->kind) {
    case InterfaceKind::directDraw7:
        wrapper->vtable[6] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDSURFACEDESC2, LPDIRECTDRAWSURFACE7 *, IUnknown *)>(&ddrawCreateSurface));
        wrapper->vtable[8] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, LPDDSURFACEDESC2, LPVOID, LPDDENUMMODESCALLBACK2)>(&ddrawEnumDisplayModes));
        wrapper->vtable[11] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDCAPS, LPDDCAPS)>(&ddrawGetCaps));
        wrapper->vtable[12] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDSURFACEDESC2)>(&ddrawGetDisplayMode));
        wrapper->vtable[20] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, HWND, DWORD)>(&ddrawSetCooperativeLevel));
        wrapper->vtable[21] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, DWORD, DWORD, DWORD, DWORD)>(&ddrawSetDisplayMode));
        wrapper->vtable[23] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDSCAPS2, LPDWORD, LPDWORD)>(&ddrawGetAvailableVidMem));
        wrapper->vtable[26] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *)>(&ddrawTestCooperativeLevel));
        wrapper->vtable[27] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDDEVICEIDENTIFIER2, DWORD)>(&ddrawGetDeviceIdentifier));
        break;
    case InterfaceKind::directDrawSurface7:
        wrapper->vtable[5] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPRECT, LPDIRECTDRAWSURFACE7, LPRECT, DWORD, LPDDBLTFX)>(&surfaceBlt));
        wrapper->vtable[11] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDIRECTDRAWSURFACE7, DWORD)>(&surfaceFlip));
        wrapper->vtable[12] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDSCAPS2, LPDIRECTDRAWSURFACE7 *)>(&surfaceGetAttachedSurface));
        wrapper->vtable[14] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDSCAPS2)>(&surfaceGetCaps));
        wrapper->vtable[22] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPDDSURFACEDESC2)>(&surfaceGetSurfaceDesc));
        wrapper->vtable[24] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *)>(&surfaceIsLost));
        wrapper->vtable[25] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPRECT, LPDDSURFACEDESC2, DWORD, HANDLE)>(&surfaceLock));
        wrapper->vtable[32] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPRECT)>(&surfaceUnlock));
        break;
    case InterfaceKind::direct3D7:
        wrapper->vtable[3] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPD3DENUMDEVICESCALLBACK7, void *)>(&d3dEnumDevices));
        wrapper->vtable[4] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, REFCLSID, IDirectDrawSurface7 *, IDirect3DDevice7 **)>(&d3dCreateDevice));
        wrapper->vtable[5] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DVERTEXBUFFERDESC *, IDirect3DVertexBuffer7 **, DWORD)>(&d3dCreateVertexBuffer));
        wrapper->vtable[6] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, REFCLSID, LPD3DENUMPIXELFORMATSCALLBACK, void *)>(&d3dEnumZBufferFormats));
        wrapper->vtable[7] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *)>(&d3dEvictManagedTextures));
        break;
    case InterfaceKind::direct3DDevice7:
        wrapper->vtable[3] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DDEVICEDESC7 *)>(&deviceGetCaps));
        wrapper->vtable[4] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, LPD3DENUMPIXELFORMATSCALLBACK, void *)>(&deviceEnumTextureFormats));
        wrapper->vtable[5] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *)>(&deviceBeginScene));
        wrapper->vtable[6] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *)>(&deviceEndScene));
        wrapper->vtable[7] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, IDirect3D7 **)>(&deviceGetDirect3D));
        wrapper->vtable[8] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, IDirectDrawSurface7 *, DWORD)>(&deviceSetRenderTarget));
        wrapper->vtable[9] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, IDirectDrawSurface7 **)>(&deviceGetRenderTarget));
        wrapper->vtable[10] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DRECT *, DWORD, D3DCOLOR, D3DVALUE, DWORD)>(&deviceClear));
        wrapper->vtable[11] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DTRANSFORMSTATETYPE, D3DMATRIX *)>(&deviceSetTransform));
        wrapper->vtable[12] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DTRANSFORMSTATETYPE, D3DMATRIX *)>(&deviceGetTransform));
        wrapper->vtable[13] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DVIEWPORT7 *)>(&deviceSetViewport));
        wrapper->vtable[14] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DTRANSFORMSTATETYPE, D3DMATRIX *)>(&deviceMultiplyTransform));
        wrapper->vtable[15] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DVIEWPORT7 *)>(&deviceGetViewport));
        wrapper->vtable[16] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DMATERIAL7 *)>(&deviceSetMaterial));
        wrapper->vtable[17] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DMATERIAL7 *)>(&deviceGetMaterial));
        wrapper->vtable[18] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DLIGHT7 *)>(&deviceSetLight));
        wrapper->vtable[19] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DLIGHT7 *)>(&deviceGetLight));
        wrapper->vtable[20] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DRENDERSTATETYPE, DWORD)>(&deviceSetRenderState));
        wrapper->vtable[21] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DRENDERSTATETYPE, DWORD *)>(&deviceGetRenderState));
        wrapper->vtable[22] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *)>(&deviceBeginStateBlock));
        wrapper->vtable[23] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD *)>(&deviceEndStateBlock));
        wrapper->vtable[24] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, IDirectDrawSurface7 *)>(&devicePreLoad));
        wrapper->vtable[25] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DPRIMITIVETYPE, DWORD, void *, DWORD, DWORD)>(&deviceDrawPrimitive));
        wrapper->vtable[26] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DPRIMITIVETYPE, DWORD, void *, DWORD, WORD *, DWORD, DWORD)>(&deviceDrawIndexedPrimitive));
        wrapper->vtable[27] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DCLIPSTATUS *)>(&deviceSetClipStatus));
        wrapper->vtable[28] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DCLIPSTATUS *)>(&deviceGetClipStatus));
        wrapper->vtable[29] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DPRIMITIVETYPE, DWORD, D3DDRAWPRIMITIVESTRIDEDDATA *, DWORD, DWORD)>(&deviceDrawPrimitiveStrided));
        wrapper->vtable[30] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DPRIMITIVETYPE, DWORD, D3DDRAWPRIMITIVESTRIDEDDATA *, DWORD, WORD *, DWORD, DWORD)>(&deviceDrawIndexedPrimitiveStrided));
        wrapper->vtable[31] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DPRIMITIVETYPE, IDirect3DVertexBuffer7 *, DWORD, DWORD, DWORD)>(&deviceDrawPrimitiveVB));
        wrapper->vtable[32] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DPRIMITIVETYPE, IDirect3DVertexBuffer7 *, DWORD, DWORD, WORD *, DWORD, DWORD)>(&deviceDrawIndexedPrimitiveVB));
        wrapper->vtable[33] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DVECTOR *, D3DVALUE *, DWORD, DWORD, DWORD *)>(&deviceComputeSphereVisibility));
        wrapper->vtable[34] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, IDirectDrawSurface7 **)>(&deviceGetTexture));
        wrapper->vtable[35] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, IDirectDrawSurface7 *)>(&deviceSetTexture));
        wrapper->vtable[36] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD *)>(&deviceGetTextureStageState));
        wrapper->vtable[37] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD)>(&deviceSetTextureStageState));
        wrapper->vtable[38] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD *)>(&deviceValidate));
        wrapper->vtable[39] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD)>(&deviceApplyStateBlock));
        wrapper->vtable[40] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD)>(&deviceCaptureStateBlock));
        wrapper->vtable[41] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD)>(&deviceDeleteStateBlock));
        wrapper->vtable[42] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, D3DSTATEBLOCKTYPE, DWORD *)>(&deviceCreateStateBlock));
        wrapper->vtable[43] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, IDirectDrawSurface7 *, POINT *, IDirectDrawSurface7 *, RECT *, DWORD)>(&deviceLoad));
        wrapper->vtable[44] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, WINBOOL)>(&deviceLightEnable));
        wrapper->vtable[45] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, WINBOOL *)>(&deviceGetLightEnable));
        wrapper->vtable[46] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DVALUE *)>(&deviceSetClipPlane));
        wrapper->vtable[47] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, D3DVALUE *)>(&deviceGetClipPlane));
        wrapper->vtable[48] = functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, DWORD, void *, DWORD)>(&deviceGetInfo));
        break;
    }
}

Wrapper *createWrapper(void *real, InterfaceKind kind, SurfaceState *surfaceBackend = nullptr) {
    if (real == nullptr) {
        return nullptr;
    }

    size_t count = vtableCount(kind);
    auto *realVtable = *reinterpret_cast<void ***>(real);
    auto *wrapper = static_cast<Wrapper *>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(Wrapper)));
    if (wrapper == nullptr) {
        return nullptr;
    }

    wrapper->vtable = static_cast<void **>(HeapAlloc(GetProcessHeap(), 0, count * sizeof(void *)));
    if (wrapper->vtable == nullptr) {
        HeapFree(GetProcessHeap(), 0, wrapper);
        return nullptr;
    }

    CopyMemory(wrapper->vtable, realVtable, count * sizeof(void *));
    wrapper->real = real;
    wrapper->realVtable = realVtable;
    wrapper->backend = surfaceBackend;
    wrapper->kind = kind;
    wrapper->references = 1;
    wrapper->vtableCount = count;
    wrapper->synthetic = false;
    wrapper->viewport = {0, 0, 800, 600, 0.0f, 1.0f};
    if (kind == InterfaceKind::directDrawSurface7 && surfaceBackend != nullptr) {
        InterlockedIncrement(&surfaceBackend->references);
    }
    installWrapperMethods(wrapper);
    return wrapper;
}

Wrapper *createSyntheticWrapper(InterfaceKind kind, void *backend) {
    size_t count = vtableCount(kind);
    auto *wrapper = static_cast<Wrapper *>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(Wrapper)));
    if (wrapper == nullptr) return nullptr;
    wrapper->vtable = static_cast<void **>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, count * sizeof(void *)));
    if (wrapper->vtable == nullptr) {
        HeapFree(GetProcessHeap(), 0, wrapper);
        return nullptr;
    }
    wrapper->real = nullptr;
    wrapper->realVtable = nullptr;
    wrapper->backend = backend;
    wrapper->kind = kind;
    wrapper->references = 1;
    wrapper->vtableCount = count;
    wrapper->synthetic = true;
    wrapper->viewport = {0, 0, 800, 600, 0.0f, 1.0f};
    for (auto &matrix : wrapper->transforms) {
        ZeroMemory(&matrix, sizeof(matrix));
        matrix._11 = matrix._22 = matrix._33 = matrix._44 = 1.0f;
    }
    wrapper->textureStageStates[0][D3DTSS_COLOROP] = D3DTOP_MODULATE;
    wrapper->textureStageStates[0][D3DTSS_COLORARG1] = D3DTA_TEXTURE;
    wrapper->textureStageStates[0][D3DTSS_COLORARG2] = D3DTA_DIFFUSE;
    wrapper->textureStageStates[0][D3DTSS_ALPHAOP] = D3DTOP_MODULATE;
    wrapper->textureStageStates[0][D3DTSS_ALPHAARG1] = D3DTA_TEXTURE;
    wrapper->textureStageStates[0][D3DTSS_ALPHAARG2] = D3DTA_DIFFUSE;
    wrapper->textureStageStates[1][D3DTSS_COLOROP] = D3DTOP_DISABLE;
    wrapper->textureStageStates[1][D3DTSS_COLORARG1] = D3DTA_TEXTURE;
    wrapper->textureStageStates[1][D3DTSS_COLORARG2] = D3DTA_CURRENT;
    wrapper->textureStageStates[1][D3DTSS_ALPHAOP] = D3DTOP_DISABLE;
    wrapper->textureStageStates[1][D3DTSS_ALPHAARG1] = D3DTA_TEXTURE;
    wrapper->textureStageStates[1][D3DTSS_ALPHAARG2] = D3DTA_CURRENT;
    if (kind == InterfaceKind::directDrawSurface7 && backend != nullptr) {
        InterlockedIncrement(&static_cast<SurfaceState *>(backend)->references);
    }
    installWrapperMethods(wrapper);
    return wrapper;
}

HRESULT wrapQueryResult(Wrapper *owner, REFIID iid, void **result) {
    if (result == nullptr) {
        return E_POINTER;
    }

    if (owner->synthetic) {
        if ((owner->kind == InterfaceKind::directDraw7 &&
             (IsEqualIID(iid, IID_IDirectDraw7) || IsEqualIID(iid, IID_IUnknown))) ||
            (owner->kind == InterfaceKind::direct3D7 &&
             (IsEqualIID(iid, IID_IDirect3D7) || IsEqualIID(iid, IID_IUnknown))) ||
            (owner->kind == InterfaceKind::direct3DDevice7 &&
             (IsEqualIID(iid, IID_IDirect3DDevice7) || IsEqualIID(iid, IID_IUnknown))) ||
            (owner->kind == InterfaceKind::directDrawSurface7 &&
             (IsEqualIID(iid, IID_IDirectDrawSurface7) || IsEqualIID(iid, IID_IUnknown)))) {
            InterlockedIncrement(reinterpret_cast<volatile LONG *>(&owner->references));
            *result = owner;
            return S_OK;
        }
        if (owner->kind == InterfaceKind::directDraw7 && IsEqualIID(iid, IID_IDirect3D7)) {
            Wrapper *wrapped = createSyntheticWrapper(InterfaceKind::direct3D7, &blg::renderer());
            if (wrapped == nullptr) return E_OUTOFMEMORY;
            *result = wrapped;
            blg::log("QueryInterface supplied synthetic IDirect3D7 backed by BLG D3D11");
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    if ((owner->kind == InterfaceKind::directDraw7 &&
         (IsEqualIID(iid, IID_IDirectDraw7) || IsEqualIID(iid, IID_IUnknown))) ||
        (owner->kind == InterfaceKind::direct3D7 &&
        (IsEqualIID(iid, IID_IDirect3D7) || IsEqualIID(iid, IID_IUnknown))) ||
        (owner->kind == InterfaceKind::direct3DDevice7 &&
         (IsEqualIID(iid, IID_IDirect3DDevice7) || IsEqualIID(iid, IID_IUnknown))) ||
        (owner->kind == InterfaceKind::directDrawSurface7 &&
         (IsEqualIID(iid, IID_IDirectDrawSurface7) || IsEqualIID(iid, IID_IUnknown)))) {
        reinterpret_cast<AddRefProc>(owner->realVtable[1])(owner->real);
        InterlockedIncrement(reinterpret_cast<volatile LONG *>(&owner->references));
        *result = owner;
        return S_OK;
    }

    auto function = reinterpret_cast<QueryInterfaceProc>(owner->realVtable[0]);
    HRESULT resultCode = function(owner->real, iid, result);
    if (FAILED(resultCode) || *result == nullptr) {
        return resultCode;
    }

    if (owner->kind == InterfaceKind::directDraw7 && IsEqualIID(iid, IID_IDirect3D7)) {
        Wrapper *wrapped = createWrapper(*result, InterfaceKind::direct3D7);
        if (wrapped == nullptr) {
            releaseRaw(*result);
            *result = nullptr;
            return E_OUTOFMEMORY;
        }
        *result = wrapped;
    } else if (owner->kind == InterfaceKind::direct3D7 && IsEqualIID(iid, IID_IDirect3DDevice7)) {
        Wrapper *wrapped = createWrapper(*result, InterfaceKind::direct3DDevice7);
        if (wrapped == nullptr) {
            releaseRaw(*result);
            *result = nullptr;
            return E_OUTOFMEMORY;
        }
        *result = wrapped;
    } else if (owner->kind == InterfaceKind::direct3DDevice7 && IsEqualIID(iid, IID_IDirect3D7)) {
        Wrapper *wrapped = createWrapper(*result, InterfaceKind::direct3D7);
        if (wrapped == nullptr) {
            releaseRaw(*result);
            *result = nullptr;
            return E_OUTOFMEMORY;
        }
        *result = wrapped;
    } else if (owner->kind == InterfaceKind::directDrawSurface7 && IsEqualIID(iid, IID_IDirectDrawSurface7)) {
        Wrapper *wrapped = createWrapper(
            *result,
            InterfaceKind::directDrawSurface7,
            static_cast<SurfaceState *>(owner->backend)
        );
        if (wrapped == nullptr) {
            releaseRaw(*result);
            *result = nullptr;
            return E_OUTOFMEMORY;
        }
        *result = wrapped;
    }

    return resultCode;
}

HRESULT STDMETHODCALLTYPE wrapperQueryInterface(Wrapper *wrapper, REFIID iid, void **result) {
    logIID("QueryInterface", iid);
    HRESULT resultCode = wrapQueryResult(wrapper, iid, result);
    blg::log("QueryInterface result=0x%08lx object=%p", static_cast<unsigned long>(resultCode), result == nullptr ? nullptr : *result);
    return resultCode;
}

ULONG STDMETHODCALLTYPE wrapperAddRef(Wrapper *wrapper) {
    return realAddRef(wrapper);
}

ULONG STDMETHODCALLTYPE wrapperRelease(Wrapper *wrapper) {
    return realRelease(wrapper);
}

SurfaceState *surfaceState(Wrapper *wrapper) {
    if (wrapper == nullptr) return nullptr;
    auto *vtable = *reinterpret_cast<void ***>(wrapper);
    if (vtable == nullptr || vtable[0] != functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, REFIID, void **)>(&wrapperQueryInterface))) {
        return nullptr;
    }
    if (wrapper->kind != InterfaceKind::directDrawSurface7) {
        return nullptr;
    }
    return static_cast<SurfaceState *>(wrapper->backend);
}

void *rawSurface(Wrapper *wrapper) {
    if (wrapper == nullptr || wrapper->kind != InterfaceKind::directDrawSurface7) return nullptr;
    if (wrapper->vtable == nullptr || wrapper->vtable[0] != functionPointer(static_cast<HRESULT (STDMETHODCALLTYPE *)(Wrapper *, REFIID, void **)>(&wrapperQueryInterface))) {
        return nullptr;
    }
    return wrapper->synthetic ? nullptr : wrapper->real;
}

size_t surfaceBytesPerPixel(const SurfaceState *state) {
    if (state == nullptr) return 0;
    switch (state->description.ddpfPixelFormat.dwRGBBitCount) {
    case 16: return 2;
    case 24: return 3;
    case 32: return 4;
    default: return 0;
    }
}

HRESULT uploadNativeTexture(DWORD stage, IDirectDrawSurface7 *surface) {
    if (surface == nullptr) return E_INVALIDARG;
    void **vtable = *reinterpret_cast<void ***>(surface);
    if (vtable == nullptr || vtable[22] == nullptr || vtable[25] == nullptr || vtable[32] == nullptr) {
        blg::trace("D3D11 native texture rejected surface=%p missing surface methods", surface);
        return DDERR_INVALIDOBJECT;
    }

    DWORD version = 0;
    bool hasStableVersion = false;
    if (vtable[43] != nullptr) {
        using GetUniquenessValue = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD *);
        HRESULT uniquenessResult = reinterpret_cast<GetUniquenessValue>(vtable[43])(surface, &version);
        hasStableVersion = SUCCEEDED(uniquenessResult);
        if (!hasStableVersion) {
            blg::trace("D3D11 native texture uniqueness failed surface=%p result=0x%08lx", surface, static_cast<unsigned long>(uniquenessResult));
        }
    }
    HRESULT cachedResult = S_FALSE;
    if (hasStableVersion) {
        cachedResult = blg::renderer().activateCachedTexture(stage, surface, version);
    }
    if (cachedResult == S_OK) {
        blg::trace("D3D11 native texture cache hit surface=%p version=%lu", surface, static_cast<unsigned long>(version));
        return S_OK;
    }
    if (blg::renderer().activateCachedTextureByIdentity(stage, surface) == S_OK) {
        blg::trace("D3D11 native texture identity cache hit surface=%p", surface);
        return S_OK;
    }

    DDSURFACEDESC2 description = {};
    description.dwSize = sizeof(description);
    using GetSurfaceDesc = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSURFACEDESC2);
    HRESULT result = reinterpret_cast<GetSurfaceDesc>(vtable[22])(surface, &description);
    if (FAILED(result)) {
        blg::trace("D3D11 native texture description failed surface=%p result=0x%08lx", surface, static_cast<unsigned long>(result));
        return result;
    }

    description.dwSize = sizeof(description);
    using Lock = HRESULT (STDMETHODCALLTYPE *)(void *, LPRECT, LPDDSURFACEDESC2, DWORD, HANDLE);
    result = reinterpret_cast<Lock>(vtable[25])(
        surface,
        nullptr,
        &description,
        DDLOCK_READONLY | DDLOCK_WAIT,
        nullptr
    );
    if (FAILED(result)) {
        blg::trace("D3D11 native texture lock failed surface=%p result=0x%08lx", surface, static_cast<unsigned long>(result));
        return result;
    }

    if (!hasStableVersion && vtable[43] != nullptr) {
        using GetUniquenessValue = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD *);
        if (FAILED(reinterpret_cast<GetUniquenessValue>(vtable[43])(surface, &version))) {
            version = GetTickCount();
        }
    } else {
        version = GetTickCount();
    }
    result = blg::renderer().setTexture(
        stage,
        surface,
        version,
        description.dwWidth,
        description.dwHeight,
        static_cast<DWORD>(description.lPitch),
        description.ddpfPixelFormat.dwRGBBitCount,
        description.ddpfPixelFormat.dwRBitMask,
        description.ddpfPixelFormat.dwGBitMask,
        description.ddpfPixelFormat.dwBBitMask,
        description.ddpfPixelFormat.dwRGBAlphaBitMask,
        description.lpSurface
    );

    using Unlock = HRESULT (STDMETHODCALLTYPE *)(void *, LPRECT);
    HRESULT unlockResult = reinterpret_cast<Unlock>(vtable[32])(surface, nullptr);
    if (SUCCEEDED(result) && FAILED(unlockResult)) result = unlockResult;
    blg::trace(
        "D3D11 native texture upload surface=%p size=%lux%lu bpp=%lu result=0x%08lx",
        surface,
        static_cast<unsigned long>(description.dwWidth),
        static_cast<unsigned long>(description.dwHeight),
        static_cast<unsigned long>(description.ddpfPixelFormat.dwRGBBitCount),
        static_cast<unsigned long>(result)
    );
    return result;
}

SurfaceState *createSurfaceState(const DDSURFACEDESC2 *requested, bool allocatePixels = true) {
    auto *state = static_cast<SurfaceState *>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(SurfaceState)));
    if (state == nullptr) return nullptr;
    state->description.dwSize = sizeof(DDSURFACEDESC2);
    state->description.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT | DDSD_PIXELFORMAT;
    state->description.dwWidth = requested != nullptr && (requested->dwFlags & DDSD_WIDTH) != 0 ? requested->dwWidth : 800;
    state->description.dwHeight = requested != nullptr && (requested->dwFlags & DDSD_HEIGHT) != 0 ? requested->dwHeight : 600;
    state->description.dwWidth = state->description.dwWidth == 0 ? 1 : state->description.dwWidth;
    state->description.dwHeight = state->description.dwHeight == 0 ? 1 : state->description.dwHeight;
    state->description.ddsCaps.dwCaps = requested != nullptr ? requested->ddsCaps.dwCaps : 0;
    state->description.ddpfPixelFormat.dwSize = sizeof(DDPIXELFORMAT);
    state->description.ddpfPixelFormat.dwFlags = DDPF_RGB | DDPF_ALPHAPIXELS;
    state->description.ddpfPixelFormat.dwRGBBitCount = 32;
    state->description.ddpfPixelFormat.dwRBitMask = 0x00ff0000;
    state->description.ddpfPixelFormat.dwGBitMask = 0x0000ff00;
    state->description.ddpfPixelFormat.dwBBitMask = 0x000000ff;
    state->description.ddpfPixelFormat.dwRGBAlphaBitMask = 0xff000000;
    if (requested != nullptr && (requested->dwFlags & DDSD_PIXELFORMAT) != 0 &&
        (requested->ddpfPixelFormat.dwRGBBitCount == 16 ||
         requested->ddpfPixelFormat.dwRGBBitCount == 24 ||
         requested->ddpfPixelFormat.dwRGBBitCount == 32)) {
        state->description.ddpfPixelFormat = requested->ddpfPixelFormat;
        state->description.ddpfPixelFormat.dwSize = sizeof(DDPIXELFORMAT);
    }
    const size_t bytesPerPixel = surfaceBytesPerPixel(state);
    if (bytesPerPixel == 0) {
        HeapFree(GetProcessHeap(), 0, state);
        return nullptr;
    }
    if (allocatePixels) {
        const size_t pitch = static_cast<size_t>(state->description.dwWidth) * bytesPerPixel;
        const size_t size = pitch * static_cast<size_t>(state->description.dwHeight);
        state->pixels = static_cast<BYTE *>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size));
        if (state->pixels == nullptr) {
            HeapFree(GetProcessHeap(), 0, state);
            return nullptr;
        }
        state->ownsPixels = true;
        state->description.dwFlags |= DDSD_PITCH | DDSD_LPSURFACE;
        state->description.lPitch = static_cast<LONG>(pitch);
        state->description.lpSurface = state->pixels;
    }
    state->references = 0;
    state->version = 1;
    state->primary = (state->description.ddsCaps.dwCaps & DDSCAPS_PRIMARYSURFACE) != 0;
    return state;
}

Wrapper *wrapNativeSurface(void *realSurface, const DDSURFACEDESC2 *hint) {
    if (realSurface == nullptr) return nullptr;
    SurfaceState *state = createSurfaceState(hint, false);
    if (state == nullptr) return nullptr;

    void **realVtable = *reinterpret_cast<void ***>(realSurface);
    if (realVtable != nullptr && realVtable[22] != nullptr) {
        DDSURFACEDESC2 actual = {};
        actual.dwSize = sizeof(actual);
        using GetSurfaceDesc = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSURFACEDESC2);
        if (SUCCEEDED(reinterpret_cast<GetSurfaceDesc>(realVtable[22])(realSurface, &actual))) {
            actual.lpSurface = nullptr;
            state->description = actual;
        }
    }

    Wrapper *wrapped = createWrapper(realSurface, InterfaceKind::directDrawSurface7, state);
    if (wrapped == nullptr) HeapFree(GetProcessHeap(), 0, state);
    return wrapped;
}

HRESULT STDMETHODCALLTYPE surfaceBlt(Wrapper *wrapper, LPRECT destination, LPDIRECTDRAWSURFACE7 source, LPRECT sourceRect, DWORD flags, LPDDBLTFX effects) {
    blg::trace("IDirectDrawSurface7::Blt source=%p flags=0x%08lx", source, static_cast<unsigned long>(flags));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPRECT, LPDIRECTDRAWSURFACE7, LPRECT, DWORD, LPDDBLTFX);
        return reinterpret_cast<Function>(wrapper->realVtable[5])(
            wrapper->real,
            destination,
            reinterpret_cast<LPDIRECTDRAWSURFACE7>(rawSurface(reinterpret_cast<Wrapper *>(source))),
            sourceRect,
            flags,
            effects
        );
    }
    SurfaceState *destinationState = surfaceState(wrapper);
    if (destinationState == nullptr) return E_INVALIDARG;
    const size_t destinationBytesPerPixel = surfaceBytesPerPixel(destinationState);
    if (destinationBytesPerPixel == 0) return DDERR_UNSUPPORTED;
    if ((flags & DDBLT_COLORFILL) != 0) {
        const DWORD color = effects == nullptr ? 0 : effects->dwFillColor;
        for (DWORD y = 0; y < destinationState->description.dwHeight; ++y) {
            BYTE *row = destinationState->pixels + static_cast<size_t>(y) * destinationState->description.lPitch;
            for (DWORD x = 0; x < destinationState->description.dwWidth; ++x) {
                for (size_t byte = 0; byte < destinationBytesPerPixel; ++byte) {
                    row[static_cast<size_t>(x) * destinationBytesPerPixel + byte] =
                        static_cast<BYTE>(color >> (byte * 8));
                }
            }
        }
        ++destinationState->version;
        return DD_OK;
    }
    SurfaceState *sourceState = surfaceState(reinterpret_cast<Wrapper *>(source));
    if (sourceState == nullptr) return E_INVALIDARG;
    const size_t sourceBytesPerPixel = surfaceBytesPerPixel(sourceState);
    if (sourceBytesPerPixel == 0) return DDERR_UNSUPPORTED;
    RECT dst = destination == nullptr ? RECT{0, 0, static_cast<LONG>(destinationState->description.dwWidth), static_cast<LONG>(destinationState->description.dwHeight)} : *destination;
    RECT src = sourceRect == nullptr ? RECT{0, 0, static_cast<LONG>(sourceState->description.dwWidth), static_cast<LONG>(sourceState->description.dwHeight)} : *sourceRect;
    LONG width = dst.right - dst.left;
    LONG sourceWidth = src.right - src.left;
    LONG height = dst.bottom - dst.top;
    LONG sourceHeight = src.bottom - src.top;
    if (width > sourceWidth) width = sourceWidth;
    if (height > sourceHeight) height = sourceHeight;
    if (width <= 0 || height <= 0) return DDERR_INVALIDPARAMS;
    if (destinationBytesPerPixel != sourceBytesPerPixel) return DDERR_UNSUPPORTED;
    for (LONG y = 0; y < height; ++y) {
        const BYTE *sourceRow = sourceState->pixels + static_cast<size_t>(src.top + y) * sourceState->description.lPitch + static_cast<size_t>(src.left) * sourceBytesPerPixel;
        BYTE *destinationRow = destinationState->pixels + static_cast<size_t>(dst.top + y) * destinationState->description.lPitch + static_cast<size_t>(dst.left) * destinationBytesPerPixel;
        CopyMemory(destinationRow, sourceRow, static_cast<size_t>(width) * destinationBytesPerPixel);
    }
    ++destinationState->version;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE surfaceFlip(Wrapper *wrapper, LPDIRECTDRAWSURFACE7 targetOverride, DWORD flags) {
    blg::trace("IDirectDrawSurface7::Flip flags=0x%08lx", static_cast<unsigned long>(flags));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDIRECTDRAWSURFACE7, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[11])(
            wrapper->real,
            reinterpret_cast<LPDIRECTDRAWSURFACE7>(rawSurface(reinterpret_cast<Wrapper *>(targetOverride))),
            flags
        );
    }
    if (!surfaceState(wrapper)) return E_INVALIDARG;
    return blg::renderer().endScene();
}

HRESULT STDMETHODCALLTYPE surfaceGetAttachedSurface(Wrapper *wrapper, LPDDSCAPS2 caps, LPDIRECTDRAWSURFACE7 *surface) {
    blg::trace("IDirectDrawSurface7::GetAttachedSurface");
    if (surface == nullptr) return E_POINTER;
    *surface = nullptr;
    if (!wrapper->synthetic) {
        void *raw = nullptr;
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSCAPS2, void **);
        HRESULT result = reinterpret_cast<Function>(wrapper->realVtable[12])(wrapper->real, caps, &raw);
        if (FAILED(result) || raw == nullptr) return result;
        Wrapper *wrapped = wrapNativeSurface(raw, nullptr);
        if (wrapped == nullptr) {
            releaseRaw(raw);
            return E_OUTOFMEMORY;
        }
        *surface = reinterpret_cast<IDirectDrawSurface7 *>(wrapped);
        blg::trace("IDirectDrawSurface7::GetAttachedSurface surface=%p", *surface);
        return result;
    }
    SurfaceState *state = surfaceState(wrapper);
    if (state == nullptr || state->attached == nullptr) return DDERR_NOTFOUND;
    Wrapper *wrapped = createSyntheticWrapper(InterfaceKind::directDrawSurface7, state->attached);
    if (wrapped == nullptr) return E_OUTOFMEMORY;
    *surface = reinterpret_cast<IDirectDrawSurface7 *>(wrapped);
    blg::trace("IDirectDrawSurface7::GetAttachedSurface surface=%p", *surface);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE surfaceGetCaps(Wrapper *wrapper, LPDDSCAPS2 caps) {
    blg::trace("IDirectDrawSurface7::GetCaps");
    if (caps == nullptr) return E_POINTER;
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSCAPS2);
        return reinterpret_cast<Function>(wrapper->realVtable[14])(wrapper->real, caps);
    }
    SurfaceState *state = surfaceState(wrapper);
    if (state == nullptr) return E_INVALIDARG;
    caps->dwCaps = state->description.ddsCaps.dwCaps;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE surfaceGetSurfaceDesc(Wrapper *wrapper, LPDDSURFACEDESC2 description) {
    blg::trace("IDirectDrawSurface7::GetSurfaceDesc");
    if (description == nullptr) return E_POINTER;
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSURFACEDESC2);
        return reinterpret_cast<Function>(wrapper->realVtable[22])(wrapper->real, description);
    }
    SurfaceState *state = surfaceState(wrapper);
    if (state == nullptr) return E_INVALIDARG;
    CopyMemory(description, &state->description, sizeof(DDSURFACEDESC2));
    description->lpSurface = nullptr;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE surfaceIsLost(Wrapper *wrapper) {
    blg::trace("IDirectDrawSurface7::IsLost");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *);
        return reinterpret_cast<Function>(wrapper->realVtable[24])(wrapper->real);
    }
    return surfaceState(wrapper) == nullptr ? DDERR_INVALIDOBJECT : DD_OK;
}

HRESULT STDMETHODCALLTYPE surfaceLock(Wrapper *wrapper, LPRECT rect, LPDDSURFACEDESC2 description, DWORD flags, HANDLE event) {
    UNREFERENCED_PARAMETER(flags);
    UNREFERENCED_PARAMETER(event);
    blg::trace("IDirectDrawSurface7::Lock");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPRECT, LPDDSURFACEDESC2, DWORD, HANDLE);
        HRESULT result = reinterpret_cast<Function>(wrapper->realVtable[25])(wrapper->real, rect, description, flags, event);
        if (SUCCEEDED(result) && description != nullptr) {
            SurfaceState *state = surfaceState(wrapper);
            if (state != nullptr) {
                state->description = *description;
                state->description.lpSurface = nullptr;
                state->pixels = static_cast<BYTE *>(description->lpSurface);
                state->ownsPixels = false;
                state->locked = true;
            }
        }
        return result;
    }
    SurfaceState *state = surfaceState(wrapper);
    if (state == nullptr || description == nullptr) return E_INVALIDARG;
    if (state->locked) return DDERR_SURFACEBUSY;
    RECT lockRect = rect == nullptr ? RECT{0, 0, static_cast<LONG>(state->description.dwWidth), static_cast<LONG>(state->description.dwHeight)} : *rect;
    if (lockRect.left < 0 || lockRect.top < 0 || lockRect.right > static_cast<LONG>(state->description.dwWidth) || lockRect.bottom > static_cast<LONG>(state->description.dwHeight) || lockRect.left >= lockRect.right || lockRect.top >= lockRect.bottom) {
        return DDERR_INVALIDPARAMS;
    }
    CopyMemory(description, &state->description, sizeof(DDSURFACEDESC2));
    description->dwWidth = static_cast<DWORD>(lockRect.right - lockRect.left);
    description->dwHeight = static_cast<DWORD>(lockRect.bottom - lockRect.top);
    description->lPitch = state->description.lPitch;
    const size_t bytesPerPixel = surfaceBytesPerPixel(state);
    description->lpSurface = state->pixels + static_cast<size_t>(lockRect.top) * state->description.lPitch + static_cast<size_t>(lockRect.left) * bytesPerPixel;
    description->dwFlags |= DDSD_LPSURFACE | DDSD_PITCH;
    state->locked = true;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE surfaceUnlock(Wrapper *wrapper, LPRECT rect) {
    blg::trace("IDirectDrawSurface7::Unlock");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPRECT);
        HRESULT result = reinterpret_cast<Function>(wrapper->realVtable[32])(wrapper->real, rect);
        if (SUCCEEDED(result)) {
            SurfaceState *state = surfaceState(wrapper);
            if (state != nullptr) {
                state->locked = false;
                ++state->version;
            }
        }
        return result;
    }
    UNREFERENCED_PARAMETER(rect);
    SurfaceState *state = surfaceState(wrapper);
    if (state == nullptr) return DDERR_INVALIDOBJECT;
    if (!state->locked) return DDERR_NOTLOCKED;
    state->locked = false;
    ++state->version;
    return DD_OK;
}

void fillDisplayMode(DDSURFACEDESC2 *description) {
    if (description == nullptr) return;
    ZeroMemory(description, sizeof(*description));
    description->dwSize = sizeof(DDSURFACEDESC2);
    description->dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT | DDSD_PIXELFORMAT;
    description->dwWidth = 800;
    description->dwHeight = 600;
    description->ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    description->ddpfPixelFormat.dwSize = sizeof(DDPIXELFORMAT);
    description->ddpfPixelFormat.dwFlags = DDPF_RGB | DDPF_ALPHAPIXELS;
    description->ddpfPixelFormat.dwRGBBitCount = 32;
    description->ddpfPixelFormat.dwRBitMask = 0x00ff0000;
    description->ddpfPixelFormat.dwGBitMask = 0x0000ff00;
    description->ddpfPixelFormat.dwBBitMask = 0x000000ff;
    description->ddpfPixelFormat.dwRGBAlphaBitMask = 0xff000000;
}

HRESULT STDMETHODCALLTYPE ddrawEnumDisplayModes(Wrapper *wrapper, DWORD flags, LPDDSURFACEDESC2 filter, LPVOID context, LPDDENUMMODESCALLBACK2 callback) {
    UNREFERENCED_PARAMETER(flags);
    blg::log(
        "IDirectDraw7::EnumDisplayModes filter=%lux%lu bpp=%lu",
        filter != nullptr && (filter->dwFlags & DDSD_WIDTH) != 0 ? static_cast<unsigned long>(filter->dwWidth) : 0UL,
        filter != nullptr && (filter->dwFlags & DDSD_HEIGHT) != 0 ? static_cast<unsigned long>(filter->dwHeight) : 0UL,
        filter != nullptr && (filter->dwFlags & DDSD_PIXELFORMAT) != 0 ? static_cast<unsigned long>(filter->ddpfPixelFormat.dwRGBBitCount) : 0UL
    );
    if (wrapper->synthetic && callback != nullptr) {
        DDSURFACEDESC2 mode = {};
        fillDisplayMode(&mode);
        if (filter != nullptr) {
            if ((filter->dwFlags & DDSD_WIDTH) != 0) mode.dwWidth = filter->dwWidth;
            if ((filter->dwFlags & DDSD_HEIGHT) != 0) mode.dwHeight = filter->dwHeight;
            if ((filter->dwFlags & DDSD_PIXELFORMAT) != 0 && filter->ddpfPixelFormat.dwRGBBitCount != 0) {
                mode.ddpfPixelFormat.dwRGBBitCount = filter->ddpfPixelFormat.dwRGBBitCount;
                if (mode.ddpfPixelFormat.dwRGBBitCount == 16) {
                    mode.ddpfPixelFormat.dwRBitMask = 0x0000f800;
                    mode.ddpfPixelFormat.dwGBitMask = 0x000007e0;
                    mode.ddpfPixelFormat.dwBBitMask = 0x0000001f;
                    mode.ddpfPixelFormat.dwRGBAlphaBitMask = 0;
                    mode.ddpfPixelFormat.dwFlags = DDPF_RGB;
                }
            }
        }
        return callback(&mode, context);
    }
    if (wrapper->synthetic) return DD_OK;
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, LPDDSURFACEDESC2, LPVOID, LPDDENUMMODESCALLBACK2);
    return reinterpret_cast<Function>(wrapper->realVtable[8])(wrapper->real, flags, filter, context, callback);
}

HRESULT STDMETHODCALLTYPE ddrawGetCaps(Wrapper *wrapper, LPDDCAPS driverCaps, LPDDCAPS helCaps) {
    blg::log("IDirectDraw7::GetCaps");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDCAPS, LPDDCAPS);
        return reinterpret_cast<Function>(wrapper->realVtable[11])(wrapper->real, driverCaps, helCaps);
    }
    auto fillCaps = [](LPDDCAPS caps) {
        if (caps == nullptr) return;
        ZeroMemory(caps, sizeof(*caps));
        caps->dwSize = sizeof(DDCAPS);
        caps->dwCaps = DDCAPS_3D | DDCAPS_BLT | DDCAPS_BLTCOLORFILL | DDCAPS_BLTSTRETCH | DDCAPS_CANBLTSYSMEM;
        caps->dwCaps2 = DDCAPS2_CANRENDERWINDOWED | DDCAPS2_CANMANAGETEXTURE;
        caps->dwCKeyCaps = DDCKEYCAPS_SRCBLT | DDCKEYCAPS_DESTBLT;
        caps->dwFXCaps = DDFXCAPS_BLTALPHA;
        caps->dwVidMemTotal = 128 * 1024 * 1024;
        caps->dwVidMemFree = 128 * 1024 * 1024;
    };
    fillCaps(driverCaps);
    fillCaps(helCaps);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE ddrawGetDisplayMode(Wrapper *wrapper, LPDDSURFACEDESC2 description) {
    blg::log("IDirectDraw7::GetDisplayMode");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSURFACEDESC2);
        return reinterpret_cast<Function>(wrapper->realVtable[12])(wrapper->real, description);
    }
    if (description == nullptr) return E_POINTER;
    fillDisplayMode(description);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE ddrawGetAvailableVidMem(Wrapper *wrapper, LPDDSCAPS2 caps, LPDWORD total, LPDWORD freeMemory) {
    UNREFERENCED_PARAMETER(caps);
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSCAPS2, LPDWORD, LPDWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[23])(wrapper->real, caps, total, freeMemory);
    }
    if (total != nullptr) *total = 128 * 1024 * 1024;
    if (freeMemory != nullptr) *freeMemory = 128 * 1024 * 1024;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE ddrawTestCooperativeLevel(Wrapper *wrapper) {
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *);
        return reinterpret_cast<Function>(wrapper->realVtable[26])(wrapper->real);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE ddrawGetDeviceIdentifier(Wrapper *wrapper, LPDDDEVICEIDENTIFIER2 identifier, DWORD flags) {
    blg::log("IDirectDraw7::GetDeviceIdentifier flags=0x%08lx", static_cast<unsigned long>(flags));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDDEVICEIDENTIFIER2, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[27])(wrapper->real, identifier, flags);
    }
    if (identifier == nullptr) return E_POINTER;
    ZeroMemory(identifier, sizeof(*identifier));
    lstrcpynA(identifier->szDriver, "Boreal Legacy Graphics", MAX_DDDEVICEID_STRING);
    lstrcpynA(identifier->szDescription, "DXMT D3D11", MAX_DDDEVICEID_STRING);
    identifier->guidDeviceIdentifier = IID_IDirect3DHALDevice;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE ddrawCreateSurface(
    Wrapper *wrapper,
    LPDDSURFACEDESC2 description,
    LPDIRECTDRAWSURFACE7 *surface,
    IUnknown *outer
) {
    blg::log(
        "IDirectDraw7::CreateSurface flags=0x%08lx caps=0x%08lx size=%lux%lu",
        description == nullptr ? 0UL : static_cast<unsigned long>(description->dwFlags),
        description == nullptr ? 0UL : static_cast<unsigned long>(description->ddsCaps.dwCaps),
        description == nullptr ? 0UL : static_cast<unsigned long>(description->dwWidth),
        description == nullptr ? 0UL : static_cast<unsigned long>(description->dwHeight)
    );
    if (surface == nullptr) return E_POINTER;
    *surface = nullptr;

    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPDDSURFACEDESC2, LPDIRECTDRAWSURFACE7 *, IUnknown *);
        return reinterpret_cast<Function>(wrapper->realVtable[6])(wrapper->real, description, surface, outer);
    }

    SurfaceState *state = createSurfaceState(description);
    if (state == nullptr) return E_OUTOFMEMORY;
    if ((state->description.ddsCaps.dwCaps & DDSCAPS_COMPLEX) != 0 &&
        (state->description.ddsCaps.dwCaps & DDSCAPS_FLIP) != 0) {
        state->attached = createSurfaceState(description);
        if (state->attached != nullptr) {
            state->attached->references = 1;
            state->attached->description.ddsCaps.dwCaps &= ~DDSCAPS_PRIMARYSURFACE;
        }
    }
    Wrapper *wrapped = createSyntheticWrapper(InterfaceKind::directDrawSurface7, state);
    if (wrapped == nullptr) return E_OUTOFMEMORY;
    *surface = reinterpret_cast<IDirectDrawSurface7 *>(wrapped);
    blg::log("IDirectDraw7::CreateSurface supplied synthetic surface primary=%d", state->primary ? 1 : 0);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE ddrawSetCooperativeLevel(Wrapper *wrapper, HWND window, DWORD flags) {
    blg::log("IDirectDraw7::SetCooperativeLevel hwnd=%p flags=0x%08lx", window, static_cast<unsigned long>(flags));
    blg::renderer().setWindow(window);
    if (wrapper->synthetic) return DD_OK;
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, HWND, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[20])(wrapper->real, window, flags);
}

HRESULT STDMETHODCALLTYPE ddrawSetDisplayMode(Wrapper *wrapper, DWORD width, DWORD height, DWORD bpp, DWORD refresh, DWORD flags) {
    blg::log(
        "IDirectDraw7::SetDisplayMode %lux%lu bpp=%lu refresh=%lu flags=0x%08lx",
        static_cast<unsigned long>(width), static_cast<unsigned long>(height),
        static_cast<unsigned long>(bpp), static_cast<unsigned long>(refresh), static_cast<unsigned long>(flags)
    );
    blg::renderer().setDisplayMode(width, height);
    if (wrapper->synthetic) return DD_OK;
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, DWORD, DWORD, DWORD, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[21])(wrapper->real, width, height, bpp, refresh, flags);
}

HRESULT STDMETHODCALLTYPE d3dEnumDevices(Wrapper *wrapper, LPD3DENUMDEVICESCALLBACK7 callback, void *context) {
    blg::log("IDirect3D7::EnumDevices");
    if (wrapper->synthetic) {
        if (callback == nullptr) return E_POINTER;
        // Wine keeps its D3D7 device descriptors alive after the callback.
        // Sacred retains the selected pointer while creating its device, so
        // callback-local descriptors are invalid. It also filters the exact
        // three WineD3D records, including the T&L GUID.
        static D3DDEVICEDESC7 descriptions[3];
        static const GUID deviceGUIDs[3] = {
            {0xa4665c60, 0x2673, 0x11cf, {0xa3, 0x1a, 0x00, 0xaa, 0x00, 0xb9, 0x33, 0x56}},
            {0x84e63de0, 0x46aa, 0x11cf, {0x81, 0x6f, 0x00, 0x00, 0xc0, 0x20, 0x15, 0x6e}},
            {0xf5049e78, 0x4861, 0x11d2, {0xa4, 0x07, 0x00, 0xa0, 0xc9, 0x06, 0x29, 0xa8}},
        };
        static const DWORD deviceCaps[3] = {0x00002ff1, 0x0008aff1, 0x0009aff1};
        static const char *deviceDescriptions[3] = {
            "WINE Direct3D7 RGB Software Emulation using WineD3D",
            "WINE Direct3D7 Hardware acceleration using WineD3D",
            "WINE Direct3D7 Hardware Transform and Lighting acceleration using WineD3D",
        };
        static const char *deviceNames[3] = {
            "RGB Emulation",
            "Direct3D HAL",
            "Wine D3D7 T&L HAL",
        };

        auto fillPrimitiveCaps = [](D3DPRIMCAPS *caps) {
            caps->dwSize = sizeof(D3DPRIMCAPS);
            caps->dwMiscCaps = 0x00000072;
            caps->dwRasterCaps = 0x003363b9;
            caps->dwZCmpCaps = 0x000000ff;
            caps->dwSrcBlendCaps = 0x00001fff;
            caps->dwDestBlendCaps = 0x000007ff;
            caps->dwAlphaCmpCaps = 0x000000ff;
            caps->dwShadeCaps = 0x000c528a;
            caps->dwTextureCaps = 0x00000d9f;
            caps->dwTextureFilterCaps = 0x0703073f;
            caps->dwTextureBlendCaps = 0x000000ff;
            caps->dwTextureAddressCaps = 0x0000001f;
            caps->dwStippleWidth = 32;
            caps->dwStippleHeight = 32;
        };
        auto fillDeviceDescription = [&](D3DDEVICEDESC7 *description, size_t index) {
            ZeroMemory(description, sizeof(*description));
            description->dwDevCaps = deviceCaps[index];
            fillPrimitiveCaps(&description->dpcLineCaps);
            fillPrimitiveCaps(&description->dpcTriCaps);
            description->dwDeviceRenderBitDepth = 0x00000700;
            description->dwDeviceZBufferBitDepth = 0x00000600;
            description->dwMinTextureWidth = 1;
            description->dwMinTextureHeight = 1;
            description->dwMaxTextureWidth = 16384;
            description->dwMaxTextureHeight = 16384;
            description->dwMaxTextureRepeat = 32768;
            description->dwMaxTextureAspectRatio = 16384;
            description->dwMaxAnisotropy = 16;
            description->dvGuardBandLeft = -32768.0f;
            description->dvGuardBandTop = -32768.0f;
            description->dvGuardBandRight = 32768.0f;
            description->dvGuardBandBottom = 32768.0f;
            description->dwStencilCaps = 0x000000ff;
            description->dwFVFCaps = 0x00100008;
            // The synthetic D3D7 frontend currently implements two stages
            // and the first eleven fixed-function texture operators. Keep
            // the advertised capability set aligned with that bridge so
            // Sacred does not select an unsupported material path.
            description->dwTextureOpCaps = 0x000007ff;
            description->wMaxTextureBlendStages = 2;
            description->wMaxSimultaneousTextures = 2;
            description->dwMaxActiveLights = 8;
            description->dvMaxVertexW = 10000000000.0f;
            description->deviceGUID = deviceGUIDs[index];
            description->wMaxUserClipPlanes = 8;
            description->wMaxVertexBlendMatrices = 4;
            description->dwVertexProcessingCaps = 0x0000003f;
        };

        for (size_t index = 0; index < 3; ++index) {
            fillDeviceDescription(&descriptions[index], index);
            HRESULT result = callback(
                const_cast<char *>(deviceDescriptions[index]),
                const_cast<char *>(deviceNames[index]),
                &descriptions[index],
                context
            );
            blg::log(
                "IDirect3D7::EnumDevices synthetic device=%lu callback result=0x%08lx",
                static_cast<unsigned long>(index),
                static_cast<unsigned long>(result)
            );
            // D3D7 EnumDevices itself returns DD_OK after the callback walk;
            // the callback's D3DENUMRET value is not the COM HRESULT. Wine
            // returns 0 here even when every callback returned 1.
            if (result != D3DENUMRET_OK) break;
        }
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPD3DENUMDEVICESCALLBACK7, void *);
    return reinterpret_cast<Function>(wrapper->realVtable[3])(wrapper->real, callback, context);
}

HRESULT STDMETHODCALLTYPE d3dEnumZBufferFormats(Wrapper *wrapper, REFCLSID clsid, LPD3DENUMPIXELFORMATSCALLBACK callback, void *context) {
    logIID("IDirect3D7::EnumZBufferFormats clsid", clsid);
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, REFCLSID, LPD3DENUMPIXELFORMATSCALLBACK, void *);
        return reinterpret_cast<Function>(wrapper->realVtable[6])(wrapper->real, clsid, callback, context);
    }
    if (callback == nullptr) return E_POINTER;
    DDPIXELFORMAT format = {};
    format.dwSize = sizeof(format);
    format.dwFlags = DDPF_ZBUFFER | DDPF_STENCILBUFFER;
    format.dwZBufferBitDepth = 24;
    format.dwStencilBitDepth = 8;
    return callback(&format, context);
}

HRESULT STDMETHODCALLTYPE d3dEvictManagedTextures(Wrapper *wrapper) {
    blg::trace("IDirect3D7::EvictManagedTextures");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *);
        return reinterpret_cast<Function>(wrapper->realVtable[7])(wrapper->real);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetCaps(Wrapper *wrapper, D3DDEVICEDESC7 *caps) {
    blg::trace("IDirect3DDevice7::GetCaps");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DDEVICEDESC7 *);
        return reinterpret_cast<Function>(wrapper->realVtable[3])(wrapper->real, caps);
    }
    if (caps == nullptr) return E_POINTER;
    ZeroMemory(caps, sizeof(*caps));
    caps->dwDevCaps = D3DDEVCAPS_HWRASTERIZATION | D3DDEVCAPS_TEXTUREVIDEOMEMORY;
    caps->dwDeviceRenderBitDepth = DDBD_32;
    caps->dwDeviceZBufferBitDepth = DDBD_24;
    caps->dwMinTextureWidth = 1;
    caps->dwMinTextureHeight = 1;
    caps->dwMaxTextureWidth = 4096;
    caps->dwMaxTextureHeight = 4096;
    caps->dwMaxTextureRepeat = 4096;
    caps->dwMaxTextureAspectRatio = 4096;
    caps->dwMaxAnisotropy = 16;
    caps->dwTextureOpCaps = 0x000007ff;
    caps->wMaxTextureBlendStages = 2;
    // The BLG fixed-function bridge currently evaluates two texture stages
    // (TEX1/TEX2) in its CPU bake path. Advertising one stage is inconsistent
    // with the observed Sacred device state and can make the game discard the
    // stage-1 material path before it reaches SetTexture.
    caps->wMaxSimultaneousTextures = 2;
    caps->dwMaxActiveLights = 8;
    caps->dvMaxVertexW = 1000000.0f;
    caps->deviceGUID = IID_IDirect3DHALDevice;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceEnumTextureFormats(Wrapper *wrapper, LPD3DENUMPIXELFORMATSCALLBACK callback, void *context) {
    blg::trace("IDirect3DDevice7::EnumTextureFormats");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, LPD3DENUMPIXELFORMATSCALLBACK, void *);
        return reinterpret_cast<Function>(wrapper->realVtable[4])(wrapper->real, callback, context);
    }
    if (callback == nullptr) return E_POINTER;
    DDPIXELFORMAT formats[3] = {};
    formats[0].dwSize = sizeof(DDPIXELFORMAT);
    formats[0].dwFlags = DDPF_RGB | DDPF_ALPHAPIXELS;
    formats[0].dwRGBBitCount = 32;
    formats[0].dwRBitMask = 0x00ff0000;
    formats[0].dwGBitMask = 0x0000ff00;
    formats[0].dwBBitMask = 0x000000ff;
    formats[0].dwRGBAlphaBitMask = 0xff000000;
    formats[1] = formats[0];
    formats[1].dwFlags = DDPF_RGB;
    formats[1].dwRGBBitCount = 16;
    formats[1].dwRBitMask = 0x0000f800;
    formats[1].dwGBitMask = 0x000007e0;
    formats[1].dwBBitMask = 0x0000001f;
    formats[1].dwRGBAlphaBitMask = 0;
    formats[2].dwSize = sizeof(DDPIXELFORMAT);
    formats[2].dwFlags = DDPF_ALPHA;
    formats[2].dwAlphaBitDepth = 8;
    for (const auto &format : formats) {
        HRESULT result = callback(const_cast<DDPIXELFORMAT *>(&format), context);
        if (result != D3DENUMRET_OK) return result;
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE d3dCreateDevice(Wrapper *wrapper, REFCLSID clsid, IDirectDrawSurface7 *surface, IDirect3DDevice7 **device) {
    logIID("IDirect3D7::CreateDevice clsid", clsid);
    UNREFERENCED_PARAMETER(wrapper);
    UNREFERENCED_PARAMETER(surface);
    if (device == nullptr) return E_POINTER;
    *device = nullptr;
    HRESULT result = blg::renderer().initialize();
    blg::log("IDirect3D7::CreateDevice BLG D3D11 bootstrap result=0x%08lx", static_cast<unsigned long>(result));
    if (FAILED(result)) return result;
    Wrapper *wrapped = createSyntheticWrapper(InterfaceKind::direct3DDevice7, &blg::renderer());
    if (wrapped == nullptr) return E_OUTOFMEMORY;
    *device = reinterpret_cast<IDirect3DDevice7 *>(wrapped);
    blg::log("IDirect3D7::CreateDevice switched native D3D7 frontend to BLG D3D11");
    return S_OK;
}

HRESULT STDMETHODCALLTYPE d3dCreateVertexBuffer(Wrapper *wrapper, D3DVERTEXBUFFERDESC *description, IDirect3DVertexBuffer7 **buffer, DWORD flags) {
    UNREFERENCED_PARAMETER(description);
    UNREFERENCED_PARAMETER(flags);
    blg::trace("IDirect3D7::CreateVertexBuffer");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DVERTEXBUFFERDESC *, IDirect3DVertexBuffer7 **, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[5])(wrapper->real, description, buffer, flags);
    }
    if (buffer != nullptr) *buffer = nullptr;
    return DDERR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE deviceBeginScene(Wrapper *wrapper) {
    blg::trace("IDirect3DDevice7::BeginScene");
    if (wrapper->synthetic) return blg::renderer().beginScene();
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *);
    return reinterpret_cast<Function>(wrapper->realVtable[5])(wrapper->real);
}

HRESULT STDMETHODCALLTYPE deviceEndScene(Wrapper *wrapper) {
    blg::trace("IDirect3DDevice7::EndScene");
    if (wrapper->synthetic) return blg::renderer().endScene();
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *);
    return reinterpret_cast<Function>(wrapper->realVtable[6])(wrapper->real);
}

HRESULT STDMETHODCALLTYPE deviceGetDirect3D(Wrapper *wrapper, IDirect3D7 **d3d) {
    if (wrapper->synthetic) {
        if (d3d == nullptr) return E_POINTER;
        *d3d = nullptr;
        Wrapper *wrapped = createSyntheticWrapper(InterfaceKind::direct3D7, &blg::renderer());
        if (wrapped == nullptr) return E_OUTOFMEMORY;
        *d3d = reinterpret_cast<IDirect3D7 *>(wrapped);
        blg::trace("IDirect3DDevice7::GetDirect3D supplied synthetic IDirect3D7");
        return S_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, IDirect3D7 **);
    HRESULT result = reinterpret_cast<Function>(wrapper->realVtable[7])(wrapper->real, d3d);
    if (SUCCEEDED(result) && d3d != nullptr && *d3d != nullptr) {
        Wrapper *wrapped = createWrapper(*d3d, InterfaceKind::direct3D7);
        if (wrapped == nullptr) {
            (*d3d)->Release();
            *d3d = nullptr;
            return E_OUTOFMEMORY;
        }
        *d3d = reinterpret_cast<IDirect3D7 *>(wrapped);
    }
    blg::trace("IDirect3DDevice7::GetDirect3D result=0x%08lx", static_cast<unsigned long>(result));
    return result;
}

HRESULT STDMETHODCALLTYPE deviceSetRenderTarget(Wrapper *wrapper, IDirectDrawSurface7 *surface, DWORD flags) {
    UNREFERENCED_PARAMETER(flags);
    blg::trace("IDirect3DDevice7::SetRenderTarget surface=%p", surface);
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, IDirectDrawSurface7 *, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[8])(wrapper->real, surface, flags);
    }
    if (surface != nullptr && surfaceState(reinterpret_cast<Wrapper *>(surface)) == nullptr) {
        // The native DDraw surface remains owned by Wine. BLG renders into
        // its D3D11 swap-chain target, but accepting this target is required
        // for Sacred's normal device setup and avoids rejecting a valid COM
        // surface merely because it is not a synthetic wrapper.
        if (wrapper->renderTarget != nullptr) {
            wrapperRelease(static_cast<Wrapper *>(wrapper->renderTarget));
            wrapper->renderTarget = nullptr;
        }
        return DD_OK;
    }
    if (surface != nullptr) wrapperAddRef(reinterpret_cast<Wrapper *>(surface));
    if (wrapper->renderTarget != nullptr) wrapperRelease(static_cast<Wrapper *>(wrapper->renderTarget));
    wrapper->renderTarget = surface;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetRenderTarget(Wrapper *wrapper, IDirectDrawSurface7 **surface) {
    blg::trace("IDirect3DDevice7::GetRenderTarget");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, IDirectDrawSurface7 **);
        return reinterpret_cast<Function>(wrapper->realVtable[9])(wrapper->real, surface);
    }
    if (surface == nullptr) return E_POINTER;
    *surface = nullptr;
    if (wrapper->renderTarget != nullptr) {
        wrapperAddRef(static_cast<Wrapper *>(wrapper->renderTarget));
        *surface = reinterpret_cast<IDirectDrawSurface7 *>(wrapper->renderTarget);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceClear(Wrapper *wrapper, DWORD count, D3DRECT *rects, DWORD flags, D3DCOLOR color, D3DVALUE z, DWORD stencil) {
    blg::trace("IDirect3DDevice7::Clear count=%lu flags=0x%08lx color=0x%08lx", static_cast<unsigned long>(count), static_cast<unsigned long>(flags), static_cast<unsigned long>(color));
    if (wrapper->synthetic) return blg::renderer().clear(count, rects, flags, color, z, stencil);
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DRECT *, DWORD, D3DCOLOR, D3DVALUE, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[10])(wrapper->real, count, rects, flags, color, z, stencil);
}

HRESULT STDMETHODCALLTYPE deviceSetTransform(Wrapper *wrapper, D3DTRANSFORMSTATETYPE state, D3DMATRIX *matrix) {
    blg::trace("IDirect3DDevice7::SetTransform state=%lu", static_cast<unsigned long>(state));
    if (wrapper->synthetic) {
        if (matrix == nullptr) return E_POINTER;
        if (static_cast<DWORD>(state) < 4) wrapper->transforms[static_cast<DWORD>(state)] = *matrix;
        return blg::renderer().setTransform(state, matrix);
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DTRANSFORMSTATETYPE, D3DMATRIX *);
    return reinterpret_cast<Function>(wrapper->realVtable[11])(wrapper->real, state, matrix);
}

HRESULT STDMETHODCALLTYPE deviceGetTransform(Wrapper *wrapper, D3DTRANSFORMSTATETYPE state, D3DMATRIX *matrix) {
    blg::trace("IDirect3DDevice7::GetTransform state=%lu", static_cast<unsigned long>(state));
    if (wrapper->synthetic) {
        if (matrix == nullptr) return E_POINTER;
        if (static_cast<DWORD>(state) >= 4) return DDERR_INVALIDPARAMS;
        *matrix = wrapper->transforms[static_cast<DWORD>(state)];
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DTRANSFORMSTATETYPE, D3DMATRIX *);
    return reinterpret_cast<Function>(wrapper->realVtable[12])(wrapper->real, state, matrix);
}

HRESULT STDMETHODCALLTYPE deviceSetViewport(Wrapper *wrapper, D3DVIEWPORT7 *viewport) {
    blg::trace(
        "IDirect3DDevice7::SetViewport x=%ld y=%ld width=%ld height=%ld",
        viewport == nullptr ? 0L : static_cast<long>(viewport->dwX),
        viewport == nullptr ? 0L : static_cast<long>(viewport->dwY),
        viewport == nullptr ? 0L : static_cast<long>(viewport->dwWidth),
        viewport == nullptr ? 0L : static_cast<long>(viewport->dwHeight)
    );
    if (wrapper->synthetic) {
        if (viewport == nullptr) return E_POINTER;
        wrapper->viewport = *viewport;
        return blg::renderer().setViewport(viewport);
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DVIEWPORT7 *);
    return reinterpret_cast<Function>(wrapper->realVtable[13])(wrapper->real, viewport);
}

HRESULT STDMETHODCALLTYPE deviceMultiplyTransform(Wrapper *wrapper, D3DTRANSFORMSTATETYPE state, D3DMATRIX *matrix) {
    blg::trace("IDirect3DDevice7::MultiplyTransform state=%lu", static_cast<unsigned long>(state));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DTRANSFORMSTATETYPE, D3DMATRIX *);
        return reinterpret_cast<Function>(wrapper->realVtable[14])(wrapper->real, state, matrix);
    }
    if (matrix == nullptr) return E_POINTER;
    const DWORD index = static_cast<DWORD>(state);
    if (index >= 4) return DDERR_INVALIDPARAMS;
    D3DMATRIX current = wrapper->transforms[index];
    D3DMATRIX product = {};
    const float *currentValues = reinterpret_cast<const float *>(&current);
    const float *matrixValues = reinterpret_cast<const float *>(matrix);
    float *productValues = reinterpret_cast<float *>(&product);
    for (int row = 0; row < 4; ++row) {
        for (int column = 0; column < 4; ++column) {
            productValues[row * 4 + column] = currentValues[row * 4] * matrixValues[column]
                + currentValues[row * 4 + 1] * matrixValues[4 + column]
                + currentValues[row * 4 + 2] * matrixValues[8 + column]
                + currentValues[row * 4 + 3] * matrixValues[12 + column];
        }
    }
    wrapper->transforms[index] = product;
    return blg::renderer().setTransform(state, &product);
}

HRESULT STDMETHODCALLTYPE deviceGetViewport(Wrapper *wrapper, D3DVIEWPORT7 *viewport) {
    blg::trace("IDirect3DDevice7::GetViewport");
    if (wrapper->synthetic) {
        if (viewport == nullptr) return E_POINTER;
        *viewport = wrapper->viewport;
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DVIEWPORT7 *);
    return reinterpret_cast<Function>(wrapper->realVtable[15])(wrapper->real, viewport);
}

HRESULT STDMETHODCALLTYPE deviceSetMaterial(Wrapper *wrapper, D3DMATERIAL7 *material) {
    blg::trace("IDirect3DDevice7::SetMaterial");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DMATERIAL7 *);
        return reinterpret_cast<Function>(wrapper->realVtable[16])(wrapper->real, material);
    }
    if (material == nullptr) return E_POINTER;
    wrapper->material = *material;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetMaterial(Wrapper *wrapper, D3DMATERIAL7 *material) {
    blg::trace("IDirect3DDevice7::GetMaterial");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DMATERIAL7 *);
        return reinterpret_cast<Function>(wrapper->realVtable[17])(wrapper->real, material);
    }
    if (material == nullptr) return E_POINTER;
    *material = wrapper->material;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceSetLight(Wrapper *wrapper, DWORD index, D3DLIGHT7 *light) {
    UNREFERENCED_PARAMETER(index);
    UNREFERENCED_PARAMETER(light);
    blg::trace("IDirect3DDevice7::SetLight index=%lu", static_cast<unsigned long>(index));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DLIGHT7 *);
        return reinterpret_cast<Function>(wrapper->realVtable[18])(wrapper->real, index, light);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetLight(Wrapper *wrapper, DWORD index, D3DLIGHT7 *light) {
    UNREFERENCED_PARAMETER(index);
    blg::trace("IDirect3DDevice7::GetLight index=%lu", static_cast<unsigned long>(index));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DLIGHT7 *);
        return reinterpret_cast<Function>(wrapper->realVtable[19])(wrapper->real, index, light);
    }
    if (light == nullptr) return E_POINTER;
    ZeroMemory(light, sizeof(*light));
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceSetRenderState(Wrapper *wrapper, D3DRENDERSTATETYPE state, DWORD value) {
    blg::trace("IDirect3DDevice7::SetRenderState state=%lu value=0x%08lx", static_cast<unsigned long>(state), static_cast<unsigned long>(value));
    if (wrapper->synthetic) {
        const DWORD index = static_cast<DWORD>(state) & 0xffu;
        wrapper->renderStates[index] = value;
        wrapper->renderStateSet[index] = true;
        return blg::renderer().setRenderState(state, value);
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DRENDERSTATETYPE, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[20])(wrapper->real, state, value);
}

HRESULT STDMETHODCALLTYPE deviceGetRenderState(Wrapper *wrapper, D3DRENDERSTATETYPE state, DWORD *value) {
    blg::trace("IDirect3DDevice7::GetRenderState state=%lu", static_cast<unsigned long>(state));
    if (wrapper->synthetic) {
        if (value == nullptr) return E_POINTER;
        const DWORD index = static_cast<DWORD>(state) & 0xffu;
        if (wrapper->renderStateSet[index]) {
            *value = wrapper->renderStates[index];
        } else {
            switch (state) {
            case D3DRENDERSTATE_ZENABLE: *value = TRUE; break;
            case D3DRENDERSTATE_ZWRITEENABLE: *value = TRUE; break;
            case D3DRENDERSTATE_ZFUNC: *value = D3DCMP_LESSEQUAL; break;
            case D3DRENDERSTATE_ALPHABLENDENABLE: *value = TRUE; break;
            case D3DRENDERSTATE_SRCBLEND: *value = D3DBLEND_SRCALPHA; break;
            case D3DRENDERSTATE_DESTBLEND: *value = D3DBLEND_INVSRCALPHA; break;
            case D3DRENDERSTATE_CULLMODE: *value = D3DCULL_NONE; break;
            default: *value = 0; break;
            }
        }
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DRENDERSTATETYPE, DWORD *);
    return reinterpret_cast<Function>(wrapper->realVtable[21])(wrapper->real, state, value);
}

HRESULT STDMETHODCALLTYPE deviceBeginStateBlock(Wrapper *wrapper) {
    blg::trace("IDirect3DDevice7::BeginStateBlock");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *);
        return reinterpret_cast<Function>(wrapper->realVtable[22])(wrapper->real);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceEndStateBlock(Wrapper *wrapper, DWORD *handle) {
    blg::trace("IDirect3DDevice7::EndStateBlock");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD *);
        return reinterpret_cast<Function>(wrapper->realVtable[23])(wrapper->real, handle);
    }
    if (handle == nullptr) return E_POINTER;
    *handle = 1;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE devicePreLoad(Wrapper *wrapper, IDirectDrawSurface7 *surface) {
    blg::trace("IDirect3DDevice7::PreLoad surface=%p", surface);
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, IDirectDrawSurface7 *);
        return reinterpret_cast<Function>(wrapper->realVtable[24])(wrapper->real, surface);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetTexture(Wrapper *wrapper, DWORD stage, IDirectDrawSurface7 **texture) {
    blg::trace("IDirect3DDevice7::GetTexture stage=%lu", static_cast<unsigned long>(stage));
    if (wrapper->synthetic) {
        if (texture == nullptr) return E_POINTER;
        *texture = nullptr;
        if (stage >= ARRAYSIZE(wrapper->textures)) return DDERR_INVALIDPARAMS;
        if (wrapper->textures[stage] != nullptr) {
            if (wrapper->textureIsWrapper[stage]) {
                Wrapper *surface = static_cast<Wrapper *>(wrapper->textures[stage]);
                wrapperAddRef(surface);
            } else {
                auto *vtable = *reinterpret_cast<void ***>(wrapper->textures[stage]);
                reinterpret_cast<AddRefProc>(vtable[1])(wrapper->textures[stage]);
            }
            *texture = reinterpret_cast<IDirectDrawSurface7 *>(wrapper->textures[stage]);
        }
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, IDirectDrawSurface7 **);
    return reinterpret_cast<Function>(wrapper->realVtable[34])(wrapper->real, stage, texture);
}

HRESULT STDMETHODCALLTYPE deviceSetTexture(Wrapper *wrapper, DWORD stage, IDirectDrawSurface7 *texture) {
    blg::trace("IDirect3DDevice7::SetTexture stage=%lu texture=%p", static_cast<unsigned long>(stage), texture);
    if (wrapper->synthetic) {
        if (stage >= ARRAYSIZE(wrapper->textures)) return DDERR_INVALIDPARAMS;
        if (texture == nullptr) {
            releaseTextureReference(wrapper, stage);
            blg::renderer().clearTexture(stage, nullptr);
            return DD_OK;
        }

        Wrapper *newTexture = reinterpret_cast<Wrapper *>(texture);
        SurfaceState *state = surfaceState(newTexture);
        const bool sameTexture = wrapper->textures[stage] == texture
            && wrapper->textureIsWrapper[stage] == (state != nullptr);
        // Sacred rebinds the same material surfaces frequently. The D3D
        // contract keeps one reference owned by the device; setting the
        // identical object again must not turn that into a Release/AddRef
        // pair. Native surfaces still pass through uploadNativeTexture so a
        // changed uniqueness value is detected.
        if (!sameTexture) releaseTextureReference(wrapper, stage);
        if (state != nullptr) {
            // Synthetic surfaces are owned by this proxy and retain the
            // already available software pixel buffer.
            if (!sameTexture) {
                wrapperAddRef(newTexture);
                wrapper->textures[stage] = newTexture;
                wrapper->textureIsWrapper[stage] = true;
            }
            const DDPIXELFORMAT &format = state->description.ddpfPixelFormat;
            HRESULT textureResult = blg::renderer().setTexture(
                stage,
                state,
                state->version,
                state->description.dwWidth,
                state->description.dwHeight,
                static_cast<DWORD>(state->description.lPitch),
                format.dwRGBBitCount,
                format.dwRBitMask,
                format.dwGBitMask,
                format.dwBBitMask,
                format.dwRGBAlphaBitMask,
                state->pixels
            );
            return textureResult;
        }

        // Sacred normally passes Wine's native surface here. Keep the native
        // COM object alive for GetTexture and take a read-only lock only for
        // the upload; all other surface methods remain untouched by BLG.
        auto *vtable = *reinterpret_cast<void ***>(texture);
        if (vtable == nullptr || vtable[1] == nullptr) {
            blg::renderer().clearTexture(stage, nullptr);
            return DDERR_INVALIDOBJECT;
        }
        if (!sameTexture) {
            reinterpret_cast<AddRefProc>(vtable[1])(texture);
            wrapper->textures[stage] = texture;
            wrapper->textureIsWrapper[stage] = false;
        }
        const ULONGLONG uploadStart = GetTickCount64();
        HRESULT result = uploadNativeTexture(stage, texture);
        blg::renderer().recordNativeTextureUpload(GetTickCount64() - uploadStart);
        if (FAILED(result)) {
            blg::trace("D3D11 native texture upload unavailable result=0x%08lx", static_cast<unsigned long>(result));
            blg::renderer().clearTexture(stage, nullptr);
            return DD_OK;
        }
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, IDirectDrawSurface7 *);
    return reinterpret_cast<Function>(wrapper->realVtable[35])(wrapper->real, stage, texture);
}

HRESULT STDMETHODCALLTYPE deviceGetTextureStageState(Wrapper *wrapper, DWORD stage, D3DTEXTURESTAGESTATETYPE state, DWORD *value) {
    blg::trace("IDirect3DDevice7::GetTextureStageState stage=%lu state=%lu", static_cast<unsigned long>(stage), static_cast<unsigned long>(state));
    if (wrapper->synthetic) {
        if (value == nullptr) return E_POINTER;
        if (stage >= 8 || static_cast<DWORD>(state) >= 32) return DDERR_INVALIDPARAMS;
        *value = wrapper->textureStageStates[stage][static_cast<DWORD>(state)];
        return DD_OK;
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD *);
    return reinterpret_cast<Function>(wrapper->realVtable[36])(wrapper->real, stage, state, value);
}

HRESULT STDMETHODCALLTYPE deviceDrawPrimitive(Wrapper *wrapper, D3DPRIMITIVETYPE primitive, DWORD fvf, void *vertices, DWORD vertexCount, DWORD flags) {
    blg::trace("IDirect3DDevice7::DrawPrimitive primitive=%lu fvf=0x%08lx vertices=%lu flags=0x%08lx", static_cast<unsigned long>(primitive), static_cast<unsigned long>(fvf), static_cast<unsigned long>(vertexCount), static_cast<unsigned long>(flags));
    if (wrapper->synthetic) return blg::renderer().drawPrimitive(primitive, fvf, vertices, vertexCount, flags);
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DPRIMITIVETYPE, DWORD, void *, DWORD, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[25])(wrapper->real, primitive, fvf, vertices, vertexCount, flags);
}

HRESULT STDMETHODCALLTYPE deviceDrawIndexedPrimitive(Wrapper *wrapper, D3DPRIMITIVETYPE primitive, DWORD fvf, void *vertices, DWORD vertexCount, WORD *indices, DWORD indexCount, DWORD flags) {
    blg::trace("IDirect3DDevice7::DrawIndexedPrimitive primitive=%lu fvf=0x%08lx vertices=%lu indices=%lu flags=0x%08lx", static_cast<unsigned long>(primitive), static_cast<unsigned long>(fvf), static_cast<unsigned long>(vertexCount), static_cast<unsigned long>(indexCount), static_cast<unsigned long>(flags));
    if (wrapper->synthetic) return blg::renderer().drawIndexedPrimitive(primitive, fvf, vertices, vertexCount, indices, indexCount, flags);
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DPRIMITIVETYPE, DWORD, void *, DWORD, WORD *, DWORD, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[26])(wrapper->real, primitive, fvf, vertices, vertexCount, indices, indexCount, flags);
}

HRESULT STDMETHODCALLTYPE deviceSetClipStatus(Wrapper *wrapper, D3DCLIPSTATUS *status) {
    blg::trace("IDirect3DDevice7::SetClipStatus");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DCLIPSTATUS *);
        return reinterpret_cast<Function>(wrapper->realVtable[27])(wrapper->real, status);
    }
    if (status == nullptr) return E_POINTER;
    wrapper->clipStatus = *status;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetClipStatus(Wrapper *wrapper, D3DCLIPSTATUS *status) {
    blg::trace("IDirect3DDevice7::GetClipStatus");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DCLIPSTATUS *);
        return reinterpret_cast<Function>(wrapper->realVtable[28])(wrapper->real, status);
    }
    if (status == nullptr) return E_POINTER;
    *status = wrapper->clipStatus;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceDrawPrimitiveStrided(Wrapper *wrapper, D3DPRIMITIVETYPE primitive, DWORD fvf, D3DDRAWPRIMITIVESTRIDEDDATA *data, DWORD vertexCount, DWORD flags) {
    UNREFERENCED_PARAMETER(primitive);
    UNREFERENCED_PARAMETER(fvf);
    UNREFERENCED_PARAMETER(data);
    UNREFERENCED_PARAMETER(vertexCount);
    blg::trace("IDirect3DDevice7::DrawPrimitiveStrided vertices=%lu", static_cast<unsigned long>(vertexCount));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DPRIMITIVETYPE, DWORD, D3DDRAWPRIMITIVESTRIDEDDATA *, DWORD, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[29])(wrapper->real, primitive, fvf, data, vertexCount, flags);
    }
    return DDERR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE deviceDrawIndexedPrimitiveStrided(Wrapper *wrapper, D3DPRIMITIVETYPE primitive, DWORD fvf, D3DDRAWPRIMITIVESTRIDEDDATA *data, DWORD vertexCount, WORD *indices, DWORD indexCount, DWORD flags) {
    UNREFERENCED_PARAMETER(primitive);
    UNREFERENCED_PARAMETER(fvf);
    UNREFERENCED_PARAMETER(data);
    UNREFERENCED_PARAMETER(vertexCount);
    blg::trace("IDirect3DDevice7::DrawIndexedPrimitiveStrided vertices=%lu indices=%lu", static_cast<unsigned long>(vertexCount), static_cast<unsigned long>(indexCount));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DPRIMITIVETYPE, DWORD, D3DDRAWPRIMITIVESTRIDEDDATA *, DWORD, WORD *, DWORD, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[30])(wrapper->real, primitive, fvf, data, vertexCount, indices, indexCount, flags);
    }
    return DDERR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE deviceDrawPrimitiveVB(Wrapper *wrapper, D3DPRIMITIVETYPE primitive, IDirect3DVertexBuffer7 *buffer, DWORD startVertex, DWORD vertexCount, DWORD flags) {
    blg::trace("IDirect3DDevice7::DrawPrimitiveVB vertices=%lu", static_cast<unsigned long>(vertexCount));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DPRIMITIVETYPE, IDirect3DVertexBuffer7 *, DWORD, DWORD, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[31])(wrapper->real, primitive, buffer, startVertex, vertexCount, flags);
    }
    return DDERR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE deviceDrawIndexedPrimitiveVB(Wrapper *wrapper, D3DPRIMITIVETYPE primitive, IDirect3DVertexBuffer7 *buffer, DWORD startVertex, DWORD vertexCount, WORD *indices, DWORD indexCount, DWORD flags) {
    blg::trace("IDirect3DDevice7::DrawIndexedPrimitiveVB vertices=%lu indices=%lu", static_cast<unsigned long>(vertexCount), static_cast<unsigned long>(indexCount));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DPRIMITIVETYPE, IDirect3DVertexBuffer7 *, DWORD, DWORD, WORD *, DWORD, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[32])(wrapper->real, primitive, buffer, startVertex, vertexCount, indices, indexCount, flags);
    }
    return DDERR_UNSUPPORTED;
}

HRESULT STDMETHODCALLTYPE deviceComputeSphereVisibility(Wrapper *wrapper, D3DVECTOR *centers, D3DVALUE *radii, DWORD sphereCount, DWORD flags, DWORD *result) {
    UNREFERENCED_PARAMETER(centers);
    UNREFERENCED_PARAMETER(radii);
    UNREFERENCED_PARAMETER(flags);
    blg::trace("IDirect3DDevice7::ComputeSphereVisibility spheres=%lu", static_cast<unsigned long>(sphereCount));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DVECTOR *, D3DVALUE *, DWORD, DWORD, DWORD *);
        return reinterpret_cast<Function>(wrapper->realVtable[33])(wrapper->real, centers, radii, sphereCount, flags, result);
    }
    if (result == nullptr) return E_POINTER;
    ZeroMemory(result, sizeof(DWORD) * sphereCount);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceSetTextureStageState(Wrapper *wrapper, DWORD stage, D3DTEXTURESTAGESTATETYPE state, DWORD value) {
    blg::trace("IDirect3DDevice7::SetTextureStageState stage=%lu state=%lu value=0x%08lx", static_cast<unsigned long>(stage), static_cast<unsigned long>(state), static_cast<unsigned long>(value));
    if (wrapper->synthetic) {
        if (stage >= 8 || static_cast<DWORD>(state) >= 32) return DDERR_INVALIDPARAMS;
        wrapper->textureStageStates[stage][static_cast<DWORD>(state)] = value;
        return blg::renderer().setTextureStageState(stage, state, value);
    }
    using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD);
    return reinterpret_cast<Function>(wrapper->realVtable[37])(wrapper->real, stage, state, value);
}

HRESULT STDMETHODCALLTYPE deviceValidate(Wrapper *wrapper, DWORD *passes) {
    blg::trace("IDirect3DDevice7::ValidateDevice");
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD *);
        return reinterpret_cast<Function>(wrapper->realVtable[38])(wrapper->real, passes);
    }
    if (passes == nullptr) return E_POINTER;
    *passes = 1;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceApplyStateBlock(Wrapper *wrapper, DWORD handle) {
    blg::trace("IDirect3DDevice7::ApplyStateBlock handle=%lu", static_cast<unsigned long>(handle));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[39])(wrapper->real, handle);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceCaptureStateBlock(Wrapper *wrapper, DWORD handle) {
    blg::trace("IDirect3DDevice7::CaptureStateBlock handle=%lu", static_cast<unsigned long>(handle));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[40])(wrapper->real, handle);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceDeleteStateBlock(Wrapper *wrapper, DWORD handle) {
    blg::trace("IDirect3DDevice7::DeleteStateBlock handle=%lu", static_cast<unsigned long>(handle));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[41])(wrapper->real, handle);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceCreateStateBlock(Wrapper *wrapper, D3DSTATEBLOCKTYPE type, DWORD *handle) {
    blg::trace("IDirect3DDevice7::CreateStateBlock type=%lu", static_cast<unsigned long>(type));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, D3DSTATEBLOCKTYPE, DWORD *);
        return reinterpret_cast<Function>(wrapper->realVtable[42])(wrapper->real, type, handle);
    }
    if (handle == nullptr) return E_POINTER;
    *handle = 1;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceLoad(Wrapper *wrapper, IDirectDrawSurface7 *destination, POINT *destinationPoint, IDirectDrawSurface7 *source, RECT *sourceRect, DWORD flags) {
    blg::trace("IDirect3DDevice7::Load destination=%p source=%p flags=0x%08lx", destination, source, static_cast<unsigned long>(flags));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, IDirectDrawSurface7 *, POINT *, IDirectDrawSurface7 *, RECT *, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[43])(wrapper->real, destination, destinationPoint, source, sourceRect, flags);
    }
    UNREFERENCED_PARAMETER(destinationPoint);
    UNREFERENCED_PARAMETER(sourceRect);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceLightEnable(Wrapper *wrapper, DWORD index, WINBOOL enabled) {
    blg::trace("IDirect3DDevice7::LightEnable index=%lu enabled=%d", static_cast<unsigned long>(index), enabled ? 1 : 0);
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, WINBOOL);
        return reinterpret_cast<Function>(wrapper->realVtable[44])(wrapper->real, index, enabled);
    }
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetLightEnable(Wrapper *wrapper, DWORD index, WINBOOL *enabled) {
    blg::trace("IDirect3DDevice7::GetLightEnable index=%lu", static_cast<unsigned long>(index));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, WINBOOL *);
        return reinterpret_cast<Function>(wrapper->realVtable[45])(wrapper->real, index, enabled);
    }
    if (enabled == nullptr) return E_POINTER;
    *enabled = FALSE;
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceSetClipPlane(Wrapper *wrapper, DWORD index, D3DVALUE *plane) {
    blg::trace("IDirect3DDevice7::SetClipPlane index=%lu", static_cast<unsigned long>(index));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DVALUE *);
        return reinterpret_cast<Function>(wrapper->realVtable[46])(wrapper->real, index, plane);
    }
    return plane == nullptr ? E_POINTER : DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetClipPlane(Wrapper *wrapper, DWORD index, D3DVALUE *plane) {
    blg::trace("IDirect3DDevice7::GetClipPlane index=%lu", static_cast<unsigned long>(index));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, D3DVALUE *);
        return reinterpret_cast<Function>(wrapper->realVtable[47])(wrapper->real, index, plane);
    }
    if (plane == nullptr) return E_POINTER;
    ZeroMemory(plane, sizeof(D3DVALUE) * 4);
    return DD_OK;
}

HRESULT STDMETHODCALLTYPE deviceGetInfo(Wrapper *wrapper, DWORD infoID, void *info, DWORD infoSize) {
    blg::trace("IDirect3DDevice7::GetInfo id=%lu size=%lu", static_cast<unsigned long>(infoID), static_cast<unsigned long>(infoSize));
    if (!wrapper->synthetic) {
        using Function = HRESULT (STDMETHODCALLTYPE *)(void *, DWORD, void *, DWORD);
        return reinterpret_cast<Function>(wrapper->realVtable[48])(wrapper->real, infoID, info, infoSize);
    }
    if (info != nullptr && infoSize != 0) ZeroMemory(info, infoSize);
    return DD_OK;
}

template <typename Function>
Function resolveExport(HMODULE module, const char *name) {
    return reinterpret_cast<Function>(GetProcAddress(module, name));
}

HMODULE builtinDirectDraw() {
    static HMODULE module = nullptr;
    static LONG initialized = 0;
    if (InterlockedCompareExchange(&initialized, 1, 0) == 0) {
        char systemDirectory[MAX_PATH] = {};
        UINT length = GetSystemDirectoryA(systemDirectory, sizeof(systemDirectory));
        if (length > 0 && length + 12 < sizeof(systemDirectory)) {
            lstrcatA(systemDirectory, "\\ddraw.dll");
            module = LoadLibraryA(systemDirectory);
        }
        if (module == nullptr) {
            blg::log("Unable to load Wine's builtin ddraw.dll from the system directory, error=%lu", static_cast<unsigned long>(GetLastError()));
        } else {
            blg::log("Loaded backing ddraw.dll from %s", systemDirectory);
        }
        InterlockedExchange(&initialized, 2);
    }
    while (initialized == 1) {
        Sleep(0);
    }
    return module;
}

using DirectDrawCreateProc = HRESULT (WINAPI *)(GUID *, LPDIRECTDRAW *, IUnknown *);
using DirectDrawCreateExProc = HRESULT (WINAPI *)(GUID *, LPVOID *, REFIID, IUnknown *);
using DirectDrawCreateClipperProc = HRESULT (WINAPI *)(DWORD, LPDIRECTDRAWCLIPPER *, IUnknown *);
using DirectDrawEnumerateAProc = HRESULT (WINAPI *)(LPDDENUMCALLBACKA, LPVOID);
using DirectDrawEnumerateWProc = HRESULT (WINAPI *)(LPDDENUMCALLBACKW, LPVOID);
using DirectDrawEnumerateExAProc = HRESULT (WINAPI *)(LPDDENUMCALLBACKEXA, LPVOID, DWORD);
using DirectDrawEnumerateExWProc = HRESULT (WINAPI *)(LPDDENUMCALLBACKEXW, LPVOID, DWORD);

// Wine's builtin DirectDraw enumeration resolves back through the native
// override when this DLL is beside a 32-bit game.  Forwarding the export in
// that situation recurses before the game can reach DirectDrawCreateEx.
// Keep the adapter list deliberately narrow: the primary display is the only
// DirectDraw adapter exposed by this proxy, while the IDirectDraw7 object and
// its surfaces remain backed by Wine.
HRESULT enumeratePrimaryDisplayA(LPDDENUMCALLBACKA callback, LPVOID context) {
    if (callback == nullptr) {
        return E_POINTER;
    }

    static char description[] = "Boreal Legacy Graphics";
    static char name[] = "Boreal Primary Display";
    callback(nullptr, description, name, context);
    return DD_OK;
}

HRESULT enumeratePrimaryDisplayW(LPDDENUMCALLBACKW callback, LPVOID context) {
    if (callback == nullptr) {
        return E_POINTER;
    }

    static WCHAR description[] = L"Boreal Legacy Graphics";
    static WCHAR name[] = L"Boreal Primary Display";
    callback(nullptr, description, name, context);
    return DD_OK;
}

HRESULT enumeratePrimaryDisplayExA(LPDDENUMCALLBACKEXA callback, LPVOID context, DWORD flags) {
    UNREFERENCED_PARAMETER(flags);
    if (callback == nullptr) {
        return E_POINTER;
    }

    static char description[] = "Boreal Legacy Graphics";
    static char name[] = "Boreal Primary Display";
    callback(nullptr, description, name, context, nullptr);
    return DD_OK;
}

HRESULT enumeratePrimaryDisplayExW(LPDDENUMCALLBACKEXW callback, LPVOID context, DWORD flags) {
    UNREFERENCED_PARAMETER(flags);
    if (callback == nullptr) {
        return E_POINTER;
    }

    static WCHAR description[] = L"Boreal Legacy Graphics";
    static WCHAR name[] = L"Boreal Primary Display";
    callback(nullptr, description, name, context, nullptr);
    return DD_OK;
}

}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawCreateEx(
    GUID *guid,
    LPVOID *object,
    REFIID iid,
    IUnknown *outer
) {
    if (object == nullptr) {
        return E_POINTER;
    }
    *object = nullptr;
    logIID("DirectDrawCreateEx", iid);

    HMODULE module = builtinDirectDraw();
    auto function = resolveExport<DirectDrawCreateExProc>(module, "DirectDrawCreateEx");
    if (function == nullptr) {
        blg::log("Backing DirectDrawCreateEx export is unavailable");
        return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    }

    HRESULT result = function(guid, object, iid, outer);
    blg::log("DirectDrawCreateEx result=0x%08lx object=%p", static_cast<unsigned long>(result), object == nullptr ? nullptr : *object);
    if (SUCCEEDED(result) && *object != nullptr && IsEqualIID(iid, IID_IDirectDraw7)) {
        Wrapper *wrapped = createWrapper(*object, InterfaceKind::directDraw7);
        if (wrapped == nullptr) {
            releaseRaw(*object);
            *object = nullptr;
            return E_OUTOFMEMORY;
        }
        *object = wrapped;
        blg::log("DirectDrawCreateEx wrapped native IDirectDraw7; DDraw remains forwarded to Wine");
    }
    return result;
}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawCreate(
    GUID *guid,
    LPDIRECTDRAW *object,
    IUnknown *outer
) {
    if (object == nullptr) {
        return E_POINTER;
    }
    blg::log("DirectDrawCreate");
    auto function = resolveExport<DirectDrawCreateProc>(builtinDirectDraw(), "DirectDrawCreate");
    if (function == nullptr) {
        return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    }
    HRESULT result = function(guid, object, outer);
    blg::log("DirectDrawCreate result=0x%08lx object=%p", static_cast<unsigned long>(result), object == nullptr ? nullptr : *object);
    return result;
}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawCreateClipper(
    DWORD flags,
    LPDIRECTDRAWCLIPPER *clipper,
    IUnknown *outer
) {
    blg::log("DirectDrawCreateClipper flags=0x%08lx", static_cast<unsigned long>(flags));
    auto function = resolveExport<DirectDrawCreateClipperProc>(builtinDirectDraw(), "DirectDrawCreateClipper");
    if (function == nullptr) {
        return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    }
    return function(flags, clipper, outer);
}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawEnumerateA(LPDDENUMCALLBACKA callback, LPVOID context) {
    blg::log("DirectDrawEnumerateA");
    HRESULT result = enumeratePrimaryDisplayA(callback, context);
    blg::log("DirectDrawEnumerateA result=0x%08lx", static_cast<unsigned long>(result));
    return result;
}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawEnumerateW(LPDDENUMCALLBACKW callback, LPVOID context) {
    blg::log("DirectDrawEnumerateW");
    HRESULT result = enumeratePrimaryDisplayW(callback, context);
    blg::log("DirectDrawEnumerateW result=0x%08lx", static_cast<unsigned long>(result));
    return result;
}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawEnumerateExA(LPDDENUMCALLBACKEXA callback, LPVOID context, DWORD flags) {
    blg::log("DirectDrawEnumerateExA flags=0x%08lx", static_cast<unsigned long>(flags));
    HRESULT result = enumeratePrimaryDisplayExA(callback, context, flags);
    blg::log("DirectDrawEnumerateExA result=0x%08lx", static_cast<unsigned long>(result));
    return result;
}

extern "C" __declspec(dllexport) HRESULT WINAPI DirectDrawEnumerateExW(LPDDENUMCALLBACKEXW callback, LPVOID context, DWORD flags) {
    blg::log("DirectDrawEnumerateExW flags=0x%08lx", static_cast<unsigned long>(flags));
    HRESULT result = enumeratePrimaryDisplayExW(callback, context, flags);
    blg::log("DirectDrawEnumerateExW result=0x%08lx", static_cast<unsigned long>(result));
    return result;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    UNREFERENCED_PARAMETER(instance);
    UNREFERENCED_PARAMETER(reserved);
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        OutputDebugStringA("Boreal Legacy Graphics proxy loaded; architecture=x86 backend=wine-ddraw tracer=d3d7\n");
    }
    return TRUE;
}
