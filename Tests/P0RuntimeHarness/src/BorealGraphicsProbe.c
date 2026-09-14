#define WIN32_LEAN_AND_MEAN
#define COBJMACROS

#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <windows.h>

static LRESULT CALLBACK probe_window_proc(HWND window, UINT message, WPARAM w_param, LPARAM l_param) {
    return DefWindowProcA(window, message, w_param, l_param);
}

int main(void) {
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL;
    IDXGISwapChain *swap_chain = NULL;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11Texture2D *back_buffer = NULL;
    ID3D11RenderTargetView *render_target = NULL;
    HWND window = NULL;
    ATOM window_class = 0;
    int exit_code = 0;
    const IID iidIDXGIFactory1 = {
        0x770aae78,
        0xf26f,
        0x4dba,
        {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}
    };
    const IID iidID3D11Texture2D = {
        0x6f15aaf2,
        0xd208,
        0x4e89,
        {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}
    };
    HRESULT result = CreateDXGIFactory1(&iidIDXGIFactory1, (void **)&factory);
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_DXGI_INIT_FAILED=0x%08lx\n", (unsigned long)result);
        return 10;
    }
    puts("BOREAL_DXGI_INITIALIZED");
    fflush(stdout);

    result = IDXGIFactory1_EnumAdapters1(factory, 0, &adapter);
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_DXGI_ADAPTER_INIT_FAILED=0x%08lx\n", (unsigned long)result);
        exit_code = 10;
        goto cleanup;
    }
    puts("BOREAL_DXGI_ADAPTER_INITIALIZED");
    fflush(stdout);

    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL selectedLevel;
    result = D3D11CreateDevice(
        (IDXGIAdapter *)adapter,
        D3D_DRIVER_TYPE_UNKNOWN,
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

    if (selectedLevel == D3D_FEATURE_LEVEL_11_0) {
        puts("BOREAL_D3D11_FEATURE_LEVEL=11_0");
    } else if (selectedLevel == D3D_FEATURE_LEVEL_10_0) {
        puts("BOREAL_D3D11_FEATURE_LEVEL=10_0");
    } else {
        puts("BOREAL_D3D11_FEATURE_LEVEL=unknown");
    }
    fflush(stdout);

    WNDCLASSA window_class_info = {0};
    window_class_info.lpfnWndProc = probe_window_proc;
    window_class_info.hInstance = GetModuleHandleA(NULL);
    window_class_info.lpszClassName = "BorealGraphicsProbeWindow";
    window_class = RegisterClassA(&window_class_info);
    if (window_class == 0) {
        fprintf(stderr, "BOREAL_D3D11_WINDOW_INIT_FAILED=0x%08lx\n", (unsigned long)GetLastError());
        exit_code = 12;
        goto cleanup;
    }
    window = CreateWindowExA(
        0,
        window_class_info.lpszClassName,
        "Boreal D3D11 probe",
        WS_OVERLAPPEDWINDOW,
        0,
        0,
        64,
        64,
        NULL,
        NULL,
        window_class_info.hInstance,
        NULL
    );
    if (window == NULL) {
        fprintf(stderr, "BOREAL_D3D11_WINDOW_CREATE_FAILED=0x%08lx\n", (unsigned long)GetLastError());
        exit_code = 12;
        goto cleanup;
    }

    DXGI_SWAP_CHAIN_DESC swap_chain_desc = {0};
    swap_chain_desc.BufferCount = 1;
    swap_chain_desc.BufferDesc.Width = 64;
    swap_chain_desc.BufferDesc.Height = 64;
    swap_chain_desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swap_chain_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swap_chain_desc.OutputWindow = window;
    swap_chain_desc.SampleDesc.Count = 1;
    swap_chain_desc.Windowed = TRUE;
    swap_chain_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    result = IDXGIFactory1_CreateSwapChain(
        factory,
        (IUnknown *)device,
        &swap_chain_desc,
        &swap_chain
    );
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_D3D11_SWAPCHAIN_INIT_FAILED=0x%08lx\n", (unsigned long)result);
        exit_code = 13;
        goto cleanup;
    }
    puts("BOREAL_D3D11_SWAPCHAIN_INITIALIZED");
    fflush(stdout);

    result = IDXGISwapChain_GetBuffer(
        swap_chain,
        0,
        &iidID3D11Texture2D,
        (void **)&back_buffer
    );
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_D3D11_BACKBUFFER_FAILED=0x%08lx\n", (unsigned long)result);
        exit_code = 14;
        goto cleanup;
    }
    result = ID3D11Device_CreateRenderTargetView(
        device,
        (ID3D11Resource *)back_buffer,
        NULL,
        &render_target
    );
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_D3D11_RENDER_TARGET_FAILED=0x%08lx\n", (unsigned long)result);
        exit_code = 14;
        goto cleanup;
    }
    puts("BOREAL_D3D11_RENDER_TARGET_INITIALIZED");
    fflush(stdout);

    const FLOAT clear_color[4] = {0.04f, 0.08f, 0.16f, 1.0f};
    ID3D11DeviceContext_ClearRenderTargetView(context, render_target, clear_color);
    puts("BOREAL_D3D11_CLEAR_SUCCEEDED");
    fflush(stdout);

    result = IDXGISwapChain_Present(swap_chain, 0, 0);
    if (FAILED(result)) {
        fprintf(stderr, "BOREAL_D3D11_PRESENT_FAILED=0x%08lx\n", (unsigned long)result);
        exit_code = 15;
        goto cleanup;
    }
    puts("BOREAL_D3D11_PRESENT_SUCCEEDED");
    fflush(stdout);

cleanup:
    if (render_target != NULL) {
        ID3D11RenderTargetView_Release(render_target);
    }
    if (back_buffer != NULL) {
        ID3D11Texture2D_Release(back_buffer);
    }
    if (swap_chain != NULL) {
        IDXGISwapChain_Release(swap_chain);
    }
    if (window != NULL) {
        DestroyWindow(window);
    }
    if (window_class != 0) {
        UnregisterClassA(window_class_info.lpszClassName, window_class_info.hInstance);
    }
    if (context != NULL) {
        ID3D11DeviceContext_Release(context);
    }
    if (device != NULL) {
        ID3D11Device_Release(device);
    }
    if (adapter != NULL) {
        IDXGIAdapter1_Release(adapter);
    }
    if (factory != NULL) {
        IDXGIFactory1_Release(factory);
    }
    return exit_code;
}
