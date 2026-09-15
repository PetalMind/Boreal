#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <ddraw.h>
#include <d3d.h>

namespace blg {

class D3D11Renderer {
public:
    D3D11Renderer();
    ~D3D11Renderer();

    D3D11Renderer(const D3D11Renderer &) = delete;
    D3D11Renderer &operator=(const D3D11Renderer &) = delete;

    void setWindow(HWND window);
    void setDisplayMode(DWORD width, DWORD height);

    HRESULT initialize();
    HRESULT beginScene();
    HRESULT endScene();
    HRESULT clear(DWORD count, D3DRECT *rects, DWORD flags, D3DCOLOR color, D3DVALUE z, DWORD stencil);
    HRESULT setTransform(D3DTRANSFORMSTATETYPE state, const D3DMATRIX *matrix);
    HRESULT setViewport(const D3DVIEWPORT7 *viewport);
    HRESULT setRenderState(D3DRENDERSTATETYPE state, DWORD value);
    HRESULT drawPrimitive(D3DPRIMITIVETYPE primitive, DWORD fvf, const void *vertices, DWORD vertexCount, DWORD flags);
    HRESULT drawIndexedPrimitive(
        D3DPRIMITIVETYPE primitive,
        DWORD fvf,
        const void *vertices,
        DWORD vertexCount,
        const WORD *indices,
        DWORD indexCount,
        DWORD flags
    );
    HRESULT setTexture(
        DWORD stage,
        const void *identity,
        DWORD version,
        DWORD width,
        DWORD height,
        DWORD pitch,
        DWORD bitsPerPixel,
        DWORD redMask,
        DWORD greenMask,
        DWORD blueMask,
        DWORD alphaMask,
        const void *pixels
    );
    HRESULT activateCachedTexture(DWORD stage, const void *identity, DWORD version);
    HRESULT activateCachedTextureByIdentity(DWORD stage, const void *identity);
    void recordNativeTextureUpload(ULONGLONG elapsedMilliseconds);
    void clearTexture(DWORD stage, const void *identity);
    HRESULT setTextureStageState(DWORD stage, D3DTEXTURESTAGESTATETYPE state, DWORD value);

private:
    struct Impl;
    Impl *impl_;
};

D3D11Renderer &renderer();

} // namespace blg
