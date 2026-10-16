#define COBJMACROS
#include <windows.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#include <stdio.h>
#include <bcrypt.h>
#include <string.h>
int main(void) {
 HMODULE realtime=LoadLibraryW(L"api-ms-win-core-realtime-l1-1-1.dll");
 typedef VOID (WINAPI *ClockFunction)(PULONGLONG);
 ClockFunction precise=realtime ? (ClockFunction)GetProcAddress(realtime,"QueryUnbiasedInterruptTimePrecise") : NULL;
 ULONGLONG before=0,after=0; QueryUnbiasedInterruptTime(&before);
 printf("REALTIME_MODULE=%p FUNCTION=%p ERROR=%lu\n",(void*)realtime,(void*)precise,GetLastError());
 if(!precise)return 5; precise(&after);
 printf("REALTIME_API=%d MONOTONIC=%d\n",realtime!=NULL,after>=before && after-before<10000000);
 if(after<before || after-before>=10000000)return 6;
 WCHAR path[MAX_PATH]; GetSystemDirectoryW(path,MAX_PATH-13); lstrcatW(path,L"\\version.dll");
 HMODULE systemVersion=LoadLibraryW(path);
 typedef DWORD (WINAPI *VersionSize)(LPCWSTR,LPDWORD);
 VersionSize directVersion=(VersionSize)GetProcAddress(systemVersion,"GetFileVersionInfoSizeW");
 DWORD ignored, proxiedSize=GetFileVersionInfoSizeW(path,&ignored), directSize=directVersion(path,&ignored);
 printf("VERSION_FORWARD=%d SIZE=%lu\n",proxiedSize==directSize && proxiedSize>0,proxiedSize);
 if(!proxiedSize || proxiedSize!=directSize)return 3;
 unsigned char a[32]={0}, b[32]={0}, c[32]={0}; BCRYPT_ALG_HANDLE realAlgorithm=NULL;
 NTSTATUS pseudo=BCryptGenRandom(BCRYPT_RNG_ALG_HANDLE,a,32,0);
 NTSTATUS system=BCryptGenRandom(NULL,b,32,BCRYPT_USE_SYSTEM_PREFERRED_RNG);
 NTSTATUS opened=BCryptOpenAlgorithmProvider(&realAlgorithm,BCRYPT_RNG_ALGORITHM,NULL,0);
 NTSTATUS real=opened ? opened : BCryptGenRandom(realAlgorithm,c,32,0);
 if(realAlgorithm)BCryptCloseAlgorithmProvider(realAlgorithm,0);
 NTSTATUS invalid=BCryptGenRandom(NULL,b,32,0);
 printf("RNG_PSEUDO=%08lx RNG_SYSTEM=%08lx RNG_REAL=%08lx RNG_INVALID=%08lx DISTINCT=%d\n",(unsigned long)pseudo,(unsigned long)system,(unsigned long)real,(unsigned long)invalid,memcmp(a,b,32)!=0);
 if(pseudo || system || real || invalid>=0 || !memcmp(a,b,32))return 4;
 IDXGIFactory4 *factory = NULL; IDXGIAdapter1 *adapter = NULL; ID3D12Device *device = NULL;
 HRESULT hr = CreateDXGIFactory1(&IID_IDXGIFactory4, (void**)&factory);
 printf("DXGI_FACTORY=%08lx\n", (unsigned long)hr); fflush(stdout);
 if (FAILED(hr)) return 1;
 for (UINT index=0; IDXGIFactory4_EnumAdapters1(factory,index,&adapter)!=DXGI_ERROR_NOT_FOUND; ++index) {
  DXGI_ADAPTER_DESC1 desc; IDXGIAdapter1_GetDesc1(adapter,&desc);
  printf("ADAPTER=%u VENDOR=%x DEVICE=%x FLAGS=%x\n",index,desc.VendorId,desc.DeviceId,desc.Flags);
  hr=D3D12CreateDevice((IUnknown*)adapter,D3D_FEATURE_LEVEL_12_0,&IID_ID3D12Device,(void**)&device);
  printf("D3D12_DEVICE_FL12_0=%08lx\n",(unsigned long)hr);fflush(stdout);
  if(SUCCEEDED(hr)){ID3D12Device_Release(device);IDXGIAdapter1_Release(adapter);IDXGIFactory4_Release(factory);return 0;}
  IDXGIAdapter1_Release(adapter);
 }
 IDXGIFactory4_Release(factory);return 2;
}
