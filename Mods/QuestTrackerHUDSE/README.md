# Quest Tracker HUD SE

Wyświetla zaznaczone zadania i ich aktualne, niezakończone cele na HUD-zie. Widok domyślnie pojawia się po prawej stronie, poniżej górnego paska HUD. Ustawienia MCM pozwalają włączyć lub wyłączyć listę, zmienić jej położenie i szerokość, ustawić krycie oraz ograniczyć liczbę widocznych zadań. Położenie można dopasować do minimapy używanej w danym zestawie modów.

Lista pobiera tytuły, cele i stan zaznaczenia bezpośrednio z questów gry. Nie zmienia celów ani ich stanu. Po odznaczeniu zadania znika ono z widoku przy następnym odświeżeniu.

## Wymagania

- Skyrim Special Edition lub Anniversary Edition na Windows;
- SKSE64 zgodne z używaną wersją gry;
- Address Library for SKSE Plugins;
- SkyUI z MCM.

## Instalacja

Zainstaluj `QuestTrackerHUDSE.zip` przez MO2/Vortex albo zaimportuj archiwum w Boreal i włącz `QuestTrackerHUDSE.esp`. Uruchom grę przez SKSE64. W menu „Ustawienia modów” wybierz „Quest Tracker HUD SE”.

Widok tworzy się w pamięci gry i nie zastępuje plików interfejsu ani HUD-u. Ustawienia położenia odnoszą się do obszaru HUD w układzie 1280 × 720 i skaluje je Skyrim razem z interfejsem. Inne mody mogą zmieniać skalę HUD-u.

## Budowanie

Budowanie kompletnego archiwum wymaga Windows, CMake, Visual Studio 2022 z narzędziami C++, vcpkg oraz Caprica Papyrus Compiler. `VCPKG_ROOT` musi wskazywać katalog vcpkg.

```powershell
$env:VCPKG_ROOT = "C:\dev\vcpkg"
.\build.ps1
```

Skrypt kompiluje skrypty Papyrusa, ESP i plugin SKSE przez CommonLibSSE-NG, po czym tworzy `QuestTrackerHUDSE.zip`. Kod zbierający stan questów znajduje się w `src/`, a skrypty interfejsu i MCM w `Source/Scripts/`.
