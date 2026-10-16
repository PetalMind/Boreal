#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <stdio.h>
#include <string.h>
#if !defined(_WIN64)
#error This compatibility helper is only for the 64-bit Steam client.
#endif

static HMODULE real_version;
#define FORWARD(result,name,signature,arguments) __declspec(dllexport) result WINAPI Boreal_##name signature { typedef result (WINAPI *Function) signature; return ((Function)GetProcAddress(real_version,#name)) arguments; }
FORWARD(DWORD,GetFileVersionInfoSizeA,(LPCSTR name,LPDWORD handle),(name,handle))
FORWARD(DWORD,GetFileVersionInfoSizeW,(LPCWSTR name,LPDWORD handle),(name,handle))
FORWARD(DWORD,GetFileVersionInfoSizeExA,(DWORD flags,LPCSTR name,LPDWORD handle),(flags,name,handle))
FORWARD(DWORD,GetFileVersionInfoSizeExW,(DWORD flags,LPCWSTR name,LPDWORD handle),(flags,name,handle))
FORWARD(BOOL,GetFileVersionInfoA,(LPCSTR name,DWORD handle,DWORD size,LPVOID data),(name,handle,size,data))
FORWARD(BOOL,GetFileVersionInfoW,(LPCWSTR name,DWORD handle,DWORD size,LPVOID data),(name,handle,size,data))
FORWARD(BOOL,GetFileVersionInfoExA,(DWORD flags,LPCSTR name,DWORD handle,DWORD size,LPVOID data),(flags,name,handle,size,data))
FORWARD(BOOL,GetFileVersionInfoExW,(DWORD flags,LPCWSTR name,DWORD handle,DWORD size,LPVOID data),(flags,name,handle,size,data))
FORWARD(BOOL,VerQueryValueA,(LPCVOID block,LPCSTR key,LPVOID *value,PUINT length),(block,key,value,length))
FORWARD(BOOL,VerQueryValueW,(LPCVOID block,LPCWSTR key,LPVOID *value,PUINT length),(block,key,value,length))
FORWARD(DWORD,VerLanguageNameA,(DWORD language,LPSTR buffer,DWORD size),(language,buffer,size))
FORWARD(DWORD,VerLanguageNameW,(DWORD language,LPWSTR buffer,DWORD size),(language,buffer,size))
FORWARD(DWORD,VerFindFileA,(DWORD flags,LPCSTR file,LPCSTR windows,LPCSTR app,LPSTR current,PUINT currentSize,LPSTR dest,PUINT destSize),(flags,file,windows,app,current,currentSize,dest,destSize))
FORWARD(DWORD,VerFindFileW,(DWORD flags,LPCWSTR file,LPCWSTR windows,LPCWSTR app,LPWSTR current,PUINT currentSize,LPWSTR dest,PUINT destSize),(flags,file,windows,app,current,currentSize,dest,destSize))
FORWARD(DWORD,VerInstallFileA,(DWORD flags,LPCSTR src,LPCSTR dst,LPCSTR srcDir,LPCSTR dstDir,LPCSTR current,LPSTR temp,PUINT tempSize),(flags,src,dst,srcDir,dstDir,current,temp,tempSize))
FORWARD(DWORD,VerInstallFileW,(DWORD flags,LPCWSTR src,LPCWSTR dst,LPCWSTR srcDir,LPCWSTR dstDir,LPCWSTR current,LPWSTR temp,PUINT tempSize),(flags,src,dst,srcDir,dstDir,current,temp,tempSize))

typedef NTSTATUS (WINAPI *RandomFunction)(BCRYPT_ALG_HANDLE, PUCHAR, ULONG, ULONG);
static RandomFunction original_random;
static NTSTATUS WINAPI compatible_random(BCRYPT_ALG_HANDLE handle, PUCHAR buffer, ULONG size, ULONG flags) {
    /* BCRYPT_RNG_ALG_HANDLE is a Windows 10 pseudo-handle. Wine 7.7
       dereferences it as an object. Use its supported OS RNG request instead. */
    if (handle == BCRYPT_RNG_ALG_HANDLE) { handle = NULL; flags |= BCRYPT_USE_SYSTEM_PREFERRED_RNG; }
    return original_random(handle, buffer, size, flags);
}
static void absolute_jump(unsigned char *memory, void *target) {
    memory[0] = 0xff; memory[1] = 0x25;
    memset(memory + 2, 0, 4); memcpy(memory + 6, &target, 8);
}

typedef FARPROC (WINAPI *ProcLookup)(HMODULE,LPCSTR);
static ProcLookup original_lookup;
static ProcLookup original_kernel32_lookup;
static HMODULE kernel_base;
static FARPROC precise_clock;
static FARPROC WINAPI compatible_lookup(HMODULE module,LPCSTR name) {
    if (module == kernel_base && (ULONG_PTR)name > 0xffff
        && !strcmp(name,"QueryUnbiasedInterruptTimePrecise")) return precise_clock;
    return original_lookup(module,name);
}
static FARPROC WINAPI compatible_kernel32_lookup(HMODULE module,LPCSTR name) {
    if (module==kernel_base && (ULONG_PTR)name>0xffff
        && !strcmp(name,"QueryUnbiasedInterruptTimePrecise"))return precise_clock;
    return original_kernel32_lookup(module,name);
}
static BOOL hook_kernel32_lookup(unsigned char *target) {
    const unsigned char expected[14]={0x48,0x83,0xec,0x28,0xe8,0x27,0xf4,0xff,0xff,0x48,0x83,0xc4,0x28,0xc3};
    if(!target || memcmp(target,expected,14))return TRUE;
    /* Preserve this stub's relative CALL as an absolute CALL in the private
       trampoline. RCX/RDX and the original stack/shadow space are unchanged. */
    int displacement;memcpy(&displacement,target+5,4);
    void *callee=target+9+displacement;
    unsigned char *code=VirtualAlloc(NULL,21,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
    if(!code)return FALSE;
    const unsigned char start[6]={0x48,0x83,0xec,0x28,0x48,0xb8};
    const unsigned char end[7]={0xff,0xd0,0x48,0x83,0xc4,0x28,0xc3};
    memcpy(code,start,6);memcpy(code+6,&callee,8);memcpy(code+14,end,7);
    DWORD old;if(!VirtualProtect(code,21,PAGE_EXECUTE_READ,&old))return FALSE;
    original_kernel32_lookup=(ProcLookup)code;
    if(!VirtualProtect(target,14,PAGE_EXECUTE_READWRITE,&old))return FALSE;
    absolute_jump(target,compatible_kernel32_lookup);
    DWORD ignored;VirtualProtect(target,14,old,&ignored);
    FlushInstructionCache(GetCurrentProcess(),target,14);
    FlushInstructionCache(GetCurrentProcess(),code,21);
    return TRUE;
}
/* Fixed prologues are qualified against the shipped Wine 7.7 host. No
   instructions containing PC-relative addresses are relocated. */
static void *install_hook(unsigned char *target,const unsigned char *expected,SIZE_T size,void *replacement) {
    if (!target || memcmp(target,expected,size)) return NULL;
    unsigned char *trampoline=VirtualAlloc(NULL,size+14,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
    if (!trampoline)return NULL;
    memcpy(trampoline,target,size);absolute_jump(trampoline+size,target+size);
    DWORD old;
    if(!VirtualProtect(trampoline,size+14,PAGE_EXECUTE_READ,&old))return NULL;
    if(!VirtualProtect(target,size,PAGE_EXECUTE_READWRITE,&old))return NULL;
    /* The original pointer is published by the caller before any application
       code runs: this helper is loaded during process DLL initialization. */
    absolute_jump(target,replacement);memset(target+14,0x90,size-14);
    DWORD ignored;VirtualProtect(target,size,old,&ignored);
    FlushInstructionCache(GetCurrentProcess(),target,size);
    FlushInstructionCache(GetCurrentProcess(),trampoline,size+14);
    return trampoline;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved) {
    if(reason!=DLL_PROCESS_ATTACH)return TRUE;
    DisableThreadLibraryCalls(module);
    WCHAR system[MAX_PATH];
    if(!GetSystemDirectoryW(system,MAX_PATH-40))return FALSE;
    lstrcatW(system,L"\\version.dll");real_version=LoadLibraryW(system);
    if(!real_version || real_version==module)return FALSE;
    HMODULE crypto=LoadLibraryW(L"bcrypt.dll");
    unsigned char *random_target=(unsigned char*)GetProcAddress(crypto,"BCryptGenRandom");
    const unsigned char random_code[14]={0x55,0x57,0x56,0x53,0x48,0x83,0xec,0x48,0x48,0x89,0xce,0x48,0x89,0xd7};
    if(random_target && !memcmp(random_target,random_code,14)) {
        original_random=(RandomFunction)install_hook(random_target,random_code,14,compatible_random);
        if(!original_random)return FALSE;
        fprintf(stderr,"Boreal: Wine 7.7 RNG pseudo-handle compatibility active.\n");
    }
    if(!GetSystemDirectoryW(system,MAX_PATH-40))return FALSE;
    lstrcatW(system,L"\\BorealRealtimeCompatibility.dll");
    HMODULE clock_module=LoadLibraryW(system);
    precise_clock=clock_module ? GetProcAddress(clock_module,"QueryUnbiasedInterruptTimePrecise") : NULL;
    kernel_base=GetModuleHandleW(L"kernelbase.dll");
    unsigned char *lookup=(unsigned char*)GetProcAddress(kernel_base,"GetProcAddress");
    const unsigned char lookup_code[18]={0x48,0x55,0x48,0x89,0xe5,0x48,0x83,0xec,0x60,0x48,0x83,0xe4,0xf0,0x0f,0x29,0x44,0x24,0x20};
    if(precise_clock && lookup && !memcmp(lookup,lookup_code,18)) {
        original_lookup=(ProcLookup)install_hook(lookup,lookup_code,18,compatible_lookup);
        if(!original_lookup)return FALSE;
        fprintf(stderr,"Boreal: Wine 7.7 realtime API-set compatibility active.\n");
    }
    if(precise_clock && !hook_kernel32_lookup((unsigned char*)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"GetProcAddress")))return FALSE;
    return TRUE;
}
