#define WIN32_LEAN_AND_MEAN
#include <windows.h>
/* Wine's current implementation also delegates the precise unbiased clock to
   RtlQueryUnbiasedInterruptTime. The older host exposes that implementation
   through QueryUnbiasedInterruptTime but lacks the API-set module name. */
__declspec(dllexport) VOID WINAPI Boreal_QueryUnbiasedInterruptTimePrecise(PULONGLONG time) {
    QueryUnbiasedInterruptTime(time);
}
