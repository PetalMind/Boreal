#define WIN32_LEAN_AND_MEAN
#define COBJMACROS

#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <windows.h>

int main(void) {
    IDXGIFactory1 *factory = NULL;
    const IID iidIDXGIFactory1 = {
        0x770aae78,
        0xf26f,
        0x4dba,
        {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}
    };
    HRESULT result = CreateDXGIFactory1(&iidIDXGIFactory1, (void **)&factory);
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_DXGI_INIT_FAILED=0x%08lx\n", (unsigned long)result);
        return 10;
    }
    puts("BOREAL_DXGI_INITIALIZED");
    fflush(stdout);

    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_0
    };
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL selectedLevel;
    result = D3D11CreateDevice(
        NULL,
        D3D_DRIVER_TYPE_HARDWARE,
        NULL,
        0,
        levels,
        sizeof(levels) / sizeof(levels[0]),
        D3D11_SDK_VERSION,
        &device,
        &selectedLevel,
        &context
    );
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_D3D11_DEVICE_INIT_FAILED=0x%08lx\n", (unsigned long)result);
        IDXGIFactory1_Release(factory);
        return 11;
    }
    puts("BOREAL_D3D11_DEVICE_INITIALIZED");
    fflush(stdout);

    (void)selectedLevel;
    if (context != NULL) {
        ID3D11DeviceContext_Release(context);
    }
    if (device != NULL) {
        ID3D11Device_Release(device);
    }
    IDXGIFactory1_Release(factory);
    return 0;
}
