# Modern Third Person Camera SE

Natywny plugin SKSE64, który unowocześnia kamerę trzecioosobową bez zastępowania
jej własnym systemem renderowania. Kamera używa profili eksploracji, walki i
celowania z łuku, a silnik Skyrim nadal odpowiada za kolizję ze światem i
przejścia między pozycjami.

## Funkcje

- Pozycja zza ramienia poza walką.
- Osobne przesunięcie i FOV w walce.
- Węższy kadr i inna pozycja dla łuku lub kuszy podczas celowania.
- Płynny powrót za postać po ręcznym obracaniu kamerą.
- Regulowana szybkość zoomu kółkiem myszy oraz FOV profili.
- Tłumienie przejść wykorzystuje natywną interpolację kamery gry.

## Wymagania

- Windows, Skyrim Special Edition 1.5.97 lub Anniversary Edition 1.6.x.
- SKSE64 zgodne z używaną wersją gry.
- Address Library for SKSE Plugins.

Nie instaluj równocześnie z SmoothCam ani innym pluginem, który przejmuje
pozycjonowanie kamery trzecioosobowej. Takie mody konkurują o ten sam stan
kamery.

## Konfiguracja

Edytuj `Data/SKSE/Plugins/ModernThirdPersonCameraSE.ini`. Wartości przesunięcia
ramienia są dodawane do bazowych wartości Skyrim w bieżącej sesji. Nie zapisują
zmian do `Skyrim.ini`.

```ini
[Camera]
Enabled=true
NormalShoulderX=18.0
NormalShoulderZ=2.0
CombatShoulderX=24.0
CombatAddY=8.0
CombatShoulderZ=2.0
BowShoulderX=14.0
BowAddY=10.0
BowShoulderZ=1.0
NormalFOV=74.0
CombatFOV=78.0
BowFOV=68.0
FOVResponse=3.5
ZoomSensitivity=1.0
AutoRecenter=true
RecenterDelay=1.1
RecenterResponse=2.4
```

Zmiany w INI wymagają ponownego uruchomienia gry. Kółko myszy nadal zmienia
odległość kamery; `ZoomSensitivity` skaluje siłę tego wejścia.

## Budowanie i instalacja

Build wymaga Windows, CMake, Visual Studio 2022 z komponentami C++ oraz
zainstalowanego vcpkg. `VCPKG_ROOT` musi wskazywać katalog vcpkg.

```powershell
$env:VCPKG_ROOT = "C:\dev\vcpkg"
.\build.ps1
```

Skrypt buduje DLL przez CommonLibSSE-NG i tworzy
`ModernThirdPersonCameraSE.zip`. Zainstaluj archiwum przez MO2/Vortex albo
rozpakuj je do katalogu `Data` gry. Uruchamiaj grę przez SKSE64.

Źródła pluginu znajdują się w `src/`. Wersja pakietu w `manifest.json` jest
źródłem prawdy i jest odczytywana przez system budowania.
