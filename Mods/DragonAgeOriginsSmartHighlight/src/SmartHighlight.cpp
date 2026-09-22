#include <windows.h>
#include <shlobj.h>

#include <algorithm>
#include <cwctype>
#include <string>

namespace {

constexpr wchar_t kWindowClassName[] = L"BorealDragonAgeOriginsSmartHighlight";
constexpr UINT_PTR kPollTimerID = 1;
constexpr UINT kPollIntervalMilliseconds = 100;

struct Config {
    bool enabled = true;
    bool syncAutoHighlight = true;
    UINT toggleVirtualKey = VK_TAB;
    int showNPCs = 0;
    int showHero = 0;
    int showFollowers = 0;
    int showTags = 0;
    int rangeMeters = 20;
    int refreshSeconds = 45;
};

HHOOK g_keyboardHook = nullptr;
HWND g_window = nullptr;
Config g_config;
bool g_toggleState = false;
bool g_gameFocused = false;
bool g_syntheticTabDown = false;

std::wstring moduleDirectory() {
    wchar_t buffer[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameW(nullptr, buffer, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return L".";

    std::wstring path(buffer, length);
    const std::wstring::size_type separator = path.find_last_of(L"\\/");
    return separator == std::wstring::npos ? L"." : path.substr(0, separator);
}

std::wstring configPath() {
    return moduleDirectory() + L"\\SmartHighlight.ini";
}

std::wstring lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t character) {
        return static_cast<wchar_t>(std::towlower(character));
    });
    return value;
}

std::wstring trim(std::wstring value) {
    const auto isSpace = [](wchar_t character) { return std::iswspace(character) != 0; };
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), [&](wchar_t character) {
        return !isSpace(character);
    }));
    value.erase(std::find_if(value.rbegin(), value.rend(), [&](wchar_t character) {
        return !isSpace(character);
    }).base(), value.end());
    return value;
}

UINT virtualKeyFromString(const std::wstring& rawValue) {
    const std::wstring value = lower(trim(rawValue));
    if (value == L"tab") return VK_TAB;
    if (value == L"f6") return VK_F6;
    if (value == L"f7") return VK_F7;
    if (value == L"f8") return VK_F8;
    if (value == L"f9") return VK_F9;
    if (value == L"f10") return VK_F10;
    if (value == L"f11") return VK_F11;
    if (value == L"f12") return VK_F12;
    if (value.size() == 1 && value[0] >= L'a' && value[0] <= L'z') {
        return static_cast<UINT>(std::towupper(value[0]));
    }

    wchar_t* end = nullptr;
    const unsigned long numeric = wcstoul(value.c_str(), &end, 10);
    if (end != value.c_str() && *end == L'\0' && numeric <= 0xFF) {
        return static_cast<UINT>(numeric);
    }
    return VK_TAB;
}

std::wstring iniString(const wchar_t* section, const wchar_t* key, const wchar_t* fallback) {
    wchar_t buffer[128] = {};
    GetPrivateProfileStringW(
        section,
        key,
        fallback,
        buffer,
        static_cast<DWORD>(std::size(buffer)),
        configPath().c_str()
    );
    return buffer;
}

int iniInteger(const wchar_t* section, const wchar_t* key, int fallback) {
    return static_cast<int>(GetPrivateProfileIntW(
        section,
        key,
        fallback,
        configPath().c_str()
    ));
}

void loadConfig() {
    g_config.enabled = iniInteger(L"smart_highlight", L"enabled", 1) != 0;
    g_config.syncAutoHighlight = iniInteger(L"smart_highlight", L"sync_auto_highlight", 1) != 0;
    g_config.toggleVirtualKey = virtualKeyFromString(
        iniString(L"smart_highlight", L"toggle_key", L"TAB")
    );
    g_config.showNPCs = iniInteger(L"auto_highlight", L"show_npcs", 0) != 0;
    g_config.showHero = iniInteger(L"auto_highlight", L"show_hero", 0) != 0;
    g_config.showFollowers = iniInteger(L"auto_highlight", L"show_followers", 0) != 0;
    g_config.showTags = iniInteger(L"auto_highlight", L"show_tags", 0) != 0;
    g_config.rangeMeters = std::clamp(iniInteger(L"auto_highlight", L"range_m", 20), 1, 200);
    g_config.refreshSeconds = std::clamp(iniInteger(L"auto_highlight", L"refresh_s", 45), 1, 3600);
}

std::wstring daoINIPath() {
    wchar_t documents[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_PERSONAL, nullptr, SHGFP_TYPE_CURRENT, documents))) {
        return std::wstring(documents) + L"\\BioWare\\Dragon Age\\Settings\\DragonAge.ini";
    }
    return L"";
}

void writeAutoHighlightSetting(const std::wstring& path, const wchar_t* key, int value) {
    const std::wstring text = value ? L"1" : L"0";
    WritePrivateProfileStringW(L"AutoHighlightOptions", key, text.c_str(), path.c_str());
}

void syncAutoHighlightConfig() {
    if (!g_config.syncAutoHighlight) return;

    const std::wstring path = daoINIPath();
    if (path.empty()) return;

    writeAutoHighlightSetting(path, L"ShowCreatures", g_config.showNPCs ? 1 : 0);
    writeAutoHighlightSetting(path, L"ShowHero", g_config.showHero ? 1 : 0);
    writeAutoHighlightSetting(path, L"ShowFollowers", g_config.showFollowers ? 1 : 0);
    writeAutoHighlightSetting(path, L"ShowTags", g_config.showTags ? 1 : 0);

    const std::wstring range = std::to_wstring(g_config.rangeMeters);
    const std::wstring refresh = std::to_wstring(g_config.refreshSeconds);
    WritePrivateProfileStringW(L"AutoHighlightOptions", L"Distance", range.c_str(), path.c_str());
    WritePrivateProfileStringW(L"AutoHighlightOptions", L"Duration", refresh.c_str(), path.c_str());
}

bool executableNameMatches(const std::wstring& fullPath) {
    const std::wstring name = lower(fullPath.substr(fullPath.find_last_of(L"\\/") + 1));
    return name == L"daorigins.exe" || name == L"daoriginslauncher.exe";
}

bool isDAOWindow(HWND window) {
    if (!window) return false;

    DWORD processID = 0;
    GetWindowThreadProcessId(window, &processID);
    if (processID == 0) return false;

    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processID);
    if (!process) return false;

    wchar_t path[MAX_PATH * 4] = {};
    DWORD pathLength = static_cast<DWORD>(std::size(path));
    const BOOL resolved = QueryFullProcessImageNameW(process, 0, path, &pathLength);
    CloseHandle(process);
    return resolved && executableNameMatches(std::wstring(path, pathLength));
}

void sendTab(bool down) {
    if (down == g_syntheticTabDown) return;

    INPUT input = {};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = VK_TAB;
    input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    if (SendInput(1, &input, sizeof(input)) == 1) {
        g_syntheticTabDown = down;
    }
}

void updateSyntheticKeyState() {
    sendTab(g_gameFocused && g_toggleState && g_config.enabled);
}

void pollGameFocus() {
    const bool focused = isDAOWindow(GetForegroundWindow());
    if (focused != g_gameFocused) {
        g_gameFocused = focused;
        updateSyntheticKeyState();
    }
}

LRESULT CALLBACK keyboardHook(int code, WPARAM message, LPARAM data) {
    if (code >= 0 && data != 0) {
        const auto* keyboard = reinterpret_cast<const KBDLLHOOKSTRUCT*>(data);
        const bool isKeyDown = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
        const bool isKeyUp = message == WM_KEYUP || message == WM_SYSKEYUP;
        const bool injected = (keyboard->flags & LLKHF_INJECTED) != 0;

        if (!injected && keyboard->vkCode == g_config.toggleVirtualKey && (isKeyDown || isKeyUp)) {
            if (isKeyDown && g_gameFocused && g_config.enabled) {
                g_toggleState = !g_toggleState;
                updateSyntheticKeyState();
                MessageBeep(g_toggleState ? MB_OK : MB_ICONASTERISK);
                return 1;
            }
            if (g_gameFocused && g_config.enabled) return 1;
        }
    }
    return CallNextHookEx(g_keyboardHook, code, message, data);
}

LRESULT CALLBACK windowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_TIMER:
        if (wParam == kPollTimerID) pollGameFocus();
        return 0;
    case WM_DESTROY:
        sendTab(false);
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcW(window, message, wParam, lParam);
    }
}

bool createMessageWindow(HINSTANCE instance) {
    WNDCLASSW windowClass = {};
    windowClass.lpfnWndProc = windowProcedure;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = kWindowClassName;
    if (!RegisterClassW(&windowClass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;

    g_window = CreateWindowExW(
        0,
        kWindowClassName,
        L"Dragon Age: Origins Smart Highlight",
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        nullptr,
        instance,
        nullptr
    );
    return g_window != nullptr;
}

} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    loadConfig();
    syncAutoHighlightConfig();
    if (!g_config.enabled || !createMessageWindow(instance)) return 0;

    g_keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardHook, instance, 0);
    if (!g_keyboardHook) {
        DestroyWindow(g_window);
        return 0;
    }

    SetTimer(g_window, kPollTimerID, kPollIntervalMilliseconds, nullptr);
    pollGameFocus();

    MSG message = {};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    sendTab(false);
    if (g_keyboardHook) UnhookWindowsHookEx(g_keyboardHook);
    if (g_window) DestroyWindow(g_window);
    return 0;
}
