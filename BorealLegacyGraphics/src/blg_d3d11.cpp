#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "blg_d3d11.h"
#include "blg_log.h"

#define D3DCOLORVALUE_DEFINED
#include <d3d.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <memory>
#include <vector>

namespace blg {

namespace {

constexpr IID kIIDIDXGIFactory1 = {
    0x770aae78, 0xf26f, 0x4dba,
    {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}
};

constexpr IID kIIDIDXGIDevice1 = {
    0x77db970f, 0x6276, 0x48ba,
    {0xba, 0x28, 0x07, 0x01, 0x43, 0xb4, 0x39, 0x2c}
};

constexpr IID kIIDID3D11Texture2D = {
    0x6f15aaf2, 0xd208, 0x4e89,
    {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}
};

// D3DTADDRESS_MIRRORONCE was added after the older Direct3D 7 headers used
// by some MinGW distributions. Its ABI value is stable across the D3D headers.
constexpr DWORD kD3DTextureAddressMirrorOnce = 5;

using CreateDXGIFactory1Proc = HRESULT (WINAPI *)(REFIID, void **);
using D3D11CreateDeviceProc = HRESULT (WINAPI *)(
    IDXGIAdapter *,
    D3D_DRIVER_TYPE,
    HMODULE,
    UINT,
    const D3D_FEATURE_LEVEL *,
    UINT,
    UINT,
    ID3D11Device **,
    D3D_FEATURE_LEVEL *,
    ID3D11DeviceContext **
);
using D3DCompileProc = HRESULT (WINAPI *)(
    const void *, SIZE_T, const char *, const D3D_SHADER_MACRO *, ID3DInclude *,
    const char *, const char *, UINT, UINT, ID3DBlob **, ID3DBlob **
);

struct LegacyVertex {
    float x;
    float y;
    float z;
    float rhw;
    DWORD color;
    float u;
    float v;
    float u1;
    float v1;
};

struct VertexLayout {
    size_t stride = 0;
    size_t colorOffset = static_cast<size_t>(-1);
    size_t textureOffset = static_cast<size_t>(-1);
    size_t texture1Offset = static_cast<size_t>(-1);
    bool transformed = false;
};

bool buildVertexLayout(DWORD fvf, VertexLayout *layout) {
    if (layout == nullptr) return false;
    *layout = {};

    const DWORD position = fvf & D3DFVF_POSITION_MASK;
    size_t offset = 0;
    if (position == D3DFVF_XYZRHW) {
        layout->transformed = true;
        offset = sizeof(float) * 4;
    } else if (position == D3DFVF_XYZ) {
        offset = sizeof(float) * 3;
    } else {
        return false;
    }

    if ((fvf & D3DFVF_NORMAL) != 0) offset += sizeof(float) * 3;
    if ((fvf & D3DFVF_RESERVED1) != 0) offset += sizeof(float);
    if ((fvf & D3DFVF_DIFFUSE) != 0) {
        layout->colorOffset = offset;
        offset += sizeof(DWORD);
    }
    if ((fvf & D3DFVF_SPECULAR) != 0) offset += sizeof(DWORD);

    const DWORD textureCount = (fvf & D3DFVF_TEXCOUNT_MASK) >> D3DFVF_TEXCOUNT_SHIFT;
    for (DWORD index = 0; index < textureCount; ++index) {
        const DWORD format = (fvf >> (16 + index * 2)) & 0x3u;
        const size_t components = format == D3DFVF_TEXTUREFORMAT1 ? 1 :
                                   format == D3DFVF_TEXTUREFORMAT3 ? 3 :
                                   format == D3DFVF_TEXTUREFORMAT4 ? 4 : 2;
        if (index == 0) layout->textureOffset = offset;
        if (index == 1) layout->texture1Offset = offset;
        offset += sizeof(float) * components;
    }
    layout->stride = offset;
    return layout->stride != 0;
}

struct Float4 {
    float x;
    float y;
    float z;
    float w;
};

Float4 transform(const D3DMATRIX &matrix, Float4 value) {
    return {
        value.x * matrix._11 + value.y * matrix._21 + value.z * matrix._31 + value.w * matrix._41,
        value.x * matrix._12 + value.y * matrix._22 + value.z * matrix._32 + value.w * matrix._42,
        value.x * matrix._13 + value.y * matrix._23 + value.z * matrix._33 + value.w * matrix._43,
        value.x * matrix._14 + value.y * matrix._24 + value.z * matrix._34 + value.w * matrix._44,
    };
}

struct ViewportConstants {
    float width;
    float height;
    float textureWidth;
    float textureHeight;
};

struct MatrixConstants {
    D3DMATRIX world;
    D3DMATRIX view;
    D3DMATRIX projection;
};

template <typename T>
void safeRelease(T *&value) {
    if (value != nullptr) {
        value->Release();
        value = nullptr;
    }
}

DWORD colorChannel(D3DCOLOR color, DWORD shift) {
    return (color >> shift) & 0xffu;
}

const char *primitiveName(D3DPRIMITIVETYPE primitive) {
    switch (primitive) {
    case D3DPT_POINTLIST: return "pointlist";
    case D3DPT_LINELIST: return "linelist";
    case D3DPT_LINESTRIP: return "linestrip";
    case D3DPT_TRIANGLELIST: return "trianglelist";
    case D3DPT_TRIANGLESTRIP: return "trianglestrip";
    case D3DPT_TRIANGLEFAN: return "trianglefan";
    case D3DPT_FORCE_DWORD: return "force_dword";
    }
    return "unknown";
}

} // namespace

struct D3D11Renderer::Impl {
    static constexpr DWORD kVertexBufferCapacity = 1024u * 1024u;
    static constexpr DWORD kIndexBufferCapacity = 2u * 1024u * 1024u;

    struct CachedTexture {
        const void *identity = nullptr;
        DWORD version = 0;
        ID3D11Texture2D *texture = nullptr;
        ID3D11ShaderResourceView *view = nullptr;
        DWORD width = 0;
        DWORD height = 0;
        std::shared_ptr<std::vector<BYTE>> pixels;
        size_t bytes = 0;
        ULONGLONG lastUsed = 0;
    };

    struct BlendStateCacheEntry {
        bool alphaEnabled = false;
        D3D11_BLEND sourceBlend = D3D11_BLEND_ONE;
        D3D11_BLEND destinationBlend = D3D11_BLEND_ZERO;
        ID3D11BlendState *state = nullptr;
    };

    struct DepthStateCacheEntry {
        bool enabled = false;
        bool writeEnabled = false;
        D3D11_COMPARISON_FUNC function = D3D11_COMPARISON_ALWAYS;
        ID3D11DepthStencilState *state = nullptr;
    };

    struct RasterizerStateCacheEntry {
        D3D11_CULL_MODE cullMode = D3D11_CULL_NONE;
        ID3D11RasterizerState *state = nullptr;
    };

    static constexpr size_t kMaximumTextureCacheBytes = 256u * 1024u * 1024u;

    HWND window = nullptr;
    DWORD width = 800;
    DWORD height = 600;
    bool initialized = false;
    bool inScene = false;
    bool shaderReady = false;
    bool zEnabled = true;
    bool zWriteEnabled = true;
    bool alphaEnabled = true;
    D3D11_COMPARISON_FUNC zFunction = D3D11_COMPARISON_LESS_EQUAL;
    D3D11_BLEND sourceBlend = D3D11_BLEND_SRC_ALPHA;
    D3D11_BLEND destinationBlend = D3D11_BLEND_INV_SRC_ALPHA;
    D3D11_CULL_MODE cullMode = D3D11_CULL_NONE;
    D3DVIEWPORT7 viewport = {0, 0, 800, 600, 0.0f, 1.0f};
    MatrixConstants matrices = {};

    HMODULE dxgiModule = nullptr;
    HMODULE d3d11Module = nullptr;
    HMODULE compilerModule = nullptr;
    IDXGIFactory1 *factory = nullptr;
    IDXGIAdapter1 *adapter = nullptr;
    IDXGISwapChain *swapChain = nullptr;
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    ID3D11Texture2D *backBuffer = nullptr;
    ID3D11RenderTargetView *renderTarget = nullptr;
    ID3D11Texture2D *depthTexture = nullptr;
    ID3D11DepthStencilView *depthStencil = nullptr;
    ID3D11Buffer *vertexBuffer = nullptr;
    ID3D11Buffer *indexBuffer = nullptr;
    ID3D11Buffer *viewportBuffer = nullptr;
    ID3D11Buffer *matrixBuffer = nullptr;
    ID3D11Texture2D *texture = nullptr;
    ID3D11ShaderResourceView *textureView = nullptr;
    ID3D11SamplerState *samplerState = nullptr;
    ID3D11InputLayout *inputLayout = nullptr;
    ID3D11VertexShader *vertexShader = nullptr;
    ID3D11PixelShader *pixelShader = nullptr;
    ID3D11BlendState *blendState = nullptr;
    ID3D11DepthStencilState *depthState = nullptr;
    ID3D11RasterizerState *rasterizerState = nullptr;
    std::vector<BlendStateCacheEntry> blendStateCache;
    std::vector<DepthStateCacheEntry> depthStateCache;
    std::vector<RasterizerStateCacheEntry> rasterizerStateCache;
    const void *textureIdentity = nullptr;
    DWORD textureVersion = 0;
    bool textureEnabled = false;
    DWORD textureWidth = 0;
    DWORD textureHeight = 0;
    DWORD textureColorOp = D3DTOP_MODULATE;
    DWORD textureColorArg1 = D3DTA_TEXTURE;
    DWORD textureColorArg2 = D3DTA_DIFFUSE;
    DWORD textureAlphaOp = D3DTOP_MODULATE;
    DWORD textureAlphaArg1 = D3DTA_TEXTURE;
    DWORD textureAlphaArg2 = D3DTA_DIFFUSE;
    DWORD textureCoordinateIndex = 0;
    DWORD textureAddressU = D3DTADDRESS_WRAP;
    DWORD textureAddressV = D3DTADDRESS_WRAP;
    DWORD textureStage1ColorOp = D3DTOP_DISABLE;
    DWORD textureStage1ColorArg1 = D3DTA_TEXTURE;
    DWORD textureStage1ColorArg2 = D3DTA_CURRENT;
    DWORD textureStage1AlphaOp = D3DTOP_DISABLE;
    DWORD textureStage1AlphaArg1 = D3DTA_TEXTURE;
    DWORD textureStage1AlphaArg2 = D3DTA_CURRENT;
    DWORD textureStage1CoordinateIndex = 1;
    DWORD textureStage1AddressU = D3DTADDRESS_WRAP;
    DWORD textureStage1AddressV = D3DTADDRESS_WRAP;
    bool softwareRendering = false;
    bool vertexBakedTextures = true;
    bool gpuTextureSampling = false;
    bool gpuTextureDynamicLinear = false;
    bool geometryCulling = false;
    DWORD presentIntervalMilliseconds = 0;
    ULONGLONG lastPresentRequestMilliseconds = 0;
    bool gpuTextureEnabled = false;
    const void *textureStage1Identity = nullptr;
    DWORD textureStage1Version = 0;
    bool textureStage1Enabled = false;
    DWORD textureStage1Width = 0;
    DWORD textureStage1Height = 0;
    std::vector<DWORD> softwareColor;
    std::vector<float> softwareDepth;
    // Keep active surface texels shared with the cache. Sacred changes the
    // current material thousands of times per second; copying each cached
    // image into a second vector makes texture binding a hidden frame cost.
    std::shared_ptr<const std::vector<BYTE>> softwareTexturePixels;
    std::shared_ptr<const std::vector<BYTE>> softwareTextureStage1Pixels;
    std::vector<CachedTexture> textureCache;
    size_t textureCacheBytes = 0;
    ULONGLONG textureUseSequence = 0;
    ULONGLONG presentCount = 0;
    ULONGLONG presentSkippedCount = 0;
    ULONGLONG fpsWindowStartCount = 0;
    ULONGLONG fpsWindowStartMilliseconds = 0;
    ULONGLONG sceneStartMilliseconds = 0;
    ULONGLONG fpsWindowSceneMilliseconds = 0;
    ULONGLONG fpsWindowPresentMilliseconds = 0;
    ULONGLONG fpsWindowPresentSkipped = 0;
    ULONGLONG fpsWindowDrawCalls = 0;
    ULONGLONG fpsWindowTextureUploads = 0;
    ULONGLONG fpsWindowTextureCacheHits = 0;
    ULONGLONG fpsWindowTextureMilliseconds = 0;
    ULONGLONG fpsWindowNativeTextureCalls = 0;
    ULONGLONG fpsWindowNativeTextureMilliseconds = 0;
    ULONGLONG fpsWindowDrawMilliseconds = 0;
    ULONGLONG fpsWindowConversionMilliseconds = 0;
    ULONGLONG fpsWindowSubmitMilliseconds = 0;
    ULONGLONG fpsWindowBatchSubmissions = 0;
    ULONGLONG fpsWindowBatchFlushes = 0;
    ULONGLONG fpsWindowBatchVertices = 0;
    ULONGLONG fpsWindowBatchIndices = 0;
    ULONGLONG fpsWindowGeometryCulled = 0;
    ULONGLONG fpsWindowTriangleListCalls = 0;
    ULONGLONG fpsWindowTriangleStripCalls = 0;
    ULONGLONG fpsWindowTriangleFanCalls = 0;
    ULONGLONG fpsWindowOtherPrimitiveCalls = 0;
    bool fpsTelemetryReady = false;
    bool pipelineStaticBound = false;
    bool blendStateDirty = true;
    bool depthStateDirty = true;
    bool rasterizerStateDirty = true;
    bool viewportDirty = true;
    bool textureBindingDirty = true;
    D3D11_PRIMITIVE_TOPOLOGY boundTopology = D3D11_PRIMITIVE_TOPOLOGY_UNDEFINED;
    DWORD vertexWriteCursor = 0;
    DWORD indexWriteCursor = 0;
    std::vector<LegacyVertex> pendingVertices;
    std::vector<WORD> pendingIndices;
    // Sacred submits thousands of small strips per frame. Reuse the conversion
    // storage so each submission does not enter the heap allocator.
    std::vector<LegacyVertex> convertedVerticesScratch;
    std::vector<WORD> primitiveIndicesScratch;
    const void *pendingTextureIdentity = nullptr;
    bool pendingTextureEnabled = false;

    HRESULT fail(const char *operation, HRESULT result) {
        blg::log("D3D11 %s failed result=0x%08lx", operation, static_cast<unsigned long>(result));
        return result;
    }

    void releaseCachedTexture(CachedTexture &entry) {
        textureCacheBytes -= std::min(textureCacheBytes, entry.bytes);
        safeRelease(entry.view);
        safeRelease(entry.texture);
        entry.pixels.reset();
        entry.bytes = 0;
    }

    void trimTextureCache() {
        while (textureCacheBytes > kMaximumTextureCacheBytes && !textureCache.empty()) {
            auto oldest = std::min_element(
                textureCache.begin(),
                textureCache.end(),
                [](const CachedTexture &left, const CachedTexture &right) {
                    return left.lastUsed < right.lastUsed;
                }
            );
            releaseCachedTexture(*oldest);
            textureCache.erase(oldest);
        }
    }

    void removeCachedTextureVersions(const void *identity) {
        for (auto iterator = textureCache.begin(); iterator != textureCache.end();) {
            if (iterator->identity != identity) {
                ++iterator;
                continue;
            }
            releaseCachedTexture(*iterator);
            iterator = textureCache.erase(iterator);
        }
    }

    CachedTexture *findCachedTexture(const void *identity, DWORD version) {
        for (auto &entry : textureCache) {
            if (entry.identity == identity && entry.version == version) return &entry;
        }
        return nullptr;
    }

    CachedTexture *findCachedTextureIdentity(const void *identity) {
        for (auto &entry : textureCache) {
            if (entry.identity == identity) return &entry;
        }
        return nullptr;
    }

    void activateCachedTexture(CachedTexture &entry) {
        if (entry.pixels == nullptr || entry.pixels->empty()) return;
        if (gpuTextureSampling && (entry.texture == nullptr || entry.view == nullptr)) return;
        if (textureEnabled && textureIdentity == entry.identity && textureVersion == entry.version
            && texture == entry.texture && textureView == entry.view) {
            entry.lastUsed = ++textureUseSequence;
            return;
        }
        const bool wasTextureEnabled = textureEnabled;
        safeRelease(textureView);
        safeRelease(texture);
        if (entry.texture != nullptr) entry.texture->AddRef();
        if (entry.view != nullptr) entry.view->AddRef();
        texture = entry.texture;
        textureView = entry.view;
        textureIdentity = entry.identity;
        textureVersion = entry.version;
        textureWidth = entry.width;
        textureHeight = entry.height;
        softwareTexturePixels = entry.pixels;
        entry.lastUsed = ++textureUseSequence;
        textureEnabled = true;
        gpuTextureEnabled = gpuTextureSampling && texture != nullptr && textureView != nullptr;
        textureBindingDirty = true;
        if (!wasTextureEnabled) updateViewportBuffer();
    }

    void activateCachedTextureStage1(CachedTexture &entry) {
        if (entry.pixels == nullptr || entry.pixels->empty()) return;
        textureStage1Identity = entry.identity;
        textureStage1Version = entry.version;
        textureStage1Width = entry.width;
        textureStage1Height = entry.height;
        softwareTextureStage1Pixels = entry.pixels;
        textureStage1Enabled = true;
        entry.lastUsed = ++textureUseSequence;
    }

    HRESULT loadDevice() {
        char textureMode[8] = {};
        gpuTextureSampling = GetEnvironmentVariableA("BLG_TEXTURE_SAMPLING", textureMode, sizeof(textureMode)) > 0
            && textureMode[0] == '1';
        char softwareMode[8] = {};
        softwareRendering = GetEnvironmentVariableA("BLG_SOFTWARE_RENDERING", softwareMode, sizeof(softwareMode)) > 0
            && softwareMode[0] == '1';
        char textureStorage[32] = {};
        gpuTextureDynamicLinear = gpuTextureSampling
            && GetEnvironmentVariableA("BLG_TEXTURE_STORAGE", textureStorage, sizeof(textureStorage)) > 0
            && _stricmp(textureStorage, "dynamic-linear") == 0;
        vertexBakedTextures = !gpuTextureSampling && !softwareRendering;
        char geometryCullingMode[8] = {};
        geometryCulling = GetEnvironmentVariableA(
            "BLG_GEOMETRY_CULLING",
            geometryCullingMode,
            sizeof(geometryCullingMode)
        ) > 0 && geometryCullingMode[0] == '1';
        char presentInterval[16] = {};
        const DWORD presentIntervalLength = GetEnvironmentVariableA(
            "BLG_PRESENT_INTERVAL_MS",
            presentInterval,
            sizeof(presentInterval)
        );
        if (presentIntervalLength > 0 && presentIntervalLength < sizeof(presentInterval)) {
            char *end = nullptr;
            const unsigned long parsed = std::strtoul(presentInterval, &end, 10);
            if (end != presentInterval && *end == '\0' && parsed >= 1 && parsed <= 1000) {
                presentIntervalMilliseconds = static_cast<DWORD>(parsed);
            }
        }
        blg::log(
            "D3D11 texture mode=%s storage=%s presentIntervalMs=%lu",
            gpuTextureSampling ? "gpu-sampled" : softwareRendering ? "software-raster" : "vertex-baked",
            !gpuTextureSampling ? "cpu-cache" : gpuTextureDynamicLinear ? "dynamic-linear" : "immutable",
            static_cast<unsigned long>(presentIntervalMilliseconds)
        );
        blg::log("D3D11 geometry culling=%s", geometryCulling ? "viewport-only" : "off");
        dxgiModule = LoadLibraryA("dxgi.dll");
        d3d11Module = LoadLibraryA("d3d11.dll");
        if (dxgiModule == nullptr || d3d11Module == nullptr) {
            return fail("LoadLibrary dxgi/d3d11", HRESULT_FROM_WIN32(GetLastError()));
        }

        auto createFactory = reinterpret_cast<CreateDXGIFactory1Proc>(GetProcAddress(dxgiModule, "CreateDXGIFactory1"));
        auto createDevice = reinterpret_cast<D3D11CreateDeviceProc>(GetProcAddress(d3d11Module, "D3D11CreateDevice"));
        if (createFactory == nullptr || createDevice == nullptr) {
            return fail("resolve DXGI/D3D11 exports", HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND));
        }
        HMODULE metalModule = GetModuleHandleA("winemetal.dll");
        FARPROC createMetalView = metalModule == nullptr
            ? nullptr
            : GetProcAddress(metalModule, "CreateMetalViewFromHWND");
        blg::log(
            "DXMT winemetal module=%p CreateMetalViewFromHWND=%p",
            metalModule,
            createMetalView
        );

        HRESULT result = createFactory(kIIDIDXGIFactory1, reinterpret_cast<void **>(&factory));
        if (FAILED(result)) {
            return fail("CreateDXGIFactory1", result);
        }

        result = factory->EnumAdapters1(0, &adapter);
        if (FAILED(result)) {
            safeRelease(factory);
            return fail("EnumAdapters1", result);
        }

        const D3D_FEATURE_LEVEL levels[] = {
            D3D_FEATURE_LEVEL_11_0,
            D3D_FEATURE_LEVEL_10_1,
            D3D_FEATURE_LEVEL_10_0
        };
        D3D_FEATURE_LEVEL selectedLevel = D3D_FEATURE_LEVEL_9_1;
        result = createDevice(
            adapter,
            D3D_DRIVER_TYPE_UNKNOWN,
            nullptr,
            0,
            levels,
            ARRAYSIZE(levels),
            D3D11_SDK_VERSION,
            &device,
            &selectedLevel,
            &context
        );
        if (FAILED(result)) {
            safeRelease(adapter);
            safeRelease(factory);
            return fail("D3D11CreateDevice", result);
        }
        IDXGIDevice1 *dxgiDevice = nullptr;
        HRESULT latencyQueryResult = device->QueryInterface(
            kIIDIDXGIDevice1,
            reinterpret_cast<void **>(&dxgiDevice)
        );
        if (SUCCEEDED(latencyQueryResult) && dxgiDevice != nullptr) {
            // Keep enough in-flight work for Sacred's many small submissions;
            // lower values make DXMT wait in PresentBoundary before the GPU
            // has drained the current scene. The override is intentionally
            // diagnostic: the normal profile stays on the validated value.
            UINT preferredFrameLatency = 16;
            char frameLatency[16] = {};
            const DWORD frameLatencyLength = GetEnvironmentVariableA(
                "BLG_FRAME_LATENCY",
                frameLatency,
                sizeof(frameLatency)
            );
            if (frameLatencyLength > 0 && frameLatencyLength < sizeof(frameLatency)) {
                char *end = nullptr;
                const unsigned long parsed = std::strtoul(frameLatency, &end, 10);
                if (end != frameLatency && *end == '\0' && parsed >= 1 && parsed <= 31) {
                    preferredFrameLatency = static_cast<UINT>(parsed);
                }
            }
            HRESULT latencyResult = dxgiDevice->SetMaximumFrameLatency(preferredFrameLatency);
            blg::log(
                "D3D11 frame latency requested=%u result=0x%08lx",
                preferredFrameLatency,
                static_cast<unsigned long>(latencyResult)
            );
            safeRelease(dxgiDevice);
        } else {
            blg::log(
                "D3D11 frame latency interface unavailable result=0x%08lx",
                static_cast<unsigned long>(latencyQueryResult)
            );
        }
        blg::log("D3D11 device initialized featureLevel=0x%04x", static_cast<unsigned int>(selectedLevel));
        return S_OK;
    }

    HRESULT createSwapChain() {
        if (window == nullptr) {
            return fail("swapchain window", E_INVALIDARG);
        }

        RECT clientRect = {};
        if (GetClientRect(window, &clientRect) && clientRect.right > 0 && clientRect.bottom > 0) {
            if (width == 0) width = static_cast<DWORD>(clientRect.right);
            if (height == 0) height = static_cast<DWORD>(clientRect.bottom);
        }
        width = std::max<DWORD>(width, 1);
        height = std::max<DWORD>(height, 1);

        // DXMT presents through CAMetalLayer.  Keep the legacy discard chain
        // as the compatibility default, but expose the native flip model as
        // a runtime probe: DXMT can retain the extra backbuffers instead of
        // forcing the presenter to recycle a single D3D11 buffer while the
        // Metal drawable queue is draining.
        bool flipSwapChain = false;
        char swapChainMode[32] = {};
        if (GetEnvironmentVariableA("BLG_SWAPCHAIN_MODE", swapChainMode, sizeof(swapChainMode)) > 0) {
            flipSwapChain = _stricmp(swapChainMode, "flip-discard") == 0;
        }

        DXGI_SWAP_CHAIN_DESC description = {};
        description.BufferCount = flipSwapChain ? 3 : 1;
        description.BufferDesc.Width = width;
        description.BufferDesc.Height = height;
        description.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        description.OutputWindow = window;
        description.SampleDesc.Count = 1;
        description.Windowed = TRUE;
        description.SwapEffect = flipSwapChain
            ? DXGI_SWAP_EFFECT_FLIP_DISCARD
            : DXGI_SWAP_EFFECT_DISCARD;

        blg::log(
            "D3D11 swapchain mode=%s buffers=%lu",
            flipSwapChain ? "flip-discard" : "discard",
            static_cast<unsigned long>(description.BufferCount)
        );

        HRESULT result = factory->CreateSwapChain(device, &description, &swapChain);
        if (FAILED(result)) {
            return fail("CreateSwapChain", result);
        }
        result = swapChain->GetBuffer(0, kIIDID3D11Texture2D, reinterpret_cast<void **>(&backBuffer));
        if (FAILED(result)) {
            return fail("IDXGISwapChain::GetBuffer", result);
        }
        result = device->CreateRenderTargetView(backBuffer, nullptr, &renderTarget);
        if (FAILED(result)) {
            return fail("CreateRenderTargetView", result);
        }

        D3D11_TEXTURE2D_DESC depthDescription = {};
        depthDescription.Width = width;
        depthDescription.Height = height;
        depthDescription.MipLevels = 1;
        depthDescription.ArraySize = 1;
        depthDescription.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
        depthDescription.SampleDesc.Count = 1;
        depthDescription.Usage = D3D11_USAGE_DEFAULT;
        depthDescription.BindFlags = D3D11_BIND_DEPTH_STENCIL;
        result = device->CreateTexture2D(&depthDescription, nullptr, &depthTexture);
        if (SUCCEEDED(result)) {
            result = device->CreateDepthStencilView(depthTexture, nullptr, &depthStencil);
        }
        if (FAILED(result)) {
            blg::log("D3D11 depth buffer unavailable result=0x%08lx; continuing without depth", static_cast<unsigned long>(result));
            safeRelease(depthTexture);
            safeRelease(depthStencil);
        }

        viewport.dwWidth = width;
        viewport.dwHeight = height;
        return S_OK;
    }

    HRESULT createStates() {
        D3D11_BUFFER_DESC vertexDescription = {};
        vertexDescription.ByteWidth = sizeof(LegacyVertex) * kVertexBufferCapacity;
        vertexDescription.Usage = D3D11_USAGE_DYNAMIC;
        vertexDescription.BindFlags = D3D11_BIND_VERTEX_BUFFER;
        vertexDescription.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        HRESULT result = device->CreateBuffer(&vertexDescription, nullptr, &vertexBuffer);
        if (FAILED(result)) return fail("CreateBuffer vertex", result);

        D3D11_BUFFER_DESC indexDescription = {};
        indexDescription.ByteWidth = sizeof(WORD) * kIndexBufferCapacity;
        indexDescription.Usage = D3D11_USAGE_DYNAMIC;
        indexDescription.BindFlags = D3D11_BIND_INDEX_BUFFER;
        indexDescription.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        result = device->CreateBuffer(&indexDescription, nullptr, &indexBuffer);
        if (FAILED(result)) return fail("CreateBuffer index", result);

        D3D11_BUFFER_DESC viewportDescription = {};
        viewportDescription.ByteWidth = sizeof(ViewportConstants);
        viewportDescription.Usage = D3D11_USAGE_DYNAMIC;
        viewportDescription.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        viewportDescription.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        result = device->CreateBuffer(&viewportDescription, nullptr, &viewportBuffer);
        if (FAILED(result)) return fail("CreateBuffer viewport", result);

        D3D11_BUFFER_DESC matrixDescription = {};
        matrixDescription.ByteWidth = sizeof(MatrixConstants);
        matrixDescription.Usage = D3D11_USAGE_DYNAMIC;
        matrixDescription.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
        matrixDescription.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        result = device->CreateBuffer(&matrixDescription, nullptr, &matrixBuffer);
        if (FAILED(result)) return fail("CreateBuffer matrices", result);

        D3D11_BLEND_DESC blendDescription = {};
        blendDescription.RenderTarget[0].BlendEnable = TRUE;
        blendDescription.RenderTarget[0].SrcBlend = sourceBlend;
        blendDescription.RenderTarget[0].DestBlend = destinationBlend;
        blendDescription.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
        blendDescription.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        blendDescription.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
        blendDescription.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
        blendDescription.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        result = device->CreateBlendState(&blendDescription, &blendState);
        if (FAILED(result)) return fail("CreateBlendState", result);
        blendState->AddRef();
        blendStateCache.push_back({alphaEnabled, sourceBlend, destinationBlend, blendState});

        D3D11_DEPTH_STENCIL_DESC depthDescription = {};
        depthDescription.DepthEnable = zEnabled;
        depthDescription.DepthWriteMask = zWriteEnabled ? D3D11_DEPTH_WRITE_MASK_ALL : D3D11_DEPTH_WRITE_MASK_ZERO;
        depthDescription.DepthFunc = zFunction;
        depthDescription.StencilEnable = FALSE;
        result = device->CreateDepthStencilState(&depthDescription, &depthState);
        if (FAILED(result)) return fail("CreateDepthStencilState", result);
        depthState->AddRef();
        depthStateCache.push_back({zEnabled, zWriteEnabled, zFunction, depthState});

        D3D11_RASTERIZER_DESC rasterDescription = {};
        rasterDescription.FillMode = D3D11_FILL_SOLID;
        rasterDescription.CullMode = cullMode;
        rasterDescription.DepthClipEnable = TRUE;
        result = device->CreateRasterizerState(&rasterDescription, &rasterizerState);
        if (FAILED(result)) return fail("CreateRasterizerState", result);
        rasterizerState->AddRef();
        rasterizerStateCache.push_back({cullMode, rasterizerState});

        D3D11_SAMPLER_DESC samplerDescription = {};
        samplerDescription.Filter = D3D11_FILTER_MIN_MAG_LINEAR_MIP_POINT;
        samplerDescription.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
        samplerDescription.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
        samplerDescription.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
        samplerDescription.MinLOD = 0.0f;
        samplerDescription.MaxLOD = D3D11_FLOAT32_MAX;
        result = device->CreateSamplerState(&samplerDescription, &samplerState);
        if (FAILED(result)) return fail("CreateSamplerState", result);
        return S_OK;
    }

    HRESULT rebuildBlendState() {
        for (const auto &entry : blendStateCache) {
            if (entry.alphaEnabled != alphaEnabled || entry.sourceBlend != sourceBlend
                || entry.destinationBlend != destinationBlend) {
                continue;
            }
            safeRelease(blendState);
            entry.state->AddRef();
            blendState = entry.state;
            blendStateDirty = true;
            return S_OK;
        }
        D3D11_BLEND_DESC description = {};
        description.RenderTarget[0].BlendEnable = alphaEnabled ? TRUE : FALSE;
        description.RenderTarget[0].SrcBlend = sourceBlend;
        description.RenderTarget[0].DestBlend = destinationBlend;
        description.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
        description.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
        description.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
        description.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
        description.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
        ID3D11BlendState *newState = nullptr;
        HRESULT result = device->CreateBlendState(&description, &newState);
        if (SUCCEEDED(result)) {
            newState->AddRef();
            blendStateCache.push_back({alphaEnabled, sourceBlend, destinationBlend, newState});
            safeRelease(blendState);
            blendState = newState;
            blendStateDirty = true;
        }
        return FAILED(result) ? fail("rebuild blend state", result) : S_OK;
    }

    HRESULT rebuildDepthState() {
        for (const auto &entry : depthStateCache) {
            if (entry.enabled != zEnabled || entry.writeEnabled != zWriteEnabled
                || entry.function != zFunction) {
                continue;
            }
            safeRelease(depthState);
            entry.state->AddRef();
            depthState = entry.state;
            depthStateDirty = true;
            return S_OK;
        }
        D3D11_DEPTH_STENCIL_DESC description = {};
        description.DepthEnable = zEnabled ? TRUE : FALSE;
        description.DepthWriteMask = zWriteEnabled ? D3D11_DEPTH_WRITE_MASK_ALL : D3D11_DEPTH_WRITE_MASK_ZERO;
        description.DepthFunc = zFunction;
        description.StencilEnable = FALSE;
        ID3D11DepthStencilState *newState = nullptr;
        HRESULT result = device->CreateDepthStencilState(&description, &newState);
        if (SUCCEEDED(result)) {
            newState->AddRef();
            depthStateCache.push_back({zEnabled, zWriteEnabled, zFunction, newState});
            safeRelease(depthState);
            depthState = newState;
            depthStateDirty = true;
        }
        return FAILED(result) ? fail("rebuild depth state", result) : S_OK;
    }

    HRESULT rebuildRasterizerState() {
        for (const auto &entry : rasterizerStateCache) {
            if (entry.cullMode != cullMode) continue;
            safeRelease(rasterizerState);
            entry.state->AddRef();
            rasterizerState = entry.state;
            rasterizerStateDirty = true;
            return S_OK;
        }
        D3D11_RASTERIZER_DESC description = {};
        description.FillMode = D3D11_FILL_SOLID;
        description.CullMode = cullMode;
        description.DepthClipEnable = TRUE;
        ID3D11RasterizerState *newState = nullptr;
        HRESULT result = device->CreateRasterizerState(&description, &newState);
        if (SUCCEEDED(result)) {
            newState->AddRef();
            rasterizerStateCache.push_back({cullMode, newState});
            safeRelease(rasterizerState);
            rasterizerState = newState;
            rasterizerStateDirty = true;
        }
        return FAILED(result) ? fail("rebuild rasterizer state", result) : S_OK;
    }

    HRESULT compileShaders() {
        compilerModule = LoadLibraryA("d3dcompiler_47.dll");
        if (compilerModule == nullptr) {
            blg::log("D3D11 shader compiler unavailable; clear/present remains enabled");
            return S_FALSE;
        }
        auto compile = reinterpret_cast<D3DCompileProc>(GetProcAddress(compilerModule, "D3DCompile"));
        if (compile == nullptr) {
            blg::log("D3DCompile export unavailable; clear/present remains enabled");
            return S_FALSE;
        }

        static const char vertexSource[] = R"(
cbuffer Viewport : register(b0) { float4 viewport; };
struct VSIn { float4 position : POSITION; float4 color : COLOR0; float2 tex : TEXCOORD0; };
struct VSOut { float4 position : SV_POSITION; float4 color : COLOR0; float2 tex : TEXCOORD0; };
VSOut main(VSIn input) {
    VSOut output;
    output.position = float4((input.position.x / viewport.x) * 2.0 - 1.0,
                             1.0 - (input.position.y / viewport.y) * 2.0,
                             input.position.z, 1.0);
    output.color = input.color;
    output.tex = input.tex;
    return output;
})";
        static const char pixelSource[] = R"(
cbuffer Viewport : register(b0) { float4 viewport; };
struct PSIn { float4 position : SV_POSITION; float4 color : COLOR0; float2 tex : TEXCOORD0; };
float4 main(PSIn input) : SV_TARGET {
    return input.color;
}
)";
        static const char texturedPixelSource[] = R"(
cbuffer Viewport : register(b0) { float4 viewport; };
Texture2D Texture0 : register(t0);
SamplerState Sampler0 : register(s0);
struct PSIn { float4 position : SV_POSITION; float4 color : COLOR0; float2 tex : TEXCOORD0; };
float4 main(PSIn input) : SV_TARGET {
    float4 textureColor = viewport.z > 0.5 ? Texture0.SampleLevel(Sampler0, input.tex, 0.0) : float4(1, 1, 1, 1);
    return textureColor * input.color;
}
)";

        ID3DBlob *vertexBlob = nullptr;
        ID3DBlob *pixelBlob = nullptr;
        ID3DBlob *errors = nullptr;
        HRESULT result = compile(vertexSource, sizeof(vertexSource) - 1, "blg_vertex", nullptr, nullptr, "main", "vs_4_0", 0, 0, &vertexBlob, &errors);
        if (FAILED(result)) {
            if (errors != nullptr) blg::log("D3DCompile vertex: %s", static_cast<const char *>(errors->GetBufferPointer()));
            safeRelease(errors);
            return fail("compile vertex shader", result);
        }
        safeRelease(errors);
        const char *selectedPixelSource = gpuTextureSampling ? texturedPixelSource : pixelSource;
        result = compile(selectedPixelSource, std::strlen(selectedPixelSource), "blg_pixel", nullptr, nullptr, "main", "ps_4_0", 0, 0, &pixelBlob, &errors);
        if (FAILED(result)) {
            if (errors != nullptr) blg::log("D3DCompile pixel: %s", static_cast<const char *>(errors->GetBufferPointer()));
            safeRelease(errors);
            safeRelease(vertexBlob);
            return fail("compile pixel shader", result);
        }
        safeRelease(errors);

        result = device->CreateVertexShader(vertexBlob->GetBufferPointer(), vertexBlob->GetBufferSize(), nullptr, &vertexShader);
        if (SUCCEEDED(result)) {
            result = device->CreatePixelShader(pixelBlob->GetBufferPointer(), pixelBlob->GetBufferSize(), nullptr, &pixelShader);
        }
        if (SUCCEEDED(result)) {
            const D3D11_INPUT_ELEMENT_DESC elements[] = {
                {"POSITION", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
                // D3DCOLOR is laid out as BGRA bytes in memory (0xAARRGGBB).
                // Match that ABI in the diagnostic GPU-texture path so red
                // and blue are not swapped by the D3D11 input assembler.
                {"COLOR", 0, DXGI_FORMAT_B8G8R8A8_UNORM, 0, 16, D3D11_INPUT_PER_VERTEX_DATA, 0},
                {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 20, D3D11_INPUT_PER_VERTEX_DATA, 0}
            };
            result = device->CreateInputLayout(elements, ARRAYSIZE(elements), vertexBlob->GetBufferPointer(), vertexBlob->GetBufferSize(), &inputLayout);
        }
        safeRelease(vertexBlob);
        safeRelease(pixelBlob);
        if (FAILED(result)) return fail("create shader pipeline", result);
        shaderReady = true;
        blg::log("D3D11 first-draw pipeline initialized: XYZRHW+diffuse+TEX1/TEX2");
        return S_OK;
    }

    void updateViewportBuffer() {
        if (viewportBuffer == nullptr || context == nullptr) return;
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        if (SUCCEEDED(context->Map(viewportBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
            ViewportConstants constants = {
                static_cast<float>(std::max<DWORD>(viewport.dwWidth, 1)),
                static_cast<float>(std::max<DWORD>(viewport.dwHeight, 1)),
                gpuTextureEnabled ? static_cast<float>(textureWidth) : 0.0f,
                gpuTextureEnabled ? static_cast<float>(textureHeight) : 0.0f
            };
            std::memcpy(mapped.pData, &constants, sizeof(constants));
            context->Unmap(viewportBuffer, 0);
        }
    }

    void ensureSoftwareBuffers() {
        const size_t pixelCount = static_cast<size_t>(std::max<DWORD>(width, 1))
            * static_cast<size_t>(std::max<DWORD>(height, 1));
        if (softwareColor.size() != pixelCount) {
            softwareColor.assign(pixelCount, 0xff000000u);
            softwareDepth.assign(pixelCount, 1.0f);
        }
    }

    static float clampColor(float value) {
        return std::max(0.0f, std::min(1.0f, value));
    }

    static DWORD packSoftwareColor(float red, float green, float blue, float alpha) {
        const auto channel = [](float value) -> DWORD {
            return static_cast<DWORD>(clampColor(value) * 255.0f + 0.5f);
        };
        return (channel(alpha) << 24)
            | (channel(red) << 16)
            | (channel(green) << 8)
            | channel(blue);
    }

    static void unpackSoftwareColor(DWORD color, float *red, float *green, float *blue, float *alpha) {
        if (red != nullptr) *red = static_cast<float>((color >> 16) & 0xffu) / 255.0f;
        if (green != nullptr) *green = static_cast<float>((color >> 8) & 0xffu) / 255.0f;
        if (blue != nullptr) *blue = static_cast<float>(color & 0xffu) / 255.0f;
        if (alpha != nullptr) *alpha = static_cast<float>((color >> 24) & 0xffu) / 255.0f;
    }

    static bool depthPass(D3D11_COMPARISON_FUNC function, float source, float destination) {
        switch (function) {
        case D3D11_COMPARISON_NEVER: return false;
        case D3D11_COMPARISON_LESS: return source < destination;
        case D3D11_COMPARISON_EQUAL: return source == destination;
        case D3D11_COMPARISON_LESS_EQUAL: return source <= destination;
        case D3D11_COMPARISON_GREATER: return source > destination;
        case D3D11_COMPARISON_NOT_EQUAL: return source != destination;
        case D3D11_COMPARISON_GREATER_EQUAL: return source >= destination;
        case D3D11_COMPARISON_ALWAYS: return true;
        default: return source <= destination;
        }
    }

    static float blendFactor(
        D3D11_BLEND blend,
        float sourceRed,
        float sourceGreen,
        float sourceBlue,
        float sourceAlpha,
        float destinationRed,
        float destinationGreen,
        float destinationBlue,
        float destinationAlpha
    ) {
        UNREFERENCED_PARAMETER(sourceGreen);
        UNREFERENCED_PARAMETER(sourceBlue);
        UNREFERENCED_PARAMETER(destinationGreen);
        UNREFERENCED_PARAMETER(destinationBlue);
        switch (blend) {
        case D3D11_BLEND_ZERO: return 0.0f;
        case D3D11_BLEND_ONE: return 1.0f;
        case D3D11_BLEND_SRC_COLOR: return sourceRed;
        case D3D11_BLEND_INV_SRC_COLOR: return 1.0f - sourceRed;
        case D3D11_BLEND_SRC_ALPHA: return sourceAlpha;
        case D3D11_BLEND_INV_SRC_ALPHA: return 1.0f - sourceAlpha;
        case D3D11_BLEND_DEST_ALPHA: return destinationAlpha;
        case D3D11_BLEND_INV_DEST_ALPHA: return 1.0f - destinationAlpha;
        case D3D11_BLEND_DEST_COLOR: return destinationRed;
        case D3D11_BLEND_INV_DEST_COLOR: return 1.0f - destinationRed;
        case D3D11_BLEND_SRC_ALPHA_SAT:
            return std::min(sourceAlpha, 1.0f - destinationAlpha);
        default: return 1.0f;
        }
    }

    void rasterizeSoftwareTriangle(const LegacyVertex &first, const LegacyVertex &second, const LegacyVertex &third) {
        const float area = (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x);
        if (std::fabs(area) < 0.00001f) return;

        const float minX = std::min(first.x, std::min(second.x, third.x));
        const float maxX = std::max(first.x, std::max(second.x, third.x));
        const float minY = std::min(first.y, std::min(second.y, third.y));
        const float maxY = std::max(first.y, std::max(second.y, third.y));
        const LONG left = std::max<LONG>(0, static_cast<LONG>(std::floor(minX)));
        const LONG right = std::min<LONG>(static_cast<LONG>(width) - 1, static_cast<LONG>(std::ceil(maxX)));
        const LONG top = std::max<LONG>(0, static_cast<LONG>(std::floor(minY)));
        const LONG bottom = std::min<LONG>(static_cast<LONG>(height) - 1, static_cast<LONG>(std::ceil(maxY)));
        if (left > right || top > bottom) return;

        float firstRed = 0.0f, firstGreen = 0.0f, firstBlue = 0.0f, firstAlpha = 1.0f;
        float secondRed = 0.0f, secondGreen = 0.0f, secondBlue = 0.0f, secondAlpha = 1.0f;
        float thirdRed = 0.0f, thirdGreen = 0.0f, thirdBlue = 0.0f, thirdAlpha = 1.0f;
        unpackSoftwareColor(first.color, &firstRed, &firstGreen, &firstBlue, &firstAlpha);
        unpackSoftwareColor(second.color, &secondRed, &secondGreen, &secondBlue, &secondAlpha);
        unpackSoftwareColor(third.color, &thirdRed, &thirdGreen, &thirdBlue, &thirdAlpha);

        for (LONG y = top; y <= bottom; ++y) {
            for (LONG x = left; x <= right; ++x) {
                const float sampleX = static_cast<float>(x) + 0.5f;
                const float sampleY = static_cast<float>(y) + 0.5f;
                const float firstWeight = ((second.x - sampleX) * (third.y - sampleY)
                    - (second.y - sampleY) * (third.x - sampleX)) / area;
                const float secondWeight = ((third.x - sampleX) * (first.y - sampleY)
                    - (third.y - sampleY) * (first.x - sampleX)) / area;
                const float thirdWeight = 1.0f - firstWeight - secondWeight;
                if (firstWeight < -0.0001f || secondWeight < -0.0001f || thirdWeight < -0.0001f) continue;

                const size_t pixelIndex = static_cast<size_t>(y) * width + static_cast<size_t>(x);
                const float depth = first.z * firstWeight + second.z * secondWeight + third.z * thirdWeight;
                if (zEnabled && !depthPass(zFunction, depth, softwareDepth[pixelIndex])) continue;

                float red = firstRed * firstWeight + secondRed * secondWeight + thirdRed * thirdWeight;
                float green = firstGreen * firstWeight + secondGreen * secondWeight + thirdGreen * thirdWeight;
                float blue = firstBlue * firstWeight + secondBlue * secondWeight + thirdBlue * thirdWeight;
                float alpha = firstAlpha * firstWeight + secondAlpha * secondWeight + thirdAlpha * thirdWeight;

                const float u = first.u * firstWeight + second.u * secondWeight + third.u * thirdWeight;
                const float v = first.v * firstWeight + second.v * secondWeight + third.v * thirdWeight;
                const float u1 = first.u1 * firstWeight + second.u1 * secondWeight + third.u1 * thirdWeight;
                const float v1 = first.v1 * firstWeight + second.v1 * secondWeight + third.v1 * thirdWeight;
                const DWORD shadedColor = applyTextureStages(
                    packSoftwareColor(red, green, blue, alpha),
                    u,
                    v,
                    u1,
                    v1
                );
                unpackSoftwareColor(shadedColor, &red, &green, &blue, &alpha);

                if (alphaEnabled) {
                    float destinationRed = 0.0f, destinationGreen = 0.0f;
                    float destinationBlue = 0.0f, destinationAlpha = 1.0f;
                    unpackSoftwareColor(softwareColor[pixelIndex], &destinationRed, &destinationGreen, &destinationBlue, &destinationAlpha);
                    const float sourceFactor = blendFactor(
                        sourceBlend, red, green, blue, alpha,
                        destinationRed, destinationGreen, destinationBlue, destinationAlpha
                    );
                    const float destinationFactor = blendFactor(
                        destinationBlend, red, green, blue, alpha,
                        destinationRed, destinationGreen, destinationBlue, destinationAlpha
                    );
                    red = red * sourceFactor + destinationRed * destinationFactor;
                    green = green * sourceFactor + destinationGreen * destinationFactor;
                    blue = blue * sourceFactor + destinationBlue * destinationFactor;
                    alpha = alpha * sourceFactor + destinationAlpha * destinationFactor;
                }
                softwareColor[pixelIndex] = packSoftwareColor(red, green, blue, alpha);
                if (zEnabled && zWriteEnabled) softwareDepth[pixelIndex] = depth;
            }
        }
    }

    void rasterizeSoftwareTriangles(const std::vector<LegacyVertex> &vertices, const WORD *indices, DWORD indexCount) {
        if (indices != nullptr) {
            for (DWORD index = 0; index + 2 < indexCount; index += 3) {
                const WORD first = indices[index];
                const WORD second = indices[index + 1];
                const WORD third = indices[index + 2];
                if (first < vertices.size() && second < vertices.size() && third < vertices.size()) {
                    rasterizeSoftwareTriangle(vertices[first], vertices[second], vertices[third]);
                }
            }
            return;
        }
        for (size_t index = 0; index + 2 < vertices.size(); index += 3) {
            rasterizeSoftwareTriangle(vertices[index], vertices[index + 1], vertices[index + 2]);
        }
    }

    static bool addressTextureCoordinate(float value, DWORD mode, float *normalized) {
        if (normalized == nullptr || !std::isfinite(value)) return false;
        switch (mode) {
        case D3DTADDRESS_CLAMP:
            *normalized = std::max(0.0f, std::min(1.0f, value));
            return true;
        case D3DTADDRESS_MIRROR: {
            const float integral = std::floor(value);
            float fraction = value - integral;
            if (static_cast<long long>(integral) & 1LL) fraction = 1.0f - fraction;
            *normalized = fraction;
            return true;
        }
        case D3DTADDRESS_BORDER:
            if (value < 0.0f || value > 1.0f) return false;
            *normalized = value;
            return true;
        case kD3DTextureAddressMirrorOnce:
            *normalized = std::fabs(value);
            if (*normalized > 1.0f) *normalized = 2.0f - *normalized;
            *normalized = std::max(0.0f, std::min(1.0f, *normalized));
            return true;
        case D3DTADDRESS_WRAP:
        default:
            *normalized = value - std::floor(value);
            return true;
        }
    }

    static DWORD sampleSoftwarePixels(
        const std::vector<BYTE> &pixels,
        DWORD sampleWidth,
        DWORD sampleHeight,
        float u,
        float v,
        DWORD addressU,
        DWORD addressV
    ) {
        if (pixels.empty() || sampleWidth == 0 || sampleHeight == 0) return 0xffffffffu;
        if (!addressTextureCoordinate(u, addressU, &u)
            || !addressTextureCoordinate(v, addressV, &v)) {
            // D3D's default border color is black. The observed Sacred path
            // uses WRAP, but keeping BORDER deterministic matters to callers
            // that select it explicitly.
            return 0;
        }
        const DWORD textureX = std::min<DWORD>(sampleWidth - 1, static_cast<DWORD>(u * sampleWidth));
        const DWORD textureY = std::min<DWORD>(sampleHeight - 1, static_cast<DWORD>(v * sampleHeight));
        const BYTE *texel = pixels.data()
            + (static_cast<size_t>(textureY) * sampleWidth + textureX) * 4;
        return static_cast<DWORD>(texel[0])
            | (static_cast<DWORD>(texel[1]) << 8)
            | (static_cast<DWORD>(texel[2]) << 16)
            | (static_cast<DWORD>(texel[3]) << 24);
    }

    static const BYTE *softwareTexelWrap(
        const BYTE *pixels,
        DWORD sampleWidth,
        DWORD sampleHeight,
        float u,
        float v
    ) {
        if (pixels == nullptr || sampleWidth == 0 || sampleHeight == 0) return nullptr;

        // Sacred's dominant material state is WRAP with normalized UVs. Keep
        // that hot path free of general address-mode dispatch and only pay for
        // floor() when coordinates actually leave the usual range.
        DWORD textureX = 0;
        DWORD textureY = 0;
        if (u >= 0.0f && u < 1.0f) {
            textureX = static_cast<DWORD>(u * sampleWidth);
        } else {
            if (!std::isfinite(u)) return nullptr;
            const float normalized = u - std::floor(u);
            textureX = std::min<DWORD>(sampleWidth - 1, static_cast<DWORD>(normalized * sampleWidth));
        }
        if (v >= 0.0f && v < 1.0f) {
            textureY = static_cast<DWORD>(v * sampleHeight);
        } else {
            if (!std::isfinite(v)) return nullptr;
            const float normalized = v - std::floor(v);
            textureY = std::min<DWORD>(sampleHeight - 1, static_cast<DWORD>(normalized * sampleHeight));
        }
        return pixels
            + (static_cast<size_t>(textureY) * sampleWidth + textureX) * 4;
    }

    static DWORD sampleSoftwarePixelsWrap(
        const std::vector<BYTE> &pixels,
        DWORD sampleWidth,
        DWORD sampleHeight,
        float u,
        float v
    ) {
        const BYTE *texel = softwareTexelWrap(
            pixels.data(),
            sampleWidth,
            sampleHeight,
            u,
            v
        );
        if (texel == nullptr) return 0xffffffffu;
        return static_cast<DWORD>(texel[0])
            | (static_cast<DWORD>(texel[1]) << 8)
            | (static_cast<DWORD>(texel[2]) << 16)
            | (static_cast<DWORD>(texel[3]) << 24);
    }

    static DWORD modulateTextureColorWrap(
        const BYTE *pixels,
        DWORD sampleWidth,
        DWORD sampleHeight,
        float u,
        float v,
        DWORD diffuseColor
    ) {
        const BYTE *texel = softwareTexelWrap(
            pixels,
            sampleWidth,
            sampleHeight,
            u,
            v
        );
        if (texel == nullptr) return diffuseColor;
        const DWORD red = (static_cast<DWORD>(texel[2]) * ((diffuseColor >> 16) & 0xffu) + 127u) / 255u;
        const DWORD green = (static_cast<DWORD>(texel[1]) * ((diffuseColor >> 8) & 0xffu) + 127u) / 255u;
        const DWORD blue = (static_cast<DWORD>(texel[0]) * (diffuseColor & 0xffu) + 127u) / 255u;
        const DWORD alpha = (static_cast<DWORD>(texel[3]) * ((diffuseColor >> 24) & 0xffu) + 127u) / 255u;
        return (alpha << 24) | (red << 16) | (green << 8) | blue;
    }

    DWORD sampleSoftwareTexture(float u, float v) const {
        if (!textureEnabled || softwareTexturePixels == nullptr) return 0xffffffffu;
        if (textureAddressU == D3DTADDRESS_WRAP && textureAddressV == D3DTADDRESS_WRAP) {
            return sampleSoftwarePixelsWrap(
                *softwareTexturePixels,
                textureWidth,
                textureHeight,
                u,
                v
            );
        }
        return sampleSoftwarePixels(
            *softwareTexturePixels,
            textureWidth,
            textureHeight,
            u,
            v,
            textureAddressU,
            textureAddressV
        );
    }

    DWORD sampleSoftwareTextureStage1(float u, float v) const {
        if (!textureStage1Enabled || softwareTextureStage1Pixels == nullptr) return 0xffffffffu;
        if (textureStage1AddressU == D3DTADDRESS_WRAP && textureStage1AddressV == D3DTADDRESS_WRAP) {
            return sampleSoftwarePixelsWrap(
                *softwareTextureStage1Pixels,
                textureStage1Width,
                textureStage1Height,
                u,
                v
            );
        }
        return sampleSoftwarePixels(
            *softwareTextureStage1Pixels,
            textureStage1Width,
            textureStage1Height,
            u,
            v,
            textureStage1AddressU,
            textureStage1AddressV
        );
    }

    static DWORD textureArgument(DWORD argument, DWORD texture, DWORD diffuse, DWORD current) {
        DWORD value = diffuse;
        switch (argument & D3DTA_SELECTMASK) {
        case D3DTA_CURRENT: value = current; break;
        case D3DTA_TEXTURE: value = texture; break;
        case D3DTA_DIFFUSE: value = diffuse; break;
        case D3DTA_SPECULAR: value = diffuse; break;
        default: break;
        }
        if ((argument & D3DTA_ALPHAREPLICATE) != 0) {
            const DWORD alpha = (value >> 24) & 0xffu;
            value = (alpha << 24) | (alpha << 16) | (alpha << 8) | alpha;
        }
        if ((argument & D3DTA_COMPLEMENT) != 0) {
            value = (255u - ((value >> 24) & 0xffu)) << 24
                | (255u - ((value >> 16) & 0xffu)) << 16
                | (255u - ((value >> 8) & 0xffu)) << 8
                | (255u - (value & 0xffu));
        }
        return value;
    }

    static DWORD combineTextureChannel(DWORD operation, DWORD first, DWORD second) {
        switch (operation) {
        case D3DTOP_SELECTARG1: return first;
        case D3DTOP_SELECTARG2: return second;
        case D3DTOP_MODULATE: return (first * second + 127u) / 255u;
        case D3DTOP_MODULATE2X: return std::min<DWORD>(255u, (first * second * 2u + 127u) / 255u);
        case D3DTOP_MODULATE4X: return std::min<DWORD>(255u, (first * second * 4u + 127u) / 255u);
        case D3DTOP_ADD: return std::min<DWORD>(255u, first + second);
        case D3DTOP_ADDSIGNED: return std::min<DWORD>(255u, first + second < 128u ? 0u : first + second - 128u);
        case D3DTOP_ADDSIGNED2X: return std::min<DWORD>(255u, first + second < 128u ? 0u : (first + second - 128u) * 2u);
        case D3DTOP_SUBTRACT: return first > second ? first - second : 0u;
        case D3DTOP_ADDSMOOTH: return first + second - (first * second + 127u) / 255u;
        default: return second;
        }
    }

    static DWORD combineTextureColor(DWORD operation, DWORD first, DWORD second) {
        const DWORD red = combineTextureChannel(operation, (first >> 16) & 0xffu, (second >> 16) & 0xffu);
        const DWORD green = combineTextureChannel(operation, (first >> 8) & 0xffu, (second >> 8) & 0xffu);
        const DWORD blue = combineTextureChannel(operation, first & 0xffu, second & 0xffu);
        const DWORD alpha = combineTextureChannel(operation, (first >> 24) & 0xffu, (second >> 24) & 0xffu);
        return (alpha << 24) | (red << 16) | (green << 8) | blue;
    }

    static DWORD modulateColors(DWORD first, DWORD second) {
        const DWORD red = (((first >> 16) & 0xffu) * ((second >> 16) & 0xffu) + 127u) / 255u;
        const DWORD green = (((first >> 8) & 0xffu) * ((second >> 8) & 0xffu) + 127u) / 255u;
        const DWORD blue = ((first & 0xffu) * (second & 0xffu) + 127u) / 255u;
        const DWORD alpha = (((first >> 24) & 0xffu) * ((second >> 24) & 0xffu) + 127u) / 255u;
        return (alpha << 24) | (red << 16) | (green << 8) | blue;
    }

    DWORD applyTextureStages(DWORD diffuseColor, float u, float v, float u1, float v1) const {
        const bool hasStage0 = textureEnabled && softwareTexturePixels != nullptr
            && !softwareTexturePixels->empty()
            && textureWidth != 0 && textureHeight != 0;
        const bool hasStage1 = textureStage1Enabled && softwareTextureStage1Pixels != nullptr
            && !softwareTextureStage1Pixels->empty()
            && textureStage1Width != 0 && textureStage1Height != 0;
        if (!hasStage0 && !hasStage1) return diffuseColor;
        DWORD currentColor = diffuseColor;
        if (hasStage0 && textureColorOp != D3DTOP_DISABLE) {
            const float textureU = textureCoordinateIndex == 1 ? u1 : u;
            const float textureV = textureCoordinateIndex == 1 ? v1 : v;
            const DWORD textureColor = sampleSoftwareTexture(textureU, textureV);
            const DWORD firstColor = textureArgument(textureColorArg1, textureColor, diffuseColor, currentColor);
            const DWORD secondColor = textureArgument(textureColorArg2, textureColor, diffuseColor, currentColor);
            const DWORD colorResult = combineTextureColor(textureColorOp, firstColor, secondColor);
            // D3D texture-stage COLOROP writes RGB only. Alpha has its own
            // operation and must remain the previous alpha until ALPHAOP is
            // evaluated below.
            currentColor = (colorResult & 0x00ffffffu) | (currentColor & 0xff000000u);
            if (textureAlphaOp != D3DTOP_DISABLE) {
                const DWORD firstAlpha = textureArgument(textureAlphaArg1, textureColor, diffuseColor, currentColor);
                const DWORD secondAlpha = textureArgument(textureAlphaArg2, textureColor, diffuseColor, currentColor);
                const DWORD alpha = combineTextureChannel(
                    textureAlphaOp,
                    (firstAlpha >> 24) & 0xffu,
                    (secondAlpha >> 24) & 0xffu
                );
                currentColor = (currentColor & 0x00ffffffu) | (alpha << 24);
            }
        } else if (hasStage0 && textureAlphaOp != D3DTOP_DISABLE) {
            const float textureU = textureCoordinateIndex == 1 ? u1 : u;
            const float textureV = textureCoordinateIndex == 1 ? v1 : v;
            const DWORD textureColor = sampleSoftwareTexture(textureU, textureV);
            const DWORD firstAlpha = textureArgument(textureAlphaArg1, textureColor, diffuseColor, currentColor);
            const DWORD secondAlpha = textureArgument(textureAlphaArg2, textureColor, diffuseColor, currentColor);
            const DWORD alpha = combineTextureChannel(
                textureAlphaOp,
                (firstAlpha >> 24) & 0xffu,
                (secondAlpha >> 24) & 0xffu
            );
            currentColor = (currentColor & 0x00ffffffu) | (alpha << 24);
        }
        if (hasStage1 && textureStage1ColorOp != D3DTOP_DISABLE) {
            const float textureU = textureStage1CoordinateIndex == 0 ? u : u1;
            const float textureV = textureStage1CoordinateIndex == 0 ? v : v1;
            const DWORD textureColor = sampleSoftwareTextureStage1(textureU, textureV);
            const DWORD firstColor = textureArgument(
                textureStage1ColorArg1, textureColor, diffuseColor, currentColor
            );
            const DWORD secondColor = textureArgument(
                textureStage1ColorArg2, textureColor, diffuseColor, currentColor
            );
            const DWORD stageColor = combineTextureColor(textureStage1ColorOp, firstColor, secondColor);
            const DWORD firstAlpha = textureArgument(
                textureStage1AlphaArg1, textureColor, diffuseColor, currentColor
            );
            const DWORD secondAlpha = textureArgument(
                textureStage1AlphaArg2, textureColor, diffuseColor, currentColor
            );
            const DWORD alpha = textureStage1AlphaOp == D3DTOP_DISABLE
                ? (currentColor >> 24) & 0xffu
                : combineTextureChannel(
                    textureStage1AlphaOp,
                    (firstAlpha >> 24) & 0xffu,
                    (secondAlpha >> 24) & 0xffu
                );
            currentColor = (stageColor & 0x00ffffffu) | (alpha << 24);
        } else if (hasStage1 && textureStage1AlphaOp != D3DTOP_DISABLE) {
            const float textureU = textureStage1CoordinateIndex == 0 ? u : u1;
            const float textureV = textureStage1CoordinateIndex == 0 ? v : v1;
            const DWORD textureColor = sampleSoftwareTextureStage1(textureU, textureV);
            const DWORD firstAlpha = textureArgument(
                textureStage1AlphaArg1, textureColor, diffuseColor, currentColor
            );
            const DWORD secondAlpha = textureArgument(
                textureStage1AlphaArg2, textureColor, diffuseColor, currentColor
            );
            const DWORD alpha = combineTextureChannel(
                textureStage1AlphaOp,
                (firstAlpha >> 24) & 0xffu,
                (secondAlpha >> 24) & 0xffu
            );
            currentColor = (currentColor & 0x00ffffffu) | (alpha << 24);
        }
        return currentColor;
    }

    void bakeTextureColors(std::vector<LegacyVertex> &vertices) const {
        if (!vertexBakedTextures) return;
        const bool hasStage0 = textureEnabled && softwareTexturePixels != nullptr
            && !softwareTexturePixels->empty()
            && textureWidth != 0 && textureHeight != 0;
        const bool hasStage1 = textureStage1Enabled && softwareTextureStage1Pixels != nullptr
            && !softwareTextureStage1Pixels->empty()
            && textureStage1Width != 0 && textureStage1Height != 0;
        if (!hasStage0 && !hasStage1) return;

        const bool stage0Modulate = hasStage0
            && textureColorOp == D3DTOP_MODULATE
            && textureColorArg1 == D3DTA_TEXTURE
            && textureColorArg2 == D3DTA_DIFFUSE
            && textureAlphaOp == D3DTOP_MODULATE
            && textureAlphaArg1 == D3DTA_TEXTURE
            && textureAlphaArg2 == D3DTA_DIFFUSE
            && textureCoordinateIndex == 0
            && textureAddressU == D3DTADDRESS_WRAP
            && textureAddressV == D3DTADDRESS_WRAP;
        const bool stage1AlphaModulate = hasStage1
            && textureStage1ColorOp == D3DTOP_SELECTARG2
            && textureStage1ColorArg2 == D3DTA_CURRENT
            && textureStage1AlphaOp == D3DTOP_MODULATE
            && textureStage1AlphaArg1 == D3DTA_TEXTURE
            && textureStage1AlphaArg2 == D3DTA_CURRENT
            && textureStage1CoordinateIndex == 1
            && textureStage1AddressU == D3DTADDRESS_WRAP
            && textureStage1AddressV == D3DTADDRESS_WRAP;
        const bool stage1NoOp = !hasStage1
            || (textureStage1ColorOp == D3DTOP_DISABLE && textureStage1AlphaOp == D3DTOP_DISABLE)
            || (textureStage1ColorOp == D3DTOP_SELECTARG2
                && textureStage1ColorArg2 == D3DTA_CURRENT
                && textureStage1AlphaOp == D3DTOP_DISABLE);
        if ((stage0Modulate && (stage1NoOp || stage1AlphaModulate))
            || (stage1AlphaModulate && !hasStage0)) {
            const BYTE *stage0Pixels = softwareTexturePixels == nullptr
                ? nullptr : softwareTexturePixels->data();
            const BYTE *stage1Pixels = softwareTextureStage1Pixels == nullptr
                ? nullptr : softwareTextureStage1Pixels->data();
            for (auto &vertex : vertices) {
                DWORD currentColor = vertex.color;
                if (stage0Modulate) {
                    currentColor = modulateTextureColorWrap(
                        stage0Pixels,
                        textureWidth,
                        textureHeight,
                        vertex.u,
                        vertex.v,
                        currentColor
                    );
                }
                if (stage1AlphaModulate) {
                    const BYTE *texel = softwareTexelWrap(
                        stage1Pixels,
                        textureStage1Width,
                        textureStage1Height,
                        vertex.u1,
                        vertex.v1
                    );
                    const DWORD textureAlpha = texel == nullptr ? 255u : static_cast<DWORD>(texel[3]);
                    const DWORD alpha = (((currentColor >> 24) & 0xffu)
                        * textureAlpha + 127u) / 255u;
                    currentColor = (currentColor & 0x00ffffffu) | (alpha << 24);
                }
                vertex.color = currentColor;
                vertex.u = 0.0f;
                vertex.v = 0.0f;
                vertex.u1 = 0.0f;
                vertex.v1 = 0.0f;
            }
            return;
        }
        for (auto &vertex : vertices) {
            vertex.color = applyTextureStages(vertex.color, vertex.u, vertex.v, vertex.u1, vertex.v1);
            vertex.u = 0.0f;
            vertex.v = 0.0f;
            vertex.u1 = 0.0f;
            vertex.v1 = 0.0f;
        }
    }

    void clearSoftware(DWORD count, D3DRECT *rects, DWORD flags, D3DCOLOR color, D3DVALUE z) {
        ensureSoftwareBuffers();
        if ((flags & D3DCLEAR_TARGET) != 0) {
            const DWORD packedColor = color;
            if (count == 0 || rects == nullptr) {
                std::fill(softwareColor.begin(), softwareColor.end(), packedColor);
            } else {
                for (DWORD index = 0; index < count; ++index) {
                    const LONG left = std::max<LONG>(0, rects[index].x1);
                    const LONG right = std::min<LONG>(static_cast<LONG>(width), rects[index].x2);
                    const LONG top = std::max<LONG>(0, rects[index].y1);
                    const LONG bottom = std::min<LONG>(static_cast<LONG>(height), rects[index].y2);
                    for (LONG y = top; y < bottom; ++y) {
                        std::fill(
                            softwareColor.begin() + static_cast<size_t>(y) * width + left,
                            softwareColor.begin() + static_cast<size_t>(y) * width + right,
                            packedColor
                        );
                    }
                }
            }
        }
        if ((flags & (D3DCLEAR_ZBUFFER | D3DCLEAR_STENCIL)) != 0) {
            std::fill(softwareDepth.begin(), softwareDepth.end(), z);
        }
    }

    void uploadSoftwareFrame() {
        ensureSoftwareBuffers();
        if (backBuffer != nullptr && context != nullptr) {
            context->UpdateSubresource(
                backBuffer,
                0,
                nullptr,
                softwareColor.data(),
                static_cast<UINT>(width * sizeof(DWORD)),
                0
            );
        }
    }

    void bindPipeline(D3D11_PRIMITIVE_TOPOLOGY topology) {
        if (!pipelineStaticBound) {
            ID3D11RenderTargetView *targets[] = {renderTarget};
            context->OMSetRenderTargets(1, targets, depthStencil);
            context->IASetInputLayout(inputLayout);
            UINT stride = sizeof(LegacyVertex);
            UINT offset = 0;
            context->IASetVertexBuffers(0, 1, &vertexBuffer, &stride, &offset);
            context->VSSetShader(vertexShader, nullptr, 0);
            context->VSSetConstantBuffers(0, 1, &viewportBuffer);
            context->PSSetShader(pixelShader, nullptr, 0);
            context->PSSetConstantBuffers(0, 1, &viewportBuffer);
            ID3D11SamplerState *samplers[] = {samplerState};
            context->PSSetSamplers(0, 1, samplers);
            pipelineStaticBound = true;
            blendStateDirty = true;
            depthStateDirty = true;
            rasterizerStateDirty = true;
            viewportDirty = true;
            textureBindingDirty = true;
        }
        if (blendStateDirty) {
            context->OMSetBlendState(blendState, nullptr, 0xffffffffu);
            blendStateDirty = false;
        }
        if (depthStateDirty) {
            context->OMSetDepthStencilState(depthState, 0);
            depthStateDirty = false;
        }
        if (rasterizerStateDirty) {
            context->RSSetState(rasterizerState);
            rasterizerStateDirty = false;
        }
        if (viewportDirty) {
            D3D11_VIEWPORT d3dViewport = {
                static_cast<float>(viewport.dwX),
                static_cast<float>(viewport.dwY),
                static_cast<float>(std::max<DWORD>(viewport.dwWidth, 1)),
                static_cast<float>(std::max<DWORD>(viewport.dwHeight, 1)),
                viewport.dvMinZ,
                viewport.dvMaxZ
            };
            context->RSSetViewports(1, &d3dViewport);
            viewportDirty = false;
        }
        if (textureBindingDirty) {
            ID3D11ShaderResourceView *resources[] = {gpuTextureEnabled ? textureView : nullptr};
            context->PSSetShaderResources(0, 1, resources);
            textureBindingDirty = false;
        }
        if (boundTopology != topology) {
            context->IASetPrimitiveTopology(topology);
            boundTopology = topology;
        }
    }

    HRESULT uploadVertices(const void *vertices, DWORD vertexCount, DWORD *startVertex) {
        if (vertices == nullptr || startVertex == nullptr || vertexCount == 0 || vertexCount > kVertexBufferCapacity) return E_INVALIDARG;
        if (vertexWriteCursor > kVertexBufferCapacity - vertexCount) return E_OUTOFMEMORY;
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        const D3D11_MAP mapType = vertexWriteCursor == 0 ? D3D11_MAP_WRITE_DISCARD : D3D11_MAP_WRITE_NO_OVERWRITE;
        HRESULT result = context->Map(vertexBuffer, 0, mapType, 0, &mapped);
        if (FAILED(result)) return fail("Map vertex buffer", result);
        *startVertex = vertexWriteCursor;
        std::memcpy(
            static_cast<BYTE *>(mapped.pData) + static_cast<size_t>(vertexWriteCursor) * sizeof(LegacyVertex),
            vertices,
            sizeof(LegacyVertex) * vertexCount
        );
        context->Unmap(vertexBuffer, 0);
        vertexWriteCursor += vertexCount;
        return S_OK;
    }

    HRESULT uploadIndices(const WORD *indices, DWORD indexCount, DWORD *startIndex) {
        if (indices == nullptr || startIndex == nullptr || indexCount == 0 || indexCount > kIndexBufferCapacity) return E_INVALIDARG;
        if (indexWriteCursor > kIndexBufferCapacity - indexCount) return E_OUTOFMEMORY;
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        const D3D11_MAP mapType = indexWriteCursor == 0 ? D3D11_MAP_WRITE_DISCARD : D3D11_MAP_WRITE_NO_OVERWRITE;
        HRESULT result = context->Map(indexBuffer, 0, mapType, 0, &mapped);
        if (FAILED(result)) return fail("Map index buffer", result);
        *startIndex = indexWriteCursor;
        std::memcpy(
            static_cast<BYTE *>(mapped.pData) + static_cast<size_t>(indexWriteCursor) * sizeof(WORD),
            indices,
            sizeof(WORD) * indexCount
        );
        context->Unmap(indexBuffer, 0);
        indexWriteCursor += indexCount;
        return S_OK;
    }

    HRESULT flushBatch() {
        if (pendingVertices.empty() || pendingIndices.empty()) {
            pendingVertices.clear();
            pendingIndices.clear();
            return S_OK;
        }

        const ULONGLONG drawStartMilliseconds = GetTickCount64();
        DWORD vertexStart = 0;
        HRESULT result = uploadVertices(
            pendingVertices.data(),
            static_cast<DWORD>(pendingVertices.size()),
            &vertexStart
        );
        if (FAILED(result)) return result;
        DWORD indexStart = 0;
        result = uploadIndices(
            pendingIndices.data(),
            static_cast<DWORD>(pendingIndices.size()),
            &indexStart
        );
        if (FAILED(result)) return result;

        bindPipeline(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        const ULONGLONG submitStartMilliseconds = GetTickCount64();
        context->IASetIndexBuffer(indexBuffer, DXGI_FORMAT_R16_UINT, 0);
        context->DrawIndexed(
            static_cast<UINT>(pendingIndices.size()),
            indexStart,
            static_cast<INT>(vertexStart)
        );
        ++fpsWindowDrawCalls;
        ++fpsWindowBatchFlushes;
        fpsWindowBatchVertices += pendingVertices.size();
        fpsWindowBatchIndices += pendingIndices.size();
        fpsWindowDrawMilliseconds += GetTickCount64() - drawStartMilliseconds;
        fpsWindowSubmitMilliseconds += GetTickCount64() - submitStartMilliseconds;

        pendingVertices.clear();
        pendingIndices.clear();
        pendingTextureIdentity = nullptr;
        pendingTextureEnabled = false;
        return S_OK;
    }

    HRESULT queueTriangleList(
        const std::vector<LegacyVertex> &vertices,
        const WORD *indices,
        DWORD indexCount
    ) {
        if (vertices.empty() || indices == nullptr || indexCount == 0) return E_INVALIDARG;
        for (DWORD index = 0; index < indexCount; ++index) {
            if (indices[index] >= vertices.size()) return E_INVALIDARG;
        }
        const bool stateChanged = !pendingVertices.empty()
            && (pendingTextureIdentity != (gpuTextureEnabled ? textureIdentity : nullptr)
                || pendingTextureEnabled != gpuTextureEnabled);
        const bool capacityExceeded = pendingVertices.size() + vertices.size() > 65535u
            || pendingIndices.size() + indexCount > kIndexBufferCapacity;
        if (stateChanged || capacityExceeded) {
            HRESULT result = flushBatch();
            if (FAILED(result)) return result;
        }
        if (pendingVertices.empty()) {
            pendingTextureIdentity = gpuTextureEnabled ? textureIdentity : nullptr;
            pendingTextureEnabled = gpuTextureEnabled;
        }
        const WORD vertexBase = static_cast<WORD>(pendingVertices.size());
        pendingVertices.insert(pendingVertices.end(), vertices.begin(), vertices.end());
        for (DWORD index = 0; index < indexCount; ++index) {
            pendingIndices.push_back(static_cast<WORD>(vertexBase + indices[index]));
        }
        ++fpsWindowBatchSubmissions;
        return S_OK;
    }

    bool isOutsideViewport(const std::vector<LegacyVertex> &vertices, const WORD *indices, DWORD indexCount) const {
        if (!geometryCulling || vertices.empty() || viewport.dwWidth == 0 || viewport.dwHeight == 0) return false;

        const float left = static_cast<float>(viewport.dwX);
        const float top = static_cast<float>(viewport.dwY);
        const float right = left + static_cast<float>(viewport.dwWidth);
        const float bottom = top + static_cast<float>(viewport.dwHeight);
        bool allLeft = true;
        bool allRight = true;
        bool allTop = true;
        bool allBottom = true;
        const DWORD count = indices != nullptr ? indexCount : static_cast<DWORD>(vertices.size());
        for (DWORD position = 0; position < count; ++position) {
            const WORD vertexIndex = indices != nullptr ? indices[position] : static_cast<WORD>(position);
            if (vertexIndex >= vertices.size()) return false;
            const LegacyVertex &vertex = vertices[vertexIndex];
            if (!std::isfinite(vertex.x) || !std::isfinite(vertex.y)) return false;
            allLeft = allLeft && vertex.x < left;
            allRight = allRight && vertex.x >= right;
            allTop = allTop && vertex.y < top;
            allBottom = allBottom && vertex.y >= bottom;
            if (!allLeft && !allRight && !allTop && !allBottom) return false;
        }
        return allLeft || allRight || allTop || allBottom;
    }

    HRESULT draw(D3DPRIMITIVETYPE primitive, DWORD fvf, const void *vertices, DWORD vertexCount, const WORD *indices, DWORD indexCount) {
        const ULONGLONG drawStartMilliseconds = GetTickCount64();
        if (!initialized || context == nullptr || !shaderReady) {
            blg::trace("D3D11 draw skipped initialized=%d shaders=%d fvf=0x%08lx", initialized ? 1 : 0, shaderReady ? 1 : 0, static_cast<unsigned long>(fvf));
            return S_OK;
        }
        if (vertices == nullptr || vertexCount == 0 || vertexCount > 4096) return E_INVALIDARG;
        if (indices != nullptr && (indexCount == 0 || indexCount > 8192)) return E_INVALIDARG;

        VertexLayout layout = {};
        if (!buildVertexLayout(fvf, &layout)) {
            blg::trace("D3D11 draw skipped unsupported FVF=0x%08lx", static_cast<unsigned long>(fvf));
            return S_OK;
        }

        const ULONGLONG conversionStartMilliseconds = GetTickCount64();
        convertedVerticesScratch.resize(vertexCount);
        std::vector<LegacyVertex> &converted = convertedVerticesScratch;
        const auto *source = static_cast<const BYTE *>(vertices);
        const bool directTransformedTexture2 = layout.transformed
            && layout.stride == sizeof(LegacyVertex)
            && layout.colorOffset == sizeof(float) * 4
            && layout.textureOffset == sizeof(float) * 5
            && layout.texture1Offset == sizeof(float) * 7;
        if (directTransformedTexture2) {
            // FVF 0x244 (XYZRHW + DIFFUSE + TEX2), the dominant Sacred
            // layout, matches LegacyVertex byte-for-byte. Avoid thousands of
            // field-wise copies and position branches per frame.
            std::memcpy(
                converted.data(),
                source,
                static_cast<size_t>(vertexCount) * sizeof(LegacyVertex)
            );
        } else {
        for (DWORD index = 0; index < vertexCount; ++index) {
            const BYTE *sourceVertex = source + static_cast<size_t>(index) * layout.stride;
            Float4 position = {};
            std::memcpy(&position.x, sourceVertex, sizeof(float));
            std::memcpy(&position.y, sourceVertex + sizeof(float), sizeof(float));
            std::memcpy(&position.z, sourceVertex + sizeof(float) * 2, sizeof(float));
            position.w = 1.0f;
            if (layout.transformed) std::memcpy(&position.w, sourceVertex + sizeof(float) * 3, sizeof(float));
            if (!layout.transformed) {
                position = transform(matrices.world, position);
                position = transform(matrices.view, position);
                position = transform(matrices.projection, position);
                const float reciprocalW = position.w == 0.0f ? 1.0f : 1.0f / position.w;
                const float normalizedX = position.x * reciprocalW;
                const float normalizedY = position.y * reciprocalW;
                const float normalizedZ = position.z * reciprocalW;
                position.x = static_cast<float>(viewport.dwX) + (normalizedX + 1.0f) * static_cast<float>(viewport.dwWidth) * 0.5f;
                position.y = static_cast<float>(viewport.dwY) + (1.0f - normalizedY) * static_cast<float>(viewport.dwHeight) * 0.5f;
                position.z = viewport.dvMinZ + normalizedZ * (viewport.dvMaxZ - viewport.dvMinZ);
                position.w = 1.0f;
            }
            converted[index].x = position.x;
            converted[index].y = position.y;
            converted[index].z = position.z;
            converted[index].rhw = position.w;
            converted[index].color = 0xffffffffu;
            if (layout.colorOffset != static_cast<size_t>(-1)) {
                std::memcpy(&converted[index].color, sourceVertex + layout.colorOffset, sizeof(DWORD));
            }
            converted[index].u = 0.0f;
            converted[index].v = 0.0f;
            converted[index].u1 = 0.0f;
            converted[index].v1 = 0.0f;
            if (layout.textureOffset != static_cast<size_t>(-1)) {
                std::memcpy(&converted[index].u, sourceVertex + layout.textureOffset, sizeof(float));
                std::memcpy(&converted[index].v, sourceVertex + layout.textureOffset + sizeof(float), sizeof(float));
            }
            if (layout.texture1Offset != static_cast<size_t>(-1)) {
                std::memcpy(&converted[index].u1, sourceVertex + layout.texture1Offset, sizeof(float));
                std::memcpy(&converted[index].v1, sourceVertex + layout.texture1Offset + sizeof(float), sizeof(float));
            }
        }
        }

        const D3DPRIMITIVETYPE requestedPrimitive = primitive;
        switch (requestedPrimitive) {
        case D3DPT_TRIANGLELIST: ++fpsWindowTriangleListCalls; break;
        case D3DPT_TRIANGLESTRIP: ++fpsWindowTriangleStripCalls; break;
        case D3DPT_TRIANGLEFAN: ++fpsWindowTriangleFanCalls; break;
        default: ++fpsWindowOtherPrimitiveCalls; break;
        }
        const bool directQuadStrip = vertexBakedTextures
            && primitive == D3DPT_TRIANGLESTRIP
            && indices == nullptr
            && vertexCount == 4;
        primitiveIndicesScratch.clear();
        if (primitive == D3DPT_TRIANGLEFAN) {
            if (indices != nullptr) {
                if (indexCount < 3) return E_INVALIDARG;
                primitiveIndicesScratch.reserve(static_cast<size_t>(indexCount - 2) * 3);
                for (DWORD index = 1; index + 1 < indexCount; ++index) {
                    primitiveIndicesScratch.push_back(indices[0]);
                    primitiveIndicesScratch.push_back(indices[index]);
                    primitiveIndicesScratch.push_back(indices[index + 1]);
                }
            } else {
                if (vertexCount < 3) return E_INVALIDARG;
                primitiveIndicesScratch.reserve(static_cast<size_t>(vertexCount - 2) * 3);
                for (DWORD index = 1; index + 1 < vertexCount; ++index) {
                    primitiveIndicesScratch.push_back(0);
                    primitiveIndicesScratch.push_back(static_cast<WORD>(index));
                    primitiveIndicesScratch.push_back(static_cast<WORD>(index + 1));
                }
            }
            primitive = D3DPT_TRIANGLELIST;
            indices = primitiveIndicesScratch.data();
            indexCount = static_cast<DWORD>(primitiveIndicesScratch.size());
        } else if (primitive == D3DPT_TRIANGLESTRIP && !directQuadStrip) {
            const DWORD sourceCount = indices != nullptr ? indexCount : vertexCount;
            if (sourceCount < 3) return E_INVALIDARG;
            primitiveIndicesScratch.reserve(static_cast<size_t>(sourceCount - 2) * 3);
            for (DWORD index = 0; index + 2 < sourceCount; ++index) {
                const WORD first = indices != nullptr ? indices[index] : static_cast<WORD>(index);
                const WORD second = indices != nullptr ? indices[index + 1] : static_cast<WORD>(index + 1);
                const WORD third = indices != nullptr ? indices[index + 2] : static_cast<WORD>(index + 2);
                if ((index & 1u) == 0) {
                    primitiveIndicesScratch.push_back(first);
                    primitiveIndicesScratch.push_back(second);
                    primitiveIndicesScratch.push_back(third);
                } else {
                    primitiveIndicesScratch.push_back(second);
                    primitiveIndicesScratch.push_back(first);
                    primitiveIndicesScratch.push_back(third);
                }
            }
            primitive = D3DPT_TRIANGLELIST;
            indices = primitiveIndicesScratch.data();
            indexCount = static_cast<DWORD>(primitiveIndicesScratch.size());
        }
        if (indices != nullptr) {
            for (DWORD index = 0; index < indexCount; ++index) {
                if (indices[index] >= vertexCount) return E_INVALIDARG;
            }
        }
        fpsWindowConversionMilliseconds += GetTickCount64() - conversionStartMilliseconds;
        if (isOutsideViewport(converted, indices, indexCount)) {
            ++fpsWindowGeometryCulled;
            fpsWindowDrawMilliseconds += GetTickCount64() - drawStartMilliseconds;
            return S_OK;
        }
        bakeTextureColors(converted);

        if (directQuadStrip) {
            static constexpr WORD kQuadStripIndices[] = {0, 1, 2, 2, 1, 3};
            HRESULT result = queueTriangleList(
                converted,
                kQuadStripIndices,
                ARRAYSIZE(kQuadStripIndices)
            );
            if (SUCCEEDED(result)) {
                fpsWindowDrawMilliseconds += GetTickCount64() - drawStartMilliseconds;
            }
            return result;
        }

        if (softwareRendering && primitive == D3DPT_TRIANGLELIST) {
            ensureSoftwareBuffers();
            rasterizeSoftwareTriangles(converted, indices, indexCount);
            ++fpsWindowDrawCalls;
            ++fpsWindowBatchSubmissions;
            ++fpsWindowBatchFlushes;
            fpsWindowBatchVertices += converted.size();
            fpsWindowBatchIndices += indices != nullptr ? indexCount : vertexCount;
            fpsWindowDrawMilliseconds += GetTickCount64() - drawStartMilliseconds;
            return S_OK;
        }

        const DWORD sourceIndexCount = indices != nullptr ? indexCount : vertexCount;
        if (primitive == D3DPT_TRIANGLELIST && sourceIndexCount >= 3 && sourceIndexCount % 3 == 0) {
            if (indices == nullptr) {
                primitiveIndicesScratch.resize(sourceIndexCount);
                for (DWORD index = 0; index < sourceIndexCount; ++index) {
                    primitiveIndicesScratch[index] = static_cast<WORD>(index);
                }
                indices = primitiveIndicesScratch.data();
            }
            return queueTriangleList(converted, indices, sourceIndexCount);
        }

        DWORD vertexStart = 0;
        HRESULT result = uploadVertices(converted.data(), vertexCount, &vertexStart);
        if (FAILED(result)) return result;
        DWORD indexStart = 0;
        if (indices != nullptr && indexCount > 0) {
            result = uploadIndices(indices, indexCount, &indexStart);
            if (FAILED(result)) return result;
        }

        D3D11_PRIMITIVE_TOPOLOGY topology = D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
        switch (primitive) {
        case D3DPT_POINTLIST: topology = D3D11_PRIMITIVE_TOPOLOGY_POINTLIST; break;
        case D3DPT_LINELIST: topology = D3D11_PRIMITIVE_TOPOLOGY_LINELIST; break;
        case D3DPT_LINESTRIP: topology = D3D11_PRIMITIVE_TOPOLOGY_LINESTRIP; break;
        case D3DPT_TRIANGLELIST: topology = D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST; break;
        case D3DPT_TRIANGLESTRIP: topology = D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP; break;
        default: return E_INVALIDARG;
        }
        bindPipeline(topology);
        const ULONGLONG submitStartMilliseconds = GetTickCount64();
        if (indices != nullptr && indexCount > 0) {
            context->IASetIndexBuffer(indexBuffer, DXGI_FORMAT_R16_UINT, 0);
            context->DrawIndexed(indexCount, indexStart, static_cast<INT>(vertexStart));
        } else {
            context->Draw(vertexCount, vertexStart);
        }
        ++fpsWindowDrawCalls;
        fpsWindowDrawMilliseconds += GetTickCount64() - drawStartMilliseconds;
        fpsWindowSubmitMilliseconds += GetTickCount64() - submitStartMilliseconds;
        blg::trace("D3D11 draw primitive=%s converted=%s vertices=%lu indices=%lu", primitiveName(requestedPrimitive), primitiveName(primitive), static_cast<unsigned long>(vertexCount), static_cast<unsigned long>(indexCount));
        return S_OK;
    }
};

D3D11Renderer::D3D11Renderer() : impl_(new Impl()) {
    std::memset(&impl_->matrices, 0, sizeof(impl_->matrices));
    impl_->matrices.world._11 = 1.0f;
    impl_->matrices.world._22 = 1.0f;
    impl_->matrices.world._33 = 1.0f;
    impl_->matrices.world._44 = 1.0f;
    impl_->matrices.view = impl_->matrices.world;
    impl_->matrices.projection = impl_->matrices.world;
}

D3D11Renderer::~D3D11Renderer() {
    if (impl_->presentCount > 0) {
        blg::log(
            "D3D11 present summary frames=%llu skipped=%llu",
            static_cast<unsigned long long>(impl_->presentCount),
            static_cast<unsigned long long>(impl_->presentSkippedCount)
        );
    }
    for (auto &entry : impl_->textureCache) {
        impl_->releaseCachedTexture(entry);
    }
    impl_->textureCache.clear();
    for (auto &entry : impl_->blendStateCache) safeRelease(entry.state);
    for (auto &entry : impl_->depthStateCache) safeRelease(entry.state);
    for (auto &entry : impl_->rasterizerStateCache) safeRelease(entry.state);
    impl_->blendStateCache.clear();
    impl_->depthStateCache.clear();
    impl_->rasterizerStateCache.clear();
    safeRelease(impl_->samplerState);
    safeRelease(impl_->textureView);
    safeRelease(impl_->texture);
    safeRelease(impl_->rasterizerState);
    safeRelease(impl_->depthState);
    safeRelease(impl_->blendState);
    safeRelease(impl_->inputLayout);
    safeRelease(impl_->pixelShader);
    safeRelease(impl_->vertexShader);
    safeRelease(impl_->matrixBuffer);
    safeRelease(impl_->viewportBuffer);
    safeRelease(impl_->indexBuffer);
    safeRelease(impl_->vertexBuffer);
    safeRelease(impl_->depthStencil);
    safeRelease(impl_->depthTexture);
    safeRelease(impl_->renderTarget);
    safeRelease(impl_->backBuffer);
    safeRelease(impl_->swapChain);
    safeRelease(impl_->context);
    safeRelease(impl_->device);
    safeRelease(impl_->adapter);
    safeRelease(impl_->factory);
    if (impl_->compilerModule != nullptr) FreeLibrary(impl_->compilerModule);
    if (impl_->d3d11Module != nullptr) FreeLibrary(impl_->d3d11Module);
    if (impl_->dxgiModule != nullptr) FreeLibrary(impl_->dxgiModule);
    delete impl_;
}

void D3D11Renderer::setWindow(HWND window) {
    impl_->window = window;
    blg::log("D3D11 target window=%p", window);
}

void D3D11Renderer::setDisplayMode(DWORD width, DWORD height) {
    impl_->width = width;
    impl_->height = height;
    impl_->viewport.dwWidth = width;
    impl_->viewport.dwHeight = height;
    if (impl_->initialized) impl_->ensureSoftwareBuffers();
    blg::log("D3D11 display mode=%lux%lu", static_cast<unsigned long>(width), static_cast<unsigned long>(height));
}

HRESULT D3D11Renderer::initialize() {
    if (impl_->initialized) return S_OK;
    HRESULT result = impl_->loadDevice();
    if (FAILED(result)) return result;
    result = impl_->createSwapChain();
    if (FAILED(result)) return result;
    impl_->ensureSoftwareBuffers();
    result = impl_->createStates();
    if (FAILED(result)) return result;
    impl_->compileShaders();
    impl_->updateViewportBuffer();
    impl_->initialized = true;
    blg::log("D3D11 bootstrap ready backbuffer=%lux%lu", static_cast<unsigned long>(impl_->width), static_cast<unsigned long>(impl_->height));
    return S_OK;
}

HRESULT D3D11Renderer::beginScene() {
    HRESULT result = initialize();
    if (FAILED(result)) return result;
    if (impl_->inScene) return D3DERR_SCENE_IN_SCENE;
    result = impl_->flushBatch();
    if (FAILED(result)) return result;
    impl_->inScene = true;
    impl_->vertexWriteCursor = 0;
    impl_->indexWriteCursor = 0;
    impl_->sceneStartMilliseconds = GetTickCount64();
    return S_OK;
}

HRESULT D3D11Renderer::endScene() {
    if (!impl_->initialized) return S_OK;
    impl_->inScene = false;
    if (impl_->softwareRendering) {
        impl_->uploadSoftwareFrame();
    } else {
        HRESULT flushResult = impl_->flushBatch();
        if (FAILED(flushResult)) return flushResult;
    }
    const ULONGLONG presentStart = GetTickCount64();
    if (impl_->presentIntervalMilliseconds != 0
        && impl_->lastPresentRequestMilliseconds != 0
        && presentStart < impl_->lastPresentRequestMilliseconds + impl_->presentIntervalMilliseconds) {
        // DXMT currently ignores DXGI_PRESENT_DO_NOT_WAIT and can block in
        // PresentBoundary. This optional cadence gate lets diagnostic runs
        // render into the current backbuffer without entering that boundary
        // for every legacy EndScene. It is disabled in the normal profile.
        return S_OK;
    }
    impl_->lastPresentRequestMilliseconds = presentStart;
    const ULONGLONG sceneElapsed = impl_->sceneStartMilliseconds == 0
        ? 0
        : presentStart - impl_->sceneStartMilliseconds;
    HRESULT result = impl_->swapChain->Present(0, DXGI_PRESENT_DO_NOT_WAIT);
    bool presentSkipped = result == DXGI_ERROR_WAS_STILL_DRAWING;
    if (result == DXGI_ERROR_INVALID_CALL) {
        // Some DXMT/swapchain combinations do not expose the non-blocking
        // flag. Preserve the normal Present path for those runtimes.
        result = impl_->swapChain->Present(0, 0);
        presentSkipped = false;
    }
    if (FAILED(result)) return impl_->fail("Present", result);

    const ULONGLONG now = GetTickCount64();
    const ULONGLONG presentElapsed = now - presentStart;
    ++impl_->presentCount;
    if (presentSkipped) {
        ++impl_->presentSkippedCount;
        ++impl_->fpsWindowPresentSkipped;
    }
    if (!impl_->fpsTelemetryReady) {
        impl_->fpsTelemetryReady = true;
        impl_->fpsWindowStartCount = impl_->presentCount;
        impl_->fpsWindowStartMilliseconds = now;
        impl_->fpsWindowSceneMilliseconds = 0;
        impl_->fpsWindowPresentMilliseconds = 0;
        impl_->fpsWindowPresentSkipped = 0;
        impl_->fpsWindowDrawCalls = 0;
        impl_->fpsWindowTextureUploads = 0;
        impl_->fpsWindowTextureCacheHits = 0;
        impl_->fpsWindowTextureMilliseconds = 0;
        impl_->fpsWindowNativeTextureCalls = 0;
        impl_->fpsWindowNativeTextureMilliseconds = 0;
        impl_->fpsWindowDrawMilliseconds = 0;
        impl_->fpsWindowConversionMilliseconds = 0;
        impl_->fpsWindowSubmitMilliseconds = 0;
        impl_->fpsWindowBatchSubmissions = 0;
        impl_->fpsWindowBatchFlushes = 0;
        impl_->fpsWindowBatchVertices = 0;
        impl_->fpsWindowBatchIndices = 0;
        impl_->fpsWindowGeometryCulled = 0;
        impl_->fpsWindowTriangleListCalls = 0;
        impl_->fpsWindowTriangleStripCalls = 0;
        impl_->fpsWindowTriangleFanCalls = 0;
        impl_->fpsWindowOtherPrimitiveCalls = 0;
    } else if (now >= impl_->fpsWindowStartMilliseconds + 1000) {
        const ULONGLONG elapsed = now - impl_->fpsWindowStartMilliseconds;
        const ULONGLONG frames = impl_->presentCount - impl_->fpsWindowStartCount;
        const double fps = elapsed == 0
            ? 0.0
            : (static_cast<double>(frames) * 1000.0) / static_cast<double>(elapsed);
        const double averageSceneMs = frames == 0
            ? 0.0
            : static_cast<double>(impl_->fpsWindowSceneMilliseconds + sceneElapsed) / static_cast<double>(frames);
        const double averagePresentMs = frames == 0
            ? 0.0
            : static_cast<double>(impl_->fpsWindowPresentMilliseconds + presentElapsed) / static_cast<double>(frames);
        blg::log(
            "D3D11 FPS presents=%llu skipped=%llu elapsedMs=%llu fps=%.2f sceneMs=%.2f presentMs=%.2f draws=%llu batchSubmissions=%llu batchFlushes=%llu batchVertices=%llu batchIndices=%llu geometryCulled=%llu triList=%llu triStrip=%llu triFan=%llu otherPrimitives=%llu textureUploads=%llu textureCacheHits=%llu textureMs=%llu nativeTextureCalls=%llu nativeTextureMs=%llu drawMs=%llu conversionMs=%llu submitMs=%llu",
            static_cast<unsigned long long>(frames),
            static_cast<unsigned long long>(impl_->fpsWindowPresentSkipped),
            static_cast<unsigned long long>(elapsed),
            fps,
            averageSceneMs,
            averagePresentMs,
            static_cast<unsigned long long>(impl_->fpsWindowDrawCalls),
            static_cast<unsigned long long>(impl_->fpsWindowBatchSubmissions),
            static_cast<unsigned long long>(impl_->fpsWindowBatchFlushes),
            static_cast<unsigned long long>(impl_->fpsWindowBatchVertices),
            static_cast<unsigned long long>(impl_->fpsWindowBatchIndices),
            static_cast<unsigned long long>(impl_->fpsWindowGeometryCulled),
            static_cast<unsigned long long>(impl_->fpsWindowTriangleListCalls),
            static_cast<unsigned long long>(impl_->fpsWindowTriangleStripCalls),
            static_cast<unsigned long long>(impl_->fpsWindowTriangleFanCalls),
            static_cast<unsigned long long>(impl_->fpsWindowOtherPrimitiveCalls),
            static_cast<unsigned long long>(impl_->fpsWindowTextureUploads),
            static_cast<unsigned long long>(impl_->fpsWindowTextureCacheHits),
            static_cast<unsigned long long>(impl_->fpsWindowTextureMilliseconds),
            static_cast<unsigned long long>(impl_->fpsWindowNativeTextureCalls),
            static_cast<unsigned long long>(impl_->fpsWindowNativeTextureMilliseconds),
            static_cast<unsigned long long>(impl_->fpsWindowDrawMilliseconds),
            static_cast<unsigned long long>(impl_->fpsWindowConversionMilliseconds),
            static_cast<unsigned long long>(impl_->fpsWindowSubmitMilliseconds)
        );
        impl_->fpsWindowStartCount = impl_->presentCount;
        impl_->fpsWindowStartMilliseconds = now;
        impl_->fpsWindowSceneMilliseconds = 0;
        impl_->fpsWindowPresentMilliseconds = 0;
        impl_->fpsWindowPresentSkipped = 0;
        impl_->fpsWindowDrawCalls = 0;
        impl_->fpsWindowTextureUploads = 0;
        impl_->fpsWindowTextureCacheHits = 0;
        impl_->fpsWindowTextureMilliseconds = 0;
        impl_->fpsWindowNativeTextureCalls = 0;
        impl_->fpsWindowNativeTextureMilliseconds = 0;
        impl_->fpsWindowDrawMilliseconds = 0;
        impl_->fpsWindowConversionMilliseconds = 0;
        impl_->fpsWindowSubmitMilliseconds = 0;
        impl_->fpsWindowBatchSubmissions = 0;
        impl_->fpsWindowBatchFlushes = 0;
        impl_->fpsWindowBatchVertices = 0;
        impl_->fpsWindowBatchIndices = 0;
        impl_->fpsWindowGeometryCulled = 0;
        impl_->fpsWindowTriangleListCalls = 0;
        impl_->fpsWindowTriangleStripCalls = 0;
        impl_->fpsWindowTriangleFanCalls = 0;
        impl_->fpsWindowOtherPrimitiveCalls = 0;
    } else {
        impl_->fpsWindowSceneMilliseconds += sceneElapsed;
        impl_->fpsWindowPresentMilliseconds += presentElapsed;
    }
    return S_OK;
}

HRESULT D3D11Renderer::clear(DWORD count, D3DRECT *rects, DWORD flags, D3DCOLOR color, D3DVALUE z, DWORD stencil) {
    UNREFERENCED_PARAMETER(count);
    UNREFERENCED_PARAMETER(rects);
    HRESULT result = initialize();
    if (FAILED(result)) return result;
    result = impl_->flushBatch();
    if (FAILED(result)) return result;
    if (impl_->softwareRendering) {
        impl_->clearSoftware(count, rects, flags, color, z);
        return S_OK;
    }
    const float clearColor[] = {
        static_cast<float>(colorChannel(color, 16)) / 255.0f,
        static_cast<float>(colorChannel(color, 8)) / 255.0f,
        static_cast<float>(colorChannel(color, 0)) / 255.0f,
        static_cast<float>(colorChannel(color, 24)) / 255.0f
    };
    if ((flags & D3DCLEAR_TARGET) != 0) {
        impl_->context->ClearRenderTargetView(impl_->renderTarget, clearColor);
    }
    if ((flags & (D3DCLEAR_ZBUFFER | D3DCLEAR_STENCIL)) != 0 && impl_->depthStencil != nullptr) {
        UINT clearFlags = 0;
        if ((flags & D3DCLEAR_ZBUFFER) != 0) clearFlags |= D3D11_CLEAR_DEPTH;
        if ((flags & D3DCLEAR_STENCIL) != 0) clearFlags |= D3D11_CLEAR_STENCIL;
        impl_->context->ClearDepthStencilView(impl_->depthStencil, clearFlags, z, static_cast<UINT8>(stencil));
    }
    return S_OK;
}

HRESULT D3D11Renderer::setTransform(D3DTRANSFORMSTATETYPE state, const D3DMATRIX *matrix) {
    if (matrix == nullptr) return E_POINTER;
    D3DMATRIX *currentMatrix = nullptr;
    switch (state) {
    case D3DTRANSFORMSTATE_WORLD: currentMatrix = &impl_->matrices.world; break;
    case D3DTRANSFORMSTATE_VIEW: currentMatrix = &impl_->matrices.view; break;
    case D3DTRANSFORMSTATE_PROJECTION: currentMatrix = &impl_->matrices.projection; break;
    default: return S_OK;
    }
    if (std::memcmp(currentMatrix, matrix, sizeof(D3DMATRIX)) == 0) return S_OK;
    switch (state) {
    case D3DTRANSFORMSTATE_WORLD: impl_->matrices.world = *matrix; break;
    case D3DTRANSFORMSTATE_VIEW: impl_->matrices.view = *matrix; break;
    case D3DTRANSFORMSTATE_PROJECTION: impl_->matrices.projection = *matrix; break;
    default: break;
    }
    return S_OK;
}

HRESULT D3D11Renderer::setViewport(const D3DVIEWPORT7 *viewport) {
    if (viewport == nullptr) return E_POINTER;
    if (std::memcmp(&impl_->viewport, viewport, sizeof(D3DVIEWPORT7)) == 0) return S_OK;
    HRESULT result = impl_->flushBatch();
    if (FAILED(result)) return result;
    impl_->viewport = *viewport;
    impl_->viewportDirty = true;
    if (impl_->initialized) impl_->updateViewportBuffer();
    return S_OK;
}

HRESULT D3D11Renderer::setRenderState(D3DRENDERSTATETYPE state, DWORD value) {
    bool stateChanged = false;
    bool stateAffectsCurrentDraws = true;
    bool rebuildBlend = false;
    bool rebuildDepth = false;
    bool rebuildRasterizer = false;
    switch (state) {
    case D3DRENDERSTATE_ZENABLE:
        stateChanged = impl_->zEnabled != (value != FALSE);
        rebuildDepth = true;
        break;
    case D3DRENDERSTATE_ZWRITEENABLE:
        stateChanged = impl_->zWriteEnabled != (value != FALSE);
        stateAffectsCurrentDraws = impl_->zEnabled;
        rebuildDepth = true;
        break;
    case D3DRENDERSTATE_ZFUNC:
        stateChanged = impl_->zFunction != static_cast<D3D11_COMPARISON_FUNC>(value);
        stateAffectsCurrentDraws = impl_->zEnabled;
        rebuildDepth = true;
        break;
    case D3DRENDERSTATE_ALPHABLENDENABLE:
        stateChanged = impl_->alphaEnabled != (value != FALSE);
        rebuildBlend = true;
        break;
    case D3DRENDERSTATE_SRCBLEND:
        stateChanged = impl_->sourceBlend != static_cast<D3D11_BLEND>(value);
        stateAffectsCurrentDraws = impl_->alphaEnabled;
        rebuildBlend = true;
        break;
    case D3DRENDERSTATE_DESTBLEND:
        stateChanged = impl_->destinationBlend != static_cast<D3D11_BLEND>(value);
        stateAffectsCurrentDraws = impl_->alphaEnabled;
        rebuildBlend = true;
        break;
    case D3DRENDERSTATE_CULLMODE:
        stateChanged = impl_->cullMode != (value == D3DCULL_CW ? D3D11_CULL_FRONT : value == D3DCULL_CCW ? D3D11_CULL_BACK : D3D11_CULL_NONE);
        rebuildRasterizer = true;
        break;
    default: return S_OK;
    }
    if (!stateChanged) return S_OK;
    if (stateAffectsCurrentDraws) {
        HRESULT flushResult = impl_->flushBatch();
        if (FAILED(flushResult)) return flushResult;
    }
    switch (state) {
    case D3DRENDERSTATE_ZENABLE: impl_->zEnabled = value != FALSE; break;
    case D3DRENDERSTATE_ZWRITEENABLE: impl_->zWriteEnabled = value != FALSE; break;
    case D3DRENDERSTATE_ZFUNC: impl_->zFunction = static_cast<D3D11_COMPARISON_FUNC>(value); break;
    case D3DRENDERSTATE_ALPHABLENDENABLE: impl_->alphaEnabled = value != FALSE; break;
    case D3DRENDERSTATE_SRCBLEND: impl_->sourceBlend = static_cast<D3D11_BLEND>(value); break;
    case D3DRENDERSTATE_DESTBLEND: impl_->destinationBlend = static_cast<D3D11_BLEND>(value); break;
    case D3DRENDERSTATE_CULLMODE:
        impl_->cullMode = value == D3DCULL_CW ? D3D11_CULL_FRONT : value == D3DCULL_CCW ? D3D11_CULL_BACK : D3D11_CULL_NONE;
        break;
        default: break;
    }
    if (!stateAffectsCurrentDraws) return S_OK;
    if (impl_->initialized) {
        if (rebuildBlend) {
            HRESULT result = impl_->rebuildBlendState();
            if (FAILED(result)) return result;
        }
        if (rebuildDepth) {
            HRESULT result = impl_->rebuildDepthState();
            if (FAILED(result)) return result;
        }
        if (rebuildRasterizer) {
            HRESULT result = impl_->rebuildRasterizerState();
            if (FAILED(result)) return result;
        }
    }
    return S_OK;
}

HRESULT D3D11Renderer::drawPrimitive(D3DPRIMITIVETYPE primitive, DWORD fvf, const void *vertices, DWORD vertexCount, DWORD flags) {
    UNREFERENCED_PARAMETER(flags);
    if (!impl_->initialized) {
        HRESULT result = initialize();
        if (FAILED(result)) return result;
    }
    return impl_->draw(primitive, fvf, vertices, vertexCount, nullptr, 0);
}

HRESULT D3D11Renderer::drawIndexedPrimitive(
    D3DPRIMITIVETYPE primitive,
    DWORD fvf,
    const void *vertices,
    DWORD vertexCount,
    const WORD *indices,
    DWORD indexCount,
    DWORD flags
) {
    UNREFERENCED_PARAMETER(flags);
    if (!impl_->initialized) {
        HRESULT result = initialize();
        if (FAILED(result)) return result;
    }
    return impl_->draw(primitive, fvf, vertices, vertexCount, indices, indexCount);
}

HRESULT D3D11Renderer::setTexture(
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
) {
    if (stage > 1) return E_NOTIMPL;
    if (identity == nullptr || pixels == nullptr || width == 0 || height == 0 || pitch == 0) {
        return E_INVALIDARG;
    }
    HRESULT result = initialize();
    if (FAILED(result)) return result;
    if (stage == 0 && impl_->textureIdentity == identity && impl_->textureVersion == version
        && impl_->textureEnabled) {
        return S_OK;
    }
    if (stage == 1 && impl_->textureStage1Identity == identity
        && impl_->textureStage1Version == version && impl_->textureStage1Enabled) {
        return S_OK;
    }
    if (activateCachedTexture(stage, identity, version) == S_OK) return S_OK;
    const bool stateChanged = stage == 0 && impl_->gpuTextureEnabled && !impl_->pendingVertices.empty()
        && (impl_->pendingTextureIdentity != (impl_->gpuTextureEnabled ? identity : nullptr)
            || !impl_->pendingTextureEnabled);
    if (stateChanged) {
        result = impl_->flushBatch();
        if (FAILED(result)) return result;
    }
    impl_->removeCachedTextureVersions(identity);

    const DWORD sourceBytesPerPixel = bitsPerPixel == 16 ? 2 : bitsPerPixel == 24 ? 3 : 4;
    if (bitsPerPixel != 16 && bitsPerPixel != 24 && bitsPerPixel != 32) {
        blg::trace("D3D11 texture skipped unsupported bpp=%lu", static_cast<unsigned long>(bitsPerPixel));
        return E_NOTIMPL;
    }
    if (pitch < width * sourceBytesPerPixel) return E_INVALIDARG;

    const ULONGLONG textureStartMilliseconds = GetTickCount64();
    const size_t convertedPitch = static_cast<size_t>(width) * 4;
    const size_t convertedSize = convertedPitch * static_cast<size_t>(height);
    auto *converted = static_cast<BYTE *>(HeapAlloc(GetProcessHeap(), 0, convertedSize));
    if (converted == nullptr) return E_OUTOFMEMORY;
    const auto *source = static_cast<const BYTE *>(pixels);
    auto extract = [](DWORD value, DWORD mask) -> BYTE {
        if (mask == 0) return 0;
        DWORD shift = 0;
        while (((mask >> shift) & 1u) == 0u && shift < 32u) ++shift;
        DWORD normalized = (value & mask) >> shift;
        DWORD maxValue = mask >> shift;
        return static_cast<BYTE>((normalized * 255u + maxValue / 2u) / maxValue);
    };
    for (DWORD y = 0; y < height; ++y) {
        const BYTE *row = source + static_cast<size_t>(y) * pitch;
        BYTE *destination = converted + static_cast<size_t>(y) * convertedPitch;
        for (DWORD x = 0; x < width; ++x) {
            DWORD value = 0;
            if (bitsPerPixel == 16) {
                value = row[x * 2] | (static_cast<DWORD>(row[x * 2 + 1]) << 8);
            } else if (bitsPerPixel == 24) {
                value = row[x * 3] |
                        (static_cast<DWORD>(row[x * 3 + 1]) << 8) |
                        (static_cast<DWORD>(row[x * 3 + 2]) << 16);
            } else {
                value = row[x * 4] |
                        (static_cast<DWORD>(row[x * 4 + 1]) << 8) |
                        (static_cast<DWORD>(row[x * 4 + 2]) << 16) |
                        (static_cast<DWORD>(row[x * 4 + 3]) << 24);
            }
            destination[x * 4] = extract(value, blueMask);
            destination[x * 4 + 1] = extract(value, greenMask);
            destination[x * 4 + 2] = extract(value, redMask);
            destination[x * 4 + 3] = alphaMask == 0 ? 0xff : extract(value, alphaMask);
        }
    }

    ID3D11Texture2D *newTexture = nullptr;
    ID3D11ShaderResourceView *newView = nullptr;
    if (stage == 0 && impl_->gpuTextureSampling) {
        D3D11_TEXTURE2D_DESC description = {};
        description.Width = width;
        description.Height = height;
        description.MipLevels = 1;
        description.ArraySize = 1;
        description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        description.SampleDesc.Count = 1;
        // Sacred replaces the whole texture when its surface version changes.
        // The dynamic-linear option maps to DXMT's buffer-backed linear
        // texture implementation. It keeps the initial texels in the
        // allocation exposed to the shader, avoiding both DEFAULT-resource
        // UpdateSubresource synchronization and Metal's regular tiled path.
        description.Usage = impl_->gpuTextureDynamicLinear
            ? D3D11_USAGE_DYNAMIC
            : D3D11_USAGE_IMMUTABLE;
        description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
        description.CPUAccessFlags = impl_->gpuTextureDynamicLinear
            ? D3D11_CPU_ACCESS_WRITE
            : 0;

        D3D11_SUBRESOURCE_DATA initialData = {};
        initialData.pSysMem = converted;
        initialData.SysMemPitch = static_cast<UINT>(convertedPitch);
        initialData.SysMemSlicePitch = static_cast<UINT>(convertedSize);
        result = impl_->device->CreateTexture2D(&description, &initialData, &newTexture);
        if (SUCCEEDED(result)) {
            result = impl_->device->CreateShaderResourceView(newTexture, nullptr, &newView);
        }
    }
    auto cachedPixels = std::make_shared<std::vector<BYTE>>(converted, converted + convertedSize);
    HeapFree(GetProcessHeap(), 0, converted);
    if (FAILED(result)) {
        if (newView != nullptr) newView->Release();
        if (newTexture != nullptr) newTexture->Release();
        return impl_->fail("Create texture", result);
    }

    if (stage == 1) {
        D3D11Renderer::Impl::CachedTexture cached = {};
        cached.identity = identity;
        cached.version = version;
        cached.width = width;
        cached.height = height;
        cached.pixels = cachedPixels;
        cached.bytes = convertedSize;
        cached.lastUsed = ++impl_->textureUseSequence;
        impl_->textureCacheBytes += cached.bytes;
        impl_->textureCache.push_back(std::move(cached));
        impl_->activateCachedTextureStage1(impl_->textureCache.back());
        impl_->trimTextureCache();
        ++impl_->fpsWindowTextureUploads;
        impl_->fpsWindowTextureMilliseconds += GetTickCount64() - textureStartMilliseconds;
        blg::trace(
            "D3D11 texture stage=1 cached CPU-only identity=%p size=%lux%lu bpp=%lu",
            identity,
            static_cast<unsigned long>(width),
            static_cast<unsigned long>(height),
            static_cast<unsigned long>(bitsPerPixel)
        );
        return S_OK;
    }

    D3D11Renderer::Impl::CachedTexture cached = {};
    cached.identity = identity;
    cached.version = version;
    cached.texture = newTexture;
    cached.view = newView;
    cached.width = width;
    cached.height = height;
    cached.pixels = cachedPixels;
    cached.bytes = convertedSize;
    cached.lastUsed = ++impl_->textureUseSequence;
    impl_->textureCacheBytes += cached.bytes;
    impl_->textureCache.push_back(std::move(cached));
    // Activate before trimming. A single oversized texture may be evicted by
    // trimTextureCache immediately; activation keeps its own COM references
    // and the CPU texels alive for the current draw even in that case.
    impl_->activateCachedTexture(impl_->textureCache.back());
    impl_->trimTextureCache();
    ++impl_->fpsWindowTextureUploads;
    impl_->fpsWindowTextureMilliseconds += GetTickCount64() - textureStartMilliseconds;
    impl_->updateViewportBuffer();
    blg::trace("D3D11 texture uploaded identity=%p size=%lux%lu bpp=%lu", identity, static_cast<unsigned long>(width), static_cast<unsigned long>(height), static_cast<unsigned long>(bitsPerPixel));
    return S_OK;
}

HRESULT D3D11Renderer::activateCachedTexture(DWORD stage, const void *identity, DWORD version) {
    if (identity == nullptr || !impl_->initialized || stage > 1) return S_FALSE;
    if (stage == 0 && impl_->textureIdentity == identity && impl_->textureVersion == version
        && impl_->textureEnabled) {
        ++impl_->fpsWindowTextureCacheHits;
        return S_OK;
    }
    if (stage == 1 && impl_->textureStage1Identity == identity
        && impl_->textureStage1Version == version && impl_->textureStage1Enabled) {
        ++impl_->fpsWindowTextureCacheHits;
        return S_OK;
    }
    auto *cached = impl_->findCachedTexture(identity, version);
    if (cached == nullptr) return S_FALSE;
    const bool stateChanged = stage == 0 && impl_->gpuTextureEnabled && !impl_->pendingVertices.empty()
        && (impl_->pendingTextureIdentity != (impl_->gpuTextureEnabled ? cached->identity : nullptr)
            || !impl_->pendingTextureEnabled);
    if (stateChanged) {
        HRESULT flushResult = impl_->flushBatch();
        if (FAILED(flushResult)) return flushResult;
    }
    if (stage == 0) impl_->activateCachedTexture(*cached);
    else impl_->activateCachedTextureStage1(*cached);
    ++impl_->fpsWindowTextureCacheHits;
    return S_OK;
}

HRESULT D3D11Renderer::activateCachedTextureByIdentity(DWORD stage, const void *identity) {
    if (identity == nullptr || !impl_->initialized || stage > 1) return S_FALSE;
    if (stage == 0 && impl_->textureIdentity == identity) {
        if (!impl_->textureEnabled) {
            impl_->textureEnabled = true;
            impl_->gpuTextureEnabled = impl_->gpuTextureSampling
                && impl_->texture != nullptr && impl_->textureView != nullptr;
            impl_->textureBindingDirty = true;
            impl_->updateViewportBuffer();
        }
        ++impl_->fpsWindowTextureCacheHits;
        return S_OK;
    }
    if (stage == 1 && impl_->textureStage1Identity == identity) {
        if (!impl_->textureStage1Enabled) {
            auto *cached = impl_->findCachedTextureIdentity(identity);
            if (cached == nullptr) return S_FALSE;
            impl_->activateCachedTextureStage1(*cached);
        }
        ++impl_->fpsWindowTextureCacheHits;
        return S_OK;
    }
    auto *cached = impl_->findCachedTextureIdentity(identity);
    if (cached == nullptr) return S_FALSE;
    const bool stateChanged = stage == 0 && impl_->gpuTextureEnabled && !impl_->pendingVertices.empty()
        && (impl_->pendingTextureIdentity != (impl_->gpuTextureEnabled ? cached->identity : nullptr)
            || !impl_->pendingTextureEnabled);
    if (stateChanged) {
        HRESULT flushResult = impl_->flushBatch();
        if (FAILED(flushResult)) return flushResult;
    }
    if (stage == 0) impl_->activateCachedTexture(*cached);
    else impl_->activateCachedTextureStage1(*cached);
    ++impl_->fpsWindowTextureCacheHits;
    return S_OK;
}

void D3D11Renderer::recordNativeTextureUpload(ULONGLONG elapsedMilliseconds) {
    ++impl_->fpsWindowNativeTextureCalls;
    impl_->fpsWindowNativeTextureMilliseconds += elapsedMilliseconds;
}

void D3D11Renderer::clearTexture(DWORD stage, const void *identity) {
    if (stage > 1) return;
    if (stage == 1) {
        if (identity == nullptr || impl_->textureStage1Identity == identity) {
            impl_->textureStage1Enabled = false;
            impl_->textureStage1Identity = nullptr;
            impl_->textureStage1Version = 0;
            impl_->textureStage1Width = 0;
            impl_->textureStage1Height = 0;
            impl_->softwareTextureStage1Pixels.reset();
        }
        return;
    }
    if (identity == nullptr || impl_->textureIdentity == identity) {
        if (impl_->textureEnabled && impl_->gpuTextureEnabled) (void)impl_->flushBatch();
        if (impl_->textureEnabled) impl_->textureBindingDirty = true;
        impl_->textureEnabled = false;
        impl_->gpuTextureEnabled = false;
        impl_->textureIdentity = nullptr;
        impl_->textureVersion = 0;
        impl_->textureWidth = 0;
        impl_->textureHeight = 0;
        impl_->softwareTexturePixels.reset();
        impl_->updateViewportBuffer();
    }
}

HRESULT D3D11Renderer::setTextureStageState(DWORD stage, D3DTEXTURESTAGESTATETYPE state, DWORD value) {
    blg::trace("D3D11 texture stage state stage=%lu state=%lu value=0x%08lx", static_cast<unsigned long>(stage), static_cast<unsigned long>(state), static_cast<unsigned long>(value));
    if (stage > 1) return S_OK;
    DWORD *target = nullptr;
    if (stage == 0) {
        switch (state) {
        case D3DTSS_COLOROP: target = &impl_->textureColorOp; break;
        case D3DTSS_COLORARG1: target = &impl_->textureColorArg1; break;
        case D3DTSS_COLORARG2: target = &impl_->textureColorArg2; break;
        case D3DTSS_ALPHAOP: target = &impl_->textureAlphaOp; break;
        case D3DTSS_ALPHAARG1: target = &impl_->textureAlphaArg1; break;
        case D3DTSS_ALPHAARG2: target = &impl_->textureAlphaArg2; break;
        case D3DTSS_TEXCOORDINDEX: target = &impl_->textureCoordinateIndex; break;
        case D3DTSS_ADDRESSU: target = &impl_->textureAddressU; break;
        case D3DTSS_ADDRESSV: target = &impl_->textureAddressV; break;
        default: return S_OK;
        }
    } else {
        switch (state) {
        case D3DTSS_COLOROP: target = &impl_->textureStage1ColorOp; break;
        case D3DTSS_COLORARG1: target = &impl_->textureStage1ColorArg1; break;
        case D3DTSS_COLORARG2: target = &impl_->textureStage1ColorArg2; break;
        case D3DTSS_ALPHAOP: target = &impl_->textureStage1AlphaOp; break;
        case D3DTSS_ALPHAARG1: target = &impl_->textureStage1AlphaArg1; break;
        case D3DTSS_ALPHAARG2: target = &impl_->textureStage1AlphaArg2; break;
        case D3DTSS_TEXCOORDINDEX: target = &impl_->textureStage1CoordinateIndex; break;
        case D3DTSS_ADDRESSU: target = &impl_->textureStage1AddressU; break;
        case D3DTSS_ADDRESSV: target = &impl_->textureStage1AddressV; break;
        default: return S_OK;
        }
    }
    if (*target == value) return S_OK;
    // In the default path the current texture-stage state is evaluated while
    // converting each draw into diffuse vertex colors.  Once those vertices
    // are in the pending batch, changing a fixed-function stage no longer
    // changes their GPU result, so it must not split the batch.  Keeping the
    // batch open is important for Sacred, which rewrites the stage state for
    // every material.  The diagnostic GPU-sampled path leaves the stage state
    // for the pixel shader, however, so its pending vertices must be submitted
    // before the new state becomes active.
    if (!impl_->vertexBakedTextures && !impl_->pendingVertices.empty()) {
        HRESULT flushResult = impl_->flushBatch();
        if (FAILED(flushResult)) return flushResult;
    }
    *target = value;
    return S_OK;
}

D3D11Renderer &renderer() {
    static D3D11Renderer instance;
    return instance;
}

} // namespace blg
