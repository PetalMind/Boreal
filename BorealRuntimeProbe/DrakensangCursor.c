#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct DeviceHook {
 IDirect3DDevice9 *object;
 IDirect3DDevice9Vtbl original, replacement;
 struct DeviceHook *next;
 POINT last_position;
 unsigned int positions_logged;
} DeviceHook;
typedef struct FactoryHook {
 IDirect3D9 *object;
 IDirect3D9Vtbl original, replacement;
 struct FactoryHook *next;
} FactoryHook;
static SRWLOCK hooks_lock=SRWLOCK_INIT;
static DeviceHook *devices;
static FactoryHook *factories;
static INIT_ONCE real_once=INIT_ONCE_STATIC_INIT;
static IDirect3D9 *(WINAPI *real_create)(UINT);

static BOOL CALLBACK load_real(PINIT_ONCE once,void *parameter,void **context){
 (void)once;(void)parameter;(void)context;
 WCHAR path[MAX_PATH];UINT n=GetSystemDirectoryW(path,MAX_PATH);
 if(!n||n+11>=MAX_PATH)return FALSE;
 wcscat(path,L"\\d3d9.dll");HMODULE real=LoadLibraryW(path);
 if(real)real_create=(void*)GetProcAddress(real,"Direct3DCreate9");
 if(!real_create||real_create==Direct3DCreate9){real_create=NULL;return FALSE;}
 return TRUE;
}
static HRESULT WINAPI present(IDirect3DDevice9 *object,const RECT *source,const RECT *destination,HWND window,const RGNDATA *dirty){
 DeviceHook *hook;AcquireSRWLockShared(&hooks_lock);
 for(hook=devices;hook&&hook->object!=object;hook=hook->next){}
 ReleaseSRWLockShared(&hooks_lock);if(!hook)return D3DERR_INVALIDCALL;
 POINT position;
 if(GetCursorPos(&position)){
  hook->original.SetCursorPosition(object,position.x,position.y,0);
  if(hook->positions_logged<8&&(!hook->positions_logged||position.x!=hook->last_position.x||position.y!=hook->last_position.y)){
   fprintf(stderr,"[Boreal DSOCursor] position %ld,%ld\n",position.x,position.y);
   hook->last_position=position;++hook->positions_logged;
  }
 }
 return hook->original.Present(object,source,destination,window,dirty);
}
static HRESULT WINAPI create_device(IDirect3D9 *object,UINT adapter,D3DDEVTYPE type,HWND focus,DWORD flags,D3DPRESENT_PARAMETERS *parameters,IDirect3DDevice9 **result){
 FactoryHook *factory;AcquireSRWLockShared(&hooks_lock);
 for(factory=factories;factory&&factory->object!=object;factory=factory->next){}
 ReleaseSRWLockShared(&hooks_lock);if(!factory)return D3DERR_INVALIDCALL;
 HRESULT status=factory->original.CreateDevice(object,adapter,type,focus,flags,parameters,result);
 if(SUCCEEDED(status)&&result&&*result){
  DeviceHook *hook=calloc(1,sizeof(*hook));if(!hook)return status;
  hook->object=*result;hook->original=*(*result)->lpVtbl;hook->replacement=hook->original;hook->replacement.Present=present;
  AcquireSRWLockExclusive(&hooks_lock);hook->next=devices;devices=hook;ReleaseSRWLockExclusive(&hooks_lock);
  (*result)->lpVtbl=&hook->replacement;
  fprintf(stderr,"[Boreal DSOCursor] Direct3D9 cursor synchronization active\n");
 }
 return status;
}
IDirect3D9 *WINAPI Direct3DCreate9(UINT version){
 if(!InitOnceExecuteOnce(&real_once,load_real,NULL,NULL))return NULL;
 IDirect3D9 *object=real_create(version);if(!object)return NULL;
 FactoryHook *hook=calloc(1,sizeof(*hook));if(!hook)return object;
 hook->object=object;hook->original=*object->lpVtbl;hook->replacement=hook->original;hook->replacement.CreateDevice=create_device;
 AcquireSRWLockExclusive(&hooks_lock);hook->next=factories;factories=hook;ReleaseSRWLockExclusive(&hooks_lock);
 object->lpVtbl=&hook->replacement;return object;
}
