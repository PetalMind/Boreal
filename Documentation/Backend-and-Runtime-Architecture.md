# Boreal — backend lokalny, runtime’y i pełny schemat uruchamiania

**Status:** opis stanu kodu na 2026-09-11
**Zakres:** lokalne usługi Swift, dane, providerzy sklepów, Wine/GPTK, prefixy, backendy graficzne, instalacja i uruchamianie gier.

Ten dokument opisuje rzeczywistą architekturę Boreal. Nie zakłada istnienia osobnego serwera Boreal, zdalnej bazy danych ani mechanizmu, którego nie ma w repozytorium.

## 1. Czym jest backend Boreal

Boreal nie ma klasycznego backendu typu API server plus database. Jest aplikacją macOS, w której backend jest lokalną warstwą usług Swift, uzupełnianą przez lokalne procesy pomocnicze i zewnętrzne API sklepów.

~~~text
SwiftUI / AppKit
        │
        ▼
BorealStore (@MainActor, stan UI i orkiestracja)
        │
        ▼
BorealServices (dependency injection i kontrakty)
        │
        ├── RuntimeManager       — runtime’y Wine/GPTK i komponenty
        ├── EnvironmentManager   — prefixy, rejestr i zależności
        ├── LaunchCoordinator    — LaunchPlan i sesja startu
        ├── WindowsProcessRunner — uruchamianie przez Wine
        ├── InstallerService     — instalatory EXE/MSI
        ├── SteamLibraryService  — lokalna biblioteka Steam
        ├── SteamWindowsService  — Windows Steam w prefixie
        ├── LegendaryEpicService — helper Legendary
        ├── GOGService           — helper gogdl
        └── Discovery / ProtonDB / ITAD
        │
        ├── JSON na dysku
        ├── procesy macOS
        ├── Wine / wineserver / wineboot
        └── zewnętrzne API i helpery
~~~

W dokumentacji występują trzy różne znaczenia słowa backend:

| Nazwa | Znaczenie |
|---|---|
| Backend aplikacji | Lokalne serwisy Swift, aktory, repozytoria JSON i helpery procesowe. |
| Runtime backend | Pakiet Wine albo Game Porting Toolkit dostarczający wine, wineserver, wineboot i biblioteki. |
| Backend graficzny | Ścieżka DirectX: D3DMetal, DXMT, DXVK, VKD3D-Proton albo WineD3D. |

## 2. Warstwy kodu

### 2.1. BorealApp

Boreal/BorealApp.swift tworzy główny BorealStore, przekazuje go do SwiftUI i uruchamia kontroler, automatyczne sprawdzanie aktualizacji kompatybilności oraz okresowe odświeżanie bibliotek. Przy zamykaniu zatrzymywane są kontrolery i operacje sklepowe.

### 2.2. BorealStore

Boreal/BorealStore.swift jest jednocześnie MainActor i Observable. Jest właścicielem stanu UI, ale długie operacje deleguje do usług.

Odpowiada za:

- aplikacje, gry sklepowe i środowiska,
- stan instalacji oraz operacji providerów,
- runtime’y i lokalne kandydaty runtime’ów,
- profile kompatybilności,
- przygotowanie/rebuild środowiska,
- tworzenie planu launchu,
- stany preparing, starting, running, ready i needsAttention,
- monitorowanie launcher process i wineserver,
- recovery po restarcie,
- zapis playtime,
- ograniczony fallback renderera po błędzie inicjalizacji urządzenia.

Nie powinien być miejscem dla składni GOG, rozpakowywania runtime’u ani bezpośredniej obsługi Process.

### 2.3. BorealServices

Boreal/BorealServices.swift składa implementacje produkcyjne i pozwala wstrzykiwać fake’i/test doubles.

Najważniejsze kontrakty:

~~~text
RuntimeManaging
EnvironmentManaging
WindowsProcessRunning
LaunchCoordinating
Installing
GameInstallationManaging
SteamLibraryLoading
SteamWindowsProviding
EpicLibraryProviding
GOGLibraryProviding
GameStoreProvider
CommunityCompatibilityLoading
DiscoveryCatalogLoading
DiscoveryPricingLoading
~~~

### 2.4. Współbieżność

- BorealStore jest MainActor.
- RuntimeManager, EnvironmentManager, WindowsProcessRunner, LaunchCoordinator, InstallerService, SteamLibraryService, LegendaryEpicService i GOGService są actorami.
- SystemProcessExecutor jest aktorem przechowującym rejestr procesów.
- JSONStore i LibraryRepository serializują zapisy.
- Skanowanie dużych drzew plików może być wykonywane w Task.detached.

## 3. Dane i źródła prawdy

### 3.1. Katalog danych

Domyślny root:

~~~text
~/Library/Application Support/Boreal/
~~~

Układ:

~~~text
Boreal/
├── Library/
│   ├── library.json
│   ├── favorites.json
│   ├── sessions.json
│   ├── downloads.json
│   └── ...
├── State/app-state.json
├── Environments/<environment-uuid>/
│   ├── environment.json
│   ├── prefix/
│   ├── Logs/
│   ├── .prefix-installing/
│   ├── .graphics-backend.json
│   └── .graphics-backup/
├── Runtimes/<runtime-id>/
│   ├── installed-runtime.json
│   ├── runtime.json
│   ├── Runtime/Wine.app/
│   ├── Dependencies/
│   ├── Support/
│   ├── Licenses/
│   ├── SBOM.spdx.json
│   └── GraphicsComponents/
├── Games/Epic/
├── Games/GOG/
├── Accounts/Epic/
├── Accounts/GOG/
├── Tools/GOGDL/1.3.0/
├── Tools/Legendary/0.21.0/
├── Tools/Winetricks/2026-09-04/
├── Installers/Steam/SteamSetup.exe
├── Logs/EnvironmentFailures/
└── Discovery/saved-games.json
~~~

Konkretne ścieżki są zdefiniowane w Boreal/BorealStorage.swift, Boreal/RuntimeManager.swift, Boreal/EnvironmentManager.swift, Boreal/GOGService.swift i Boreal/LegendaryEpicService.swift.

### 3.2. Warstwowy zapis biblioteki

- Library/library.json — aplikacje, gry i kanoniczne GameInstallation.
- Library/favorites.json — stabilne klucze ulubionych.
- Library/sessions.json — sesje gry i czas mierzony przez Boreal.
- Library/downloads.json — postęp i wznowienie pobierania.
- State/app-state.json — m.in. ostatnie automatyczne odświeżenie.

JSONStore tworzy katalog rodzica i zapisuje dokument atomowo. Stary root-level library.json jest czytany jako format migracyjny/testowy; domyślna ścieżka zapisuje format warstwowy.

### 3.3. Relacje domenowe

~~~text
GameLibraryProvider + externalID
            │
            ▼
      StoreReference
            │
            ├── StoreLibraryGame      metadata / ownership / bridge
            ├── GameInstallation      canonical filesystem installation
            └── WindowsApplication    executable + environment
                                             │
                                             ▼
                                   ManagedBorealEnvironment
                                             │
                                             ▼
                                       InstalledRuntime
~~~

Zasady:

- gry sklepowej nie identyfikuje się po nazwie, tylko po provider + externalID,
- metadane sklepu i lokalny stan uruchomienia są rozdzielone,
- GameInstallation jest kanonicznym rekordem instalacji,
- pola instalacji w StoreLibraryGame pozostają mostem kompatybilnościowym,
- ApplicationStatus nie jest źródłem prawdy o obecności plików,
- stan procesu jest runtime’owy i nie jest zwykłym stanem katalogu.

### 3.4. Stan instalacji a stan procesu

InstallationState opisuje pliki:

~~~text
unknown → installing → installed
                    ├→ missing
                    └→ broken
uninstalled
~~~

ApplicationStatus opisuje launch:

~~~text
ready → preparing → starting → running → ready
                                      └→ needsAttention
unavailable
~~~

Instalacja może być missing, podczas gdy metadane i historia gry nadal istnieją. Aplikacja może mieć needsAttention, mimo że pliki gry są na dysku.

## 4. Providerzy sklepów

### 4.1. Wspólny kontrakt

Boreal/GameStoreProvider.swift definiuje operacje biblioteki, szczegółów, rozmiaru, instalacji, update, verify, uninstall i launch planu. GameStoreProviderCapabilities oznacza rzeczywiście obsługiwane operacje. Brak capability oznacza brak obsługi, a nie pustą akcję w UI.

### 4.2. Macierz

| Provider | Biblioteka | Instalacja | Update/verify/uninstall | Launch plan | Runtime |
|---|---:|---:|---:|---:|---|
| Steam | Tak, lokalne VDF/cache + API | Nie dla natywnego klienta | Nie jako direct provider operation | Nie dla natywnego Steam; Windows przez klienta | Jeden wspólny Windows Steam environment |
| Epic | Tak przez Legendary | Tak | Tak | Tak | Oddzielny environment gry |
| GOG | Tak przez GOG API + gogdl | Tak | Tak | Tak | Oddzielny environment gry |

### 4.3. Steam natywny i Windows Steam

SteamLibraryService czyta:

~~~text
~/Library/Application Support/Steam/
├── config/loginusers.vdf
├── userdata/<account>/config/localconfig.vdf
├── userdata/<account>/config/librarycache/
├── steamapps/appmanifest_<appid>.acf
└── libraryfolders.vdf
~~~

Łączy bibliotekę użytkownika, cache, manifesty, dodatkowe biblioteki Steam, Store API, App Reviews API i ProtonDB.

Boreal nie zastępuje natywnego klienta Steam przez SteamCMD. Dla Windows Steam:

1. SteamWindowsService pobiera oficjalny SteamSetup.exe po HTTPS.
2. InstallerService tworzy wspólny prefix WoW64.
3. Instalator tworzy steam.exe.
4. Steam pobiera i zarządza grami.
5. Boreal uruchamia grę przez steam.exe -applaunch <AppID>.

Bootstrap klienta używa steam.exe -silent. Wspólny prefix klienta nie powinien być zastępowany osobnym prefixem każdej gry Steam.

### 4.4. Epic / Legendary

LegendaryEpicService używa:

~~~text
Tools/Legendary/0.21.0/legendary
Accounts/Epic/
~~~

Helper jest pobierany dla właściwej architektury i weryfikowany SHA-256. user.json wskazuje stan połączenia.

Operacje obejmują:

~~~text
legendary auth --code <code>
legendary list --platform Windows --json
legendary list-installed --json --show-dirs
legendary info <id> --platform Windows|Mac --json
legendary -y install <id> --platform Windows --base-path <root> --skip-dlcs
legendary -y install <id> --update-only --skip-dlcs
legendary verify <id>
legendary -y uninstall <id>
legendary launch <id> --json --wine <wine> --wine-prefix <prefix>
~~~

Boreal nie wykonuje providerowego pre_launch_command. Waliduje executable i working directory, a z providerowego środowiska usuwa WINEPREFIX i PATH, bo te wartości kontroluje Boreal.

### 4.5. GOG / gogdl

GOGService używa:

~~~text
Tools/GOGDL/1.3.0/gogdl
Accounts/GOG/auth.json
Accounts/GOG/gogdl/
Games/GOG/
~~~

Helper jest pobierany i weryfikowany SHA-256. Biblioteka korzysta z listy produktów, gamesdb.gog.com i lokalnego wykrywania manifestu.

Operacje obejmują:

~~~text
gogdl auth --code <code>
gogdl auth
gogdl info <id> --platform windows|osx --lang en-US --skip-dlcs
gogdl download <id> --path <path> --platform windows|osx --skip-dlcs
gogdl update <id> --path <path> --platform windows|osx --skip-dlcs
gogdl repair <id> --path <path> --platform windows|osx --skip-dlcs
~~~

Launch GOG jest wyprowadzany z goggame-<id>.info. Boreal wybiera primary playTask, rozwiązuje executable względem katalogu instalacji i odrzuca ścieżki wychodzące poza grę.

### 4.6. Dodatkowe źródła zewnętrzne

- Steam Store/App Reviews — metadane, wymagania, oceny, liczba graczy.
- ProtonDB — zewnętrzna ocena kompatybilności, nie dowód działania lokalnego runtime’u.
- AppleGamingWiki — Discovery.
- ITAD — ceny i historia cen.

Źródła te nie tworzą prefixu i nie są dowodem, że konkretny proces zadziałał.

## 5. Runtime — model i budowa

### 5.1. Immutable package

Runtime jest wersjonowanym, samowystarczalnym pakietem. Boreal nie szuka Wine w Homebrew, MacPorts, /usr/local, /opt/homebrew ani globalnym PATH.

~~~text
BorealRuntime/
├── Runtime/Wine.app/
├── Dependencies/
├── Support/
│   ├── wine-mono/
│   ├── wine-gecko/
│   └── winetricks
├── Licenses/THIRD_PARTY_NOTICES.txt
├── SBOM.spdx.json
└── runtime.json
~~~

Wymagane executable:

~~~text
Runtime/Wine.app/Contents/Resources/wine/bin/wine
Runtime/Wine.app/Contents/Resources/wine/bin/wineserver
Runtime/Wine.app/Contents/Resources/wine/bin/wineboot
~~~

Runtime jest read-only po publikacji. Prefix gry pozostaje osobnym, mutable katalogiem.

### 5.2. Manifest

runtime.json opisuje id, wersję Wine, revision Boreal, architekturę, minimalny macOS, kanał, requirements, features, components i layout.

Features obejmują WoW64, Mono, Gecko, D3DMetal, DXMT, DXVK, VKD3D, esync, msync, fullscreen FSR i capabilities grafiki.

BorealRuntime jest wpisem katalogowym z artefaktem, hashem i rozmiarem. InstalledRuntime jest opisem rzeczywistego snapshotu na dysku.

Engine:

~~~text
features.d3dmetal == true  → Game Porting Toolkit
w przeciwnym razie         → Wine
~~~

### 5.3. Builder

Tools/RuntimeBuilder/build-runtime.sh:

~~~bash
Tools/RuntimeBuilder/build-runtime.sh \
  upstream-wine.tar.xz \
  runtime.json \
  ./Dependencies \
  ./Support \
  ./Licenses \
  ./SBOM.spdx.json \
  ./dist/BorealRuntime.tar.xz
~~~

Kroki:

1. walidacja argumentów i JSON,
2. sprawdzenie schemaVersion == 1,
3. rozpakowanie upstream .tar.xz,
4. znalezienie Wine*.app,
5. normalizacja do Runtime/Wine.app,
6. dodanie dependencies, support, licencji i SBOM,
7. sprawdzenie wine, wineserver, wineboot,
8. sprawdzenie notices/SBOM,
9. audyt Mach-O przez otool -L,
10. utworzenie .tar.xz,
11. wydruk SHA-256 i compressed size.

Hash i rozmiar artefaktu trafiają do zewnętrznego katalogu; nie są samoodwołaniem w pakiecie.

### 5.4. Trust chain

SignedRuntimeCatalogLoader:

1. pobiera catalog.json i catalog.sig,
2. weryfikuje podpis Ed25519,
3. dekoduje wpisy,
4. przekazuje wpis do RuntimeManager,
5. ten sprawdza hash, rozmiar, ścieżki archiwum, symlinki, manifest, requirements, layout i smoke test,
6. dopiero potem publikuje runtime atomowo i jako read-only.

Podpis katalogu Boreal jest niezależny od podpisu/notaryzacji Apple.

### 5.5. Aktualny stan katalogu

W BorealServices.live:

- w DEBUG lokalny katalog można podać przez BOREAL_RUNTIME_CATALOG,
- poza DEBUG używany jest EmptyRuntimeCatalog,
- produkcyjne URL katalogu i embedded Ed25519 public key nie są skonfigurowane w tym checkoutcie.

Architektura podpisanego katalogu istnieje, ale bieżący production wiring nie udostępnia automatycznie katalogu do pobierania runtime’ów. Zainstalowane i jawnie importowane lokalne runtime’y działają niezależnie od tego ograniczenia.

## 6. Instalacja i import runtime’u

### 6.1. Walidacja

RuntimeManager.validate sprawdza:

- trzy executable,
- runtime.json, Dependencies, Support, Licenses, notices i SBOM,
- requirements macOS/Rosetta,
- wynik wine --version,
- zgodność wersji z manifestem,
- dla GPTK rzeczywistą tożsamość GPTK, nie samą wersję Wine.

Runtime jest gotowy dopiero po przejściu całego zestawu.

### 6.2. Instalacja z katalogu

~~~text
catalog entry
   │
   ├── validateManifest
   ├── sprawdź wymagania
   ├── download → Runtimes/.downloads/<transaction>.tar.xz
   ├── sprawdź rozmiar i SHA-256
   ├── sprawdź listę archiwum pod kątem / i ..
   ├── extract → Runtimes/.installing/<transaction>
   ├── sprawdź symlinki/layout
   ├── porównaj runtime.json z katalogiem
   ├── validate + wine --version
   ├── smokeTest w disposable prefixie
   ├── zapisz installed-runtime.json
   ├── atomowo przenieś do Runtimes/<id>
   └── makeImmutable
~~~

Przy błędzie usuwane są download, staging i częściowy destination.

### 6.3. Import lokalnego Wine/GPTK

localRuntimeCandidates() szuka aplikacji .app bezpośrednio w /Applications i ~/Applications. Discovery jest read-only i sprawdza executable, Bundle version, minimalny macOS, Mach-O architecture, GPTK markers i WoW64.

importLocalRuntime:

1. akceptuje wyłącznie dozwoloną lokalizację,
2. kopiuje całe Wine.app do .installing,
3. dodaje dependencies/support/licenses/SBOM,
4. generuje lokalny manifest,
5. sprawdza symlinki, executable i layout,
6. wykonuje wine --version,
7. wykonuje wineboot --init w izolowanym prefixie,
8. zapisuje installed-runtime.json,
9. publikuje snapshot atomowo,
10. ustawia go read-only.

Lokalny snapshot ma origin localImport, czyli jest zwalidowany lokalnie, ale nie jest poświadczony przez katalog Boreal. Gdy GPTK nie ma oczekiwanego wineboot, Boreal tworzy wrapper Support/wineboot.

### 6.4. WoW64

Dla lokalnego payloadu sprawdzane są:

~~~text
Contents/Resources/wine/lib/wine/i386-windows/ntdll.dll
Contents/Resources/wine/lib/wine/x86_64-windows/wow64cpu.dll
Contents/Resources/wine/bin/wine64
~~~

PE32 i tryb prefixu są różne:

- PE32 mówi, że executable jest 32-bitowy,
- WoW64 mówi, że runtime obsługuje 32- i 64-bitowe aplikacje w jednym prefixie.

W nowoczesnym WoW64 WINEARCH musi być usunięte, a nie ustawione na win64.

## 7. Environment i tworzenie prefixu

### 7.1. Model

ManagedBorealEnvironment przechowuje id, configuration, runtimeID, rootURL, prefixURL, logsURL, state i purpose.

~~~text
Environments/<uuid>/
├── environment.json
├── prefix/
└── Logs/
~~~

Runtime może być współdzielony przez wiele środowisk, ale prefix należy do konkretnego środowiska.

### 7.2. Tryby prefixu

| Tryb | WINEARCH | Wymaganie |
|---|---|---|
| wow64 | brak | runtime ma WoW64 |
| legacyWin32 | win32 | runtime nie jest nowoczesnym WoW64 |
| legacyWin64 | win64 | runtime nie jest nowoczesnym WoW64 |

W WoW64 executable x86 może działać w prefixie używającym układu Win64. Komponenty x64 trafiają do system32, a x32 do syswow64.

### 7.3. Transakcja tworzenia

EnvironmentManager.create tworzy rekord i log directory. Gotowość powstaje dopiero w initialize:

~~~text
create
  → environment.json: created
  → environment.json: initializing
  → .prefix-installing/
  → wineboot -u
  → czekaj na drive_c, dosdevices, system.reg, user.reg
  → winecfg /v <windowsVersion>
  → reg add RetinaMode
  → konfiguracja WineBus, jeśli capability istnieje
  → reset/aktywacja graphics backend
  → instalacja dependencies
  → walidacja
  → moveItem(.prefix-installing, prefix)
  → environment.json: ready
~~~

Zasady:

- staging i final prefix są usuwane przed nową próbą,
- nie publikuje się niekompletnego prefixu,
- kompletność jest sprawdzana niezależnie od exit code wineboot,
- przy błędzie staging i final prefix są usuwane,
- rekord otrzymuje stan invalid,
- retry zaczyna od nowego staging directory.

### 7.4. Środowisko procesu

~~~text
WINEPREFIX=<environment>/prefix
WINEARCH=win32|win64          # tylko tryby legacy
PATH=<runtime>/wine/bin:<system-path>
WINEESYNC=1|0                 # jeśli runtime ma esync
WINEMSYNC=1|0                 # jeśli runtime ma msync
WINE_FULLSCREEN_FSR=1|0      # jeśli runtime ma FSR
WINEDLLPATH=<DXMT unix path>  # tylko DXMT
WINEDEBUG=-all,+fps           # lub +all,+fps
~~~

Boreal resetuje odziedziczone WINEARCH, WINEDLLPATH, WINEDLLOVERRIDES, WINEESYNC, WINEMSYNC i WINE_FULLSCREEN_FSR, po czym dodaje tylko wartości wynikające z konfiguracji.

### 7.5. Registry i dependencies

EnvironmentManager wykonuje realne polecenia:

~~~text
winecfg /v <windowsVersion>
wine reg add HKCU\Software\Wine\Mac Driver /v RetinaMode /t REG_SZ /d Y|N /f
~~~

Przy WineBus/SDL ustawiane są wartości pod HKLM\System\CurrentControlSet\Services\WineBus.

Obsługiwane zależności:

~~~text
legacyDirectX   → d3dx9
vc2010          → vcrun2010
vc2015To2022    → vcrun2019
xact            → xact
xinput          → xinput
dotNetFramework → dotnet48
physX           → physx
~~~

Najpierw używany jest Support/winetricks. Fallback pobiera skrypt do Tools/Winetricks/2026-09-04/winetricks. Receipt trafia do prefix/.boreal-dependencies/<dependency>. Status jest dodatkowo sprawdzany przez obecność bibliotek w system32/syswow64.

## 8. Backend graficzny

### 8.1. Ścieżki

| Backend | DirectX | Architektura | Host API | Wymagania |
|---|---|---|---|---|
| D3DMetal | DX11/DX12 | Win64 | Metal | GPTK + D3DMetal |
| DXMT | DX11 | Win64 | Metal | Wine + DXMT feature + package |
| DXVK | DX9/DX10/DX11 | Win32/Win64 | Vulkan | Wine + DXVK feature + DLL-e |
| VKD3D-Proton | DX12 | Win32/Win64 | Vulkan | Wine + VKD3D feature + d3d12.dll |
| WineD3D | DX9–DX12 | Win32/Win64 | OpenGL | brak dodatkowego pakietu |

Resolver uwzględnia API, architekturę, features runtime’u, obecność bibliotek, profil gry i ranking. Sama nazwa wersji Wine nie jest capability.

### 8.2. Profile i Automatic

Profil gry może mieć preferredBackend, enforcedBackend, defaultAPI, enforcedAPI, argumenty i zmienne środowiskowe. Wymuszony, niedostępny backend powinien wygenerować błąd. Automatyczny wybór może użyć kompatybilnego fallbacku, ale nie udaje obecności komponentu.

### 8.3. Komponenty

RuntimeManager obsługuje pakiety z:

- 3Shain/dxmt,
- Gcenx/DXVK-macOS,
- HansKristian-Work/vkd3d-proton.

Dla każdego artefaktu sprawdzane są release, HTTPS, host, rozmiar, digest jeśli jest dostępny, bezpieczne rozpakowanie, architektura DLL-i i wymagany zestaw plików.

~~~text
Runtimes/<id>/GraphicsComponents/
├── DXMT/x64/*.dll
├── DXMT/x32/*.dll
├── DXMT/x64-unix/winemetal.so
├── DXVK/x64/*.dll
├── DXVK/x32/*.dll
└── VKD3D/x64/*.dll
~~~

component.json przechowuje komponent, wersję, repozytorium i czas instalacji. Instalacja komponentu jest transakcyjna i odtwarza poprzedni katalog przy błędzie.

### 8.4. Aktywacja w prefixie

GraphicsBackendManager:

1. resetuje poprzednią aktywację,
2. wybiera x64/x32,
3. dla WoW64 kopiuje x64 do system32, x32 do syswow64,
4. backupuje istniejące DLL-e w .graphics-backup,
5. kopiuje obsługiwane DLL-e,
6. zapisuje .graphics-backend.json,
7. EnvironmentManager wpisuje aktywne override’y native,builtin.

Reset usuwa zarządzane DLL-e, odtwarza backupy i usuwa manifest.

### 8.5. Fallback renderera

RendererLaunchFailureDetector wymaga zarówno wskazówki Direct3D/Vulkan/DXVK/MoltenVK, jak i błędu tworzenia urządzenia/bufora albo odpowiednika.

~~~text
graphicsBackend = wineD3D
graphicsFallback = wineD3DVulkan
WINED3D_RENDERER=vulkan
WINEDLLOVERRIDES=<relevant DLL>=b
~~~

Zapisywany jest CompatibilityFallbackEvent z log reference. Fallback nie zmienia profili gry z wymuszonym backendem.

## 9. Od executable do procesu

### 9.1. Analiza PE i discovery

ExecutableDiscovery i ExecutableCompatibilityAnalyzer klasyfikują:

~~~text
game, launcher, installer, updater, helper, uninstaller, unknown
~~~

Architektura PE:

~~~text
Optional Header 0x10B → PE32 / x86
Optional Header 0x20B → PE32+ / x86_64
~~~

Konfigurator, updater, uninstaller i helper nie mogą zastąpić głównej gry. Dodatkowe executable są AuxiliaryExecutable i działają w tym samym środowisku.

### 9.2. Przygotowanie kompatybilności

CompatibilityPreparationResolver scala analizę executable, profil użytkownika, profil gry, DirectX, features runtime’u i dependencies. Wynikiem są executable, executableArchitecture, launcherArchitectures, prefixMode, windowsVersion, directXAPI, graphicsStack, dependencies i runtimeID.

### 9.3. Runtime selection

RuntimeSelectionRequest może wymagać architektur, prefix mode, backendu, DirectX, engine, profilu gry i konkretnego runtime ID.

Kolejność prepareReadyRuntime:

1. filtrowanie zainstalowanych runtime’ów,
2. walidacja przed użyciem,
3. preferowanie WoW64 w trybie automatycznym,
4. próba importu lokalnego runtime’u,
5. próba instalacji z katalogu,
6. noCompatibleRuntime, jeśli żaden kandydat nie przejdzie warunków.

### 9.4. Launch plans

WindowsLaunchPlan zawiera executable, arguments, environment, workingDirectory, overlayCompatibleFullscreen i overlayDisplayID.

Plan może pochodzić ze Steam, Epic, GOG, własnego executable, auxiliary executable albo instalatora. LaunchPlan dodaje ID aplikacji/środowiska/runtime’u, resolved graphics stack, prefix mode, DirectX, dependencies, purpose i architekturę executable.

### 9.5. Kolejność launchu

~~~text
toggleRunning
   → znajdź environment.json i InstalledRuntime
   → odczytaj profil
   → wybierz bezpośredni game executable
   → wykryj DirectX, jeśli potrzeba
   → GameLaunchCompatibility.prepare
   → EnvironmentManager.configure
   → providerowy WindowsLaunchPlan
   → launch arguments / profile environment / wrapper
   → pełny LaunchPlan
   → LaunchCoordinator.start
   → WindowsProcessRunner.run
~~~

GameLaunchCompatibility może przygotować np. steam_appid.txt lub shim WinRT przed uruchomieniem.

### 9.6. Argumenty Wine i logi

WineLaunchArguments:

- MSI uruchamia przez msiexec /i,
- zwykłe executable dostaje ścieżkę Windows,
- overlay fullscreen może użyć explorer /desktop=....

Ścieżka w prefixie jest tłumaczona do C:\..., a plik poza prefixem do Z:\....

SystemProcessExecutor ustawia executable, argumenty, environment, working directory i stdout/stderr. Logi launchu:

~~~text
Environments/<uuid>/Logs/launch-<timestamp>-<id>.stdout.log
Environments/<uuid>/Logs/launch-<timestamp>-<id>.stderr.log
~~~

## 10. Instalatory i istniejące gry

### 10.1. Pełna instalacja

InstallerService.install:

1. odczytuje architekturę instalatora,
2. wybiera runtime,
3. tworzy i inicjalizuje environment,
4. uruchamia instalator,
5. skanuje różnicę plików w drive_c,
6. wybiera executable,
7. analizuje grę i grafikę,
8. konfiguruje environment,
9. instaluje zależności,
10. zwraca InstallationCommit.

Dla Windows Steam wymaga wspólnego runtime’u zdolnego do x86 i x86_64.

### 10.2. Sam instalator

launchInstaller:

- akceptuje tylko regularny EXE albo MSI,
- tworzy i inicjalizuje environment,
- uruchamia wybrany instalator,
- nie wykrywa automatycznie gotowej gry,
- nie uruchamia znalezionego executable,
- zwraca sesję instalatora.

To jest uruchomienie wybranego programu Windows, a nie natywny system instalacyjny z własnym parserem postępu.

### 10.3. Istniejąca instalacja

Boreal nie kopiuje plików istniejącej gry. Tworzy runtime/prefix, a executable pozostaje na miejscu. .app jest akceptowany wyłącznie dla gry z supportsNativeMacOS; .exe musi być kwalifikowanym executable.

## 11. Monitorowanie i recovery

Boreal monitoruje dwa poziomy:

~~~text
launcher/process session
  → waitForExit → PID, exit code, stdout/stderr

Wine environment session
  → wineserver -w → czy środowisko ma aktywne procesy
~~~

### 11.1. Stop

1. zatrzymanie launcher process,
2. wineboot --end-session,
3. oczekiwanie na koniec środowiska,
4. w razie potrzeby wineserver -k,
5. dezaktywacja kontrolera i play session,
6. powrót do ready.

### 11.2. Błąd

Przy niezerowym exit code zapisywane są exit code, etap i log. Aplikacja przechodzi do needsAttention, chyba że był to jawny stop. Detector może zapisać jednorazowy fallback grafiki.

### 11.3. Restart aplikacji

Stan running przy zamknięciu jest niepewny. Po restarcie Boreal odtwarza environment/runtime i wykonuje wineserver -w:

- active — odtwarza monitoring i sesję,
- inactive — kończy sesję i ustawia ready,
- unknown — ustawia needsAttention zamiast udawać pewność.

## 12. Utrzymanie

### 12.1. Runtime updates

Runtime’y są side-by-side. Nowa wersja trafia do nowego katalogu; istniejący immutable runtime nie jest modyfikowany. Środowiska mogą zostać przepięte na nowy runtimeID tylko przy bezpiecznym stanie bez aktywnych operacji.

### 12.2. Component updates

DXMT/DXVK/VKD3D mają własne receipty i aktualizują się niezależnie. Boreal blokuje zmianę komponentu, gdy runtime jest używany przez aktywną sesję. Po zmianie komponentu prefix wymaga ponownej konfiguracji/aktywacji.

### 12.3. Game maintenance

Operacje są kierowane przez GameStoreProviderRegistry:

- Epic → Legendary,
- GOG → gogdl,
- Steam → klient Steam albo brak direct-provider operation zgodnie z capability.

Postęp trafia do StoreDownloadRecord, a biblioteka jest resynchronizowana.

### 12.4. Usuwanie

- usunięcie aplikacji może usunąć jej environment, jeśli nie jest współdzielony,
- GOG przenosi instalację do kosza,
- Epic wywołuje legendary -y uninstall,
- Steam deleguje instalację klientowi Steam.

## 13. Diagnostyka

### 13.1. Runtime

| Objaw | Sprawdzenie |
|---|---|
| Runtime verification failed | installed-runtime.json, runtime.json, executable, wine --version. |
| Brak 32-bit | WoW64 features i i386-windows/ntdll.dll + wow64cpu.dll/wine64. |
| WINEARCH odrzucony | Tryb WoW64 musi usuwać odziedziczone WINEARCH. |
| GPTK rozpoznany jako Wine | Bundle name i markery D3DMetal w payloadzie. |
| Częściowy import | Czy staging doszedł do atomowego moveItem. |

### 13.2. Prefix

~~~text
Environments/<uuid>/environment.json
Environments/<uuid>/Logs/wineboot.stderr.log
Environments/<uuid>/Logs/winecfg.stderr.log
Environments/<uuid>/Logs/wine-registry.stderr.log
Environments/<uuid>/prefix/drive_c
Environments/<uuid>/prefix/dosdevices
Environments/<uuid>/prefix/system.reg
Environments/<uuid>/prefix/user.reg
~~~

preserveFailureDiagnostics kopiuje logi do Logs/EnvironmentFailures/<uuid>-<token>/.

### 13.3. Grafika

~~~text
Runtimes/<id>/GraphicsComponents/<DXMT|DXVK|VKD3D>/
Environments/<uuid>/.graphics-backend.json
Environments/<uuid>/.graphics-backup/
Environments/<uuid>/Logs/graphics-*.stderr.log
Environments/<uuid>/Logs/launch-*.stderr.log
~~~

features.dxvk == true nie wystarcza: muszą istnieć właściwe DLL-e, architektura i DirectX API.

### 13.4. Launch plan

BorealStore.lastLaunchPlans przechowuje ostatni niezmienny plan diagnostyczny. launchPlanDiagnostics(for:) pokazuje executable, argumenty, working directory, zmienne planu, runtime/prefix, resolved backend, DirectX i architekturę.

Exit code sam nie rozróżnia awarii executable, architektury, prefixu, providera, grafiki ani procesu potomnego. Zawsze trzeba czytać plan i log.

## 14. Bezpieczeństwo i własność

Sprawdzane są:

- bezpieczne ID runtime’u bez / i ..,
- względne ścieżki manifestu,
- executable/working directory providerów w dozwolonym root,
- brak absolutnych i parent-traversing ścieżek w archiwach,
- symlinki niewychodzące ze staging root,
- architektura PE bibliotek graficznych.

| Zasób | Właściciel |
|---|---|
| Runtime executable/payload | RuntimeManager |
| WINEPREFIX, WINEARCH, PATH | EnvironmentManager / WindowsProcessRunner |
| Registry prefixu | Wine przez EnvironmentManager |
| DLL-e backendów | GraphicsBackendManager |
| Providerowe executable/arguments | provider po walidacji Boreal |
| Finalny process launch | LaunchCoordinator + WindowsProcessRunner |
| UI snapshot | BorealStore + LibraryRepository |

Provider nie może przekierować launchu do innego prefixu ani runtime’u. Może dostarczyć argumenty, executable i dodatkowe zmienne, ale finalne środowisko narzuca Boreal.

## 15. Pełne przepływy

### 15.1. Epic/GOG

~~~text
sync provider
  → StoreLibraryGame(provider, externalID)
  → pobierz pliki gry
  → canonical GameInstallation
  → analiza executable/architektury
  → wybór DirectX i graphics stack
  → RuntimeManager wybiera/instaluje runtime
  → EnvironmentManager.create
  → wineboot → winecfg → registry → graphics → dependencies
  → provider tworzy bezpieczny WindowsLaunchPlan
  → zapis application + environment
  → LaunchCoordinator
  → WindowsProcessRunner
  → monitor process + wineserver + logs + playtime
~~~

### 15.2. Steam Windows

~~~text
SteamLibraryService
  → StoreLibraryGame z AppID
  → SteamWindowsService pobiera SteamSetup.exe
  → InstallerService tworzy wspólny WoW64 environment
  → SteamSetup instaluje steam.exe
  → Steam pobiera grę
  → Boreal czyta appmanifest_<AppID>.acf
  → steam.exe -applaunch <AppID>
  → wineserver monitoruje wspólny environment
~~~

### 15.3. Własny EXE lub instalator

~~~text
wybór pliku
  → walidacja rozszerzenia i regular file
  → analiza PE32/PE32+
  → odrzucenie installer/updater/helper jako głównej gry
  → wybór runtime’u
  → isolated environment
  → wineboot i konfiguracja
  → WindowsProcessRunner
  → dla pełnej instalacji discovery executable
  → zapis aplikacji/environment po sukcesie
~~~

WindowsApplicationRole.installer jest trwałym wpisem do uruchamiania instalatora w zarządzanym środowisku, a nie automatycznym systemem zarządzania instalacją.

## 16. Rozszerzanie systemu

### Nowy provider

1. dodać provider identity,
2. utworzyć service auth/library/installation,
3. utworzyć adapter GameStoreProvider,
4. zadeklarować tylko rzeczywiste capabilities,
5. dodać adapter do BorealServices.live,
6. walidować launch plan,
7. identyfikować rekordy po provider + externalID.

### Nowy runtime engine

1. rozszerzyć RuntimeEngine,
2. opisać features i manifest,
3. dodać layout i walidację payloadu,
4. rozszerzyć runtime selection,
5. wykrywać capability w plikach, nie po nazwie,
6. dodać UI dopiero po działającej ścieżce creation/launch.

### Nowy backend graficzny

1. dodać GraphicsBackend/GraphicsStack,
2. opisać API i architektury,
3. opisać required features/components,
4. dodać detekcję konkretnych bibliotek,
5. dodać instalację i receipt,
6. dodać aktywację/reset z backupem,
7. dodać registry overrides tylko dla aktywnych DLL-i.

### Zmiana engine/architektury gry

Nie podmieniać runtime’u w działającym prefixie:

~~~text
current application
  → wybierz kompatybilny runtime
  → utwórz replacement environment
  → initialize + configure + validate
  → przygotuj launch plan
  → przełącz application.environmentID
  → usuń stary environment po sukcesie
~~~

Pliki gry nie powinny być redownloadowane wyłącznie z powodu zmiany Wine/GPTK lub prefixu.

## 17. Granice obecnego stanu

1. Boreal nie ma centralnego backendu HTTP ani zdalnej bazy aplikacji.
2. Epic/GOG używają lokalnych helperów i zewnętrznych usług kont.
3. Podpisany loader katalogu runtime’ów istnieje, ale production wiring używa obecnie EmptyRuntimeCatalog.
4. Capability metadata musi być potwierdzona payloadem.
5. ProtonDB i store metadata nie zastępują lokalnej walidacji prefixu i launchu.
6. Exit code nie wystarcza do diagnozy.
7. ApplicationStatus, GameInstallation.state i EnvironmentSessionState są trzema różnymi osiami stanu.
8. Automatyczny fallback renderera jest ograniczony do rozpoznanego błędu i nie jest mechanizmem „spróbuj wszystkiego”.

## 18. Mapa plików

| Obszar | Plik |
|---|---|
| App composition | Boreal/BorealApp.swift, Boreal/BorealServices.swift |
| Orkiestracja | Boreal/BorealStore.swift |
| Runtime model | Boreal/RuntimeModels.swift |
| Runtime install/validation | Boreal/RuntimeManager.swift |
| Runtime builder | Tools/RuntimeBuilder/build-runtime.sh, Tools/RuntimeBuilder/runtime.example.json |
| Requirements/trust | Boreal/RuntimeRequirements.swift, Boreal/RuntimeSecurity.swift |
| Prefix model | Boreal/EnvironmentModels.swift |
| Prefix creation | Boreal/EnvironmentManager.swift |
| Graphics | Boreal/GameGraphicsProfiles.swift, Boreal/GraphicsBackendManager.swift, Boreal/GraphicsCompatibilityManager.swift |
| Launch | Boreal/ArchitectureServices.swift, Boreal/ProcessModels.swift |
| Processes | Boreal/SystemProcessExecutor.swift, Boreal/WindowsProcessRunner.swift |
| Installers | Boreal/InstallerService.swift, Boreal/ExecutableDiscovery.swift |
| Steam | Boreal/SteamLibraryService.swift, Boreal/SteamWindowsService.swift |
| Epic | Boreal/LegendaryEpicService.swift |
| GOG | Boreal/GOGService.swift |
| Provider boundary | Boreal/GameStoreProvider.swift |
| Persistent data | Boreal/BorealStorage.swift |
| Existing runtime docs | Documentation/P0-Runtime.md, Documentation/P0.7-Local-Runtime-Import.md, Documentation/Graphics-Capabilities.md |

## 19. Skrót całego schematu

~~~text
UI
 → BorealStore
 → analiza executable / metadata providera
 → RuntimeManager wybiera zwalidowany runtime
 → EnvironmentManager tworzy i konfiguruje prefix
 → GraphicsBackendResolver wybiera dostępny stack
 → provider tworzy WindowsLaunchPlan
 → Boreal scala profil, argumenty i ograniczenia środowiska
 → LaunchCoordinator tworzy LaunchSession
 → WindowsProcessRunner narzuca WINEPREFIX/PATH/architekturę
 → SystemProcessExecutor uruchamia wine
 → stdout/stderr trafiają do Logs
 → wineserver monitoruje całe środowisko
 → Boreal zapisuje status, playtime, fallbacki i diagnostykę
~~~

Najważniejsza granica architektoniczna: runtime jest współdzielonym, niemutowalnym pakietem; prefix jest osobnym, mutowalnym środowiskiem; provider dostarcza dane i plan gry; Boreal zachowuje kontrolę nad rzeczywistym runtime’em, prefixem, procesem i logami.
