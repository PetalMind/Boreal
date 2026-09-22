# Runtime, backend graficzny i DirectX — dokumentacja działania oraz audyt integracji

Data audytu: 2026-09-22
Zakres: wybór runtime, architektura prefixu, wykrywanie DirectX, wybór backendu graficznego, instalacja komponentów, konfiguracja środowiska i uruchamianie procesu Windows.

## 1. Wnioski wykonawcze

Boreal nie traktuje runtime, prefixu, API DirectX i renderera jako jednej opcji. Są to cztery powiązane, ale odrębne decyzje:

1. runtime określa silnik Wine/GPTK, dostępne architektury i deklarowane możliwości;
2. prefix mode określa sposób budowy prefixu — nowoczesny WoW64 albo jeden z trybów legacy;
3. DirectX API określa rodzinę API, której wymaga gra — DX9, DX10, DX11 albo DX12;
4. backend określa implementację tego API — D3DMetal, DXMT, DXVK, VKD3D albo WineD3D.

Wybór nie kończy się na wartości zapisanej w ustawieniach. Przed uruchomieniem Boreal ponownie rozwiązuje konfigurację dla konkretnej gry, sprawdza możliwości runtime i dopiero wtedy buduje `LaunchPlan`. W przypadku ustawienia `Automatic` wybierany jest najlepszy kwalifikujący się stos z katalogu backendów. W przypadku ręcznego wyboru niedostępny backend powinien zakończyć przygotowanie błędem, a nie cichym przełączeniem na inną technologię.

Najważniejsze ustalenia audytu:

- ogólna architektura jest spójna: runtime, API, backend i prefix są rozwiązywane w jednym przygotowaniu kompatybilności;
- D3DMetal i DXMT mają dodatkową walidację urządzenia D3D11; sama obecność bibliotek nie jest wystarczająca;
- analiza PE rozpoznaje teraz także Delay Import Directory, a ścieżki wyboru API korzystają ze wspólnego detektora zachowującego kandydatów, confidence i dowody;
- registry overrides są ograniczane do bibliotek właściwych dla wybranego backendu i API;
- nowe receipts komponentów zapisują SHA-256 każdego zainstalowanego pliku i sprawdzają je przy odczycie; starsze receipts pozostają czytelne, ale bez weryfikacji plików;
- mutacje prefixu i snapshot/restore są serializowane wspólną blokadą ścieżki; aktywacja DLL i registry ma snapshot poprzedniego stanu i próbę rollbacku;
- DXVK i VKD3D są obecnie rozpoznawane głównie po artefaktach DLL i metadanych komponentu, bez analogicznego testu urządzenia, swapchaina i prezentacji;
- DXVK ma później kontrolę obecności części bibliotek zależną od wybranego API, ale ogólne wykrywanie możliwości runtime jest przede wszystkim oparte o wariant x64;
- dla DXMT instalacja jest bardziej restrykcyjna: wymagane są warianty x64, warianty x86 dla runtime obsługującego x86, `winemetal.so` oraz pozytywny self-test;
- analiza automatycznych zależności obejmuje także wykonywalne pliki oznaczone jako `.unknown`, co pozwala znaleźć importy właściwego pliku gry, gdy skaner nie sklasyfikuje go jako `.game`;
- obecność w prefixie bibliotek VC++ nie jest sama w sobie dowodem instalacji redystrybucyjnego VC++; status VC++ wymaga jawnego markera instalacji Boreal;
- zbudowana aplikacja zawiera probe 64-bit, probe 32-bit i lokalny komponent `BorealLegacyGraphics`, ale nie zawiera pełnego Wine/GPTK. Runtime jest zewnętrznym pakietem instalowanym w `Application Support/Runtimes`;
- przy nowoczesnym WoW64 `WINEARCH` jest usuwane, a nie ustawiane na `win64`; `WINEARCH=win32`/`win64` występuje tylko przy trybach legacy;
- standardowy audyt runtime nie udowadnia, że każda wersja DXVK/VKD3D faktycznie tworzy urządzenie i prezentuje klatkę. To jest aktualna granica dowodu integracyjnego.

## 2. Model pojęciowy

### 2.1. Runtime

Runtime jest zainstalowanym pakietem zawierającym wykonawcze Wine lub GPTK, metadane, licencje, SBOM i opcjonalne komponenty graficzne. Model `InstalledRuntime` przechowuje między innymi:

- `id`, nazwę i wersję Wine;
- `rootURL` oraz ścieżki do `wine`, `wineserver` i `wineboot`;
- architekturę oraz capabilities uruchamiania PE32 i PE32+;
- silnik `wine` albo `gamePortingToolkit`;
- flagi `d3dmetal`, `dxmt`, `dxvk`, `vkd3d`, `esync`, `msync`;
- stan weryfikacji, w tym `d3dmetalVerified`, `d3d11Verified` i zweryfikowane architektury D3D11;
- źródło instalacji i informacje o wymaganych komponentach.

`RuntimeEngine` ma dwa warianty:

| Silnik | Znaczenie | Domyślna rodzina grafiki |
|---|---|---|
| `wine` | klasyczny Wine, także nowoczesny WoW64 | WineD3D; opcjonalnie DXMT, DXVK lub VKD3D |
| `gamePortingToolkit` | runtime oparty na GPTK | D3DMetal |

Starsze manifesty mogą nie mieć jawnego pola silnika. Wtedy GPTK jest wnioskowany tylko w ograniczonym przypadku, gdy manifest deklaruje D3DMetal. Nie należy utożsamiać samego braku pola `engine` z pełną diagnozą runtime.

### 2.2. Prefix

`WinePrefixMode` rozróżnia:

| Tryb | `WINEARCH` | Logiczna architektura prefixu | Zastosowanie |
|---|---|---|---|
| `wow64` | brak | Win64 z obsługą aplikacji 32-bit | preferowany tryb dla runtime z nowoczesnym WoW64 |
| `legacyWin32` | `win32` | Win32 | zgodność ze starszymi runtime i grami 32-bit |
| `legacyWin64` | `win64` | Win64 | zgodność ze starszymi runtime 64-bit |

Ważne: `wow64` nie jest tym samym co `legacyWin64`. W WoW64 brak `WINEARCH` jest zamierzony — środowisko jest tworzone w natywnym, nowoczesnym układzie runtime, a nie przez wymuszenie starego trybu `win64`.

### 2.3. DirectX API

`GraphicsAPI` ma wartości `automatic`, `directX9`, `directX10`, `directX11` i `directX12`. API jest ustalane według następującej kolejności:

1. backend/profile wymuszający konkretną wartość;
2. wybór użytkownika zapisany w konfiguracji gry;
3. domyślne API profilu gry;
4. detekcja z pliku wykonywalnego;
5. wartość automatyczna, jeśli żadna z powyższych informacji nie wystarczy.

Wybór API używa `DirectXDetector` i `WindowsPEInspection`. Dla poprawnego PE analizowane są tablice zwykłych importów oraz opóźnionych importów (Delay Import Directory); wariant `analyze` zachowuje kandydatów wraz z confidence i dowodami. `dxgi.dll` sama w sobie nie rozstrzyga wersji DirectX, bo jest wspólną biblioteką wielu ścieżek. Dla danych niebędących PE istnieje ograniczone skanowanie tekstowych sygnatur z niższym confidence. Dla zgodności ze starszymi call-site'ami `detect` zwraca najwyżej uszeregowanego kandydata, jeśli jest ich kilka; dlatego sama niejednoznaczność nie zatrzymuje jeszcze automatycznego wyboru. Analiza pliku nadal nie dowodzi, które API gra wybierze w czasie działania.

### 2.4. Backend graficzny

`GraphicsBackend` reprezentuje implementację renderera:

| Backend | API | Architektura | Host API | Wymagania |
|---|---|---|---|---|
| D3DMetal | DX11, DX12 | Win64 | Metal | GPTK oraz zweryfikowany D3DMetal |
| DXMT | DX10, DX11 | Win32, Win64 | Metal | flaga DXMT, komponent DXMT i pozytywny self-test D3D11 |
| DXVK | DX9, DX10, DX11 | Win32, Win64 | Vulkan | flaga DXVK i komponent DXVK |
| VKD3D | DX12 | Win32, Win64 | Vulkan | flaga VKD3D i komponent VKD3D |
| WineD3D | DX9, DX10, DX11 | Win32, Win64 | OpenGL | brak dodatkowego komponentu |

`Automatic` nie jest osobnym rendererem. Jest żądaniem uruchomienia resolvera, który wybiera jeden z powyższych stosów.

## 3. Skąd pochodzi wybór konfiguracji

### 3.1. Konfiguracja środowiska

`EnvironmentConfiguration` przechowuje między innymi:

- `runtimeID`;
- Windows version;
- wykrytą lub wymuszoną architekturę wykonywalnego pliku;
- `prefixMode`;
- `graphicsBackend`;
- `graphicsAPI`;
- `graphicsFallback`;
- esync/msync, FSR i upscaling;
- wymagane zależności;
- referencje do komponentów graficznych.

Konfiguracja środowiska jest zapisana w `environment.json`, ale podczas uruchamiania nie jest ślepo zaufana. `BorealStore` pobiera aktywny runtime, profil gry i wykonywalny plik, a następnie ponownie tworzy plan uruchomienia.

### 3.2. Profil gry

`GameGraphicsProfiles` może określać:

- wykrywane API;
- preferowany backend;
- backend wymuszony;
- argumenty startowe, np. `/dx9` lub `/dx11`;
- zamianę wykonywalnego pliku na wrapper/proxy;
- wymagane DLL i zależności;
- ograniczenia fullscreen/overlay;
- zmienne środowiskowe, np. konfigurację WineD3D.

Profil jest bardziej szczegółowym źródłem wiedzy niż sama detekcja PE. Przykładowe reguły obecne w kodzie obejmują profile wymuszające D3DMetal dla wybranych gier DX12, Titan Quest z opcjami `/dx11` i `/dx9`, Torchlight II z WineD3D DX9 oraz Dragon Age: Origins z WineD3D DX9 i `WINE_D3D_CONFIG=renderer=gl`.

Dla Sacred Gold GOG istnieje osobna ścieżka legacy: gra jest 32-bitowa i DirectDraw, profil preferuje DXMT, używa wrappera `BorealLegacyGraphics` i uwzględnia ograniczenia overlay/fullscreen. To nie jest równoważne z ogólnym przypadkiem DXVK dla gry DirectX 9.

### 3.3. Interfejs użytkownika

`WineCompatibilityConfigurator` pokazuje użytkownikowi:

- runtime: automatyczny albo konkretny zainstalowany i zweryfikowany runtime;
- DirectX API;
- renderer/backend;
- renderer WineD3D;
- Windows version;
- executable architecture;
- prefix mode;
- opcje zaawansowane.

Opcje niekwalifikujące się dla wybranego runtime są wyłączane i otrzymują powód. Interfejs nie powinien być traktowany jako jedyne miejsce egzekwowania reguł: ta sama walidacja jest powtarzana w przygotowaniu uruchomienia.

### 3.4. Automatyczne zależności gry

`ExecutableAnalysis.importantExecutables` wybiera wykonywalne pliki o rolach `.game`, `.launcher` i `.unknown`. Włączenie `.unknown` pozwala uwzględnić zagnieżdżony właściwy plik gry, na przykład `*-Win64-Shipping.exe` w instalacji Unreal, nawet gdy heurystyka nazwy nie potrafiła przypisać mu roli `.game`. `AutomaticRuntimeDependencyDetection` scala zależności wymagane przez te pliki.

`RuntimeDependencyResolver` analizuje importy i nazwy bibliotek dla takich elementów jak legacy DirectX, VC++ 2010, VC++ 2015–2022, XACT, XInput, .NET Framework i PhysX. To analiza PE, niezależna od wyboru backendu renderującego DirectX: `d3d11.dll`/`d3d12.dll` opisuje API grafiki, natomiast np. `msvcp140.dll` wskazuje zależność VC++.

Status zainstalowanych zależności jest odczytywany z bibliotek w prefixie i markerów `.boreal-dependencies/<dependency>`. Dla VC++ 2010 i VC++ 2015–2022 wymagany jest marker zapisany po pomyślnym zakończeniu instalacji przez winetricks. Wine zawiera własne kopie bibliotek o podobnych nazwach, więc samo ich znalezienie mogłoby błędnie oznaczyć natywny redystrybutor VC++ jako zainstalowany. Inne zależności mogą być potwierdzone bibliotekami lub markerem.

## 4. Resolver runtime i backendu

### 4.1. Wejście do `CompatibilityPreparationResolver`

`RuntimeSelectionRequest` przekazuje do resolvera:

- architekturę wykonywalnego pliku;
- żądany prefix mode;
- żądany backend;
- żądane API DirectX;
- profil gry;
- wymagany silnik runtime;
- opcjonalne wymuszenie `runtimeID`.

Resolver najpierw ustala główny wykonywalny plik, potem rozwiązuje prefix, API, backend i zależności automatyczne. Jeśli wybrany backend nie jest obsługiwany przez konkretny runtime, przygotowanie kończy się błędem niekompatybilności.

### 4.2. Kwalifikowanie runtime

Runtime musi przejść wszystkie poniższe filtry:

1. ma wymagane capabilities architektury PE;
2. obsługuje żądany lub automatycznie wybrany prefix mode;
3. ma właściwy silnik, jeżeli profil go wymaga;
4. odpowiada przypiętemu `runtimeID`, jeżeli użytkownik przypiął runtime;
5. przechodzi `GraphicsBackendResolver` dla danego API, architektury i profilu;
6. jest zainstalowany, poprawnie zwalidowany i ma wymagane pliki.

Przy automatycznym wyborze punktacja preferuje między innymi WoW64, lokalnie importowany runtime i lepiej dopasowany stack graficzny. Przypięcie runtime otrzymuje najwyższy priorytet; jeśli przypięty runtime nie spełnia wymagań, Boreal zgłasza błąd zamiast zmienić go po cichu.

### 4.3. Ranking backendów

Katalog `GraphicsStackCatalog` nadaje bazowe priorytety:

- D3DMetal: 95;
- DXMT: 90;
- DXVK: 88;
- VKD3D: 86;
- WineD3D: 10.

Do wyniku dochodzą preferencje profilu, preferencja Metal oraz premia za przejście probe D3D11 przez D3DMetal lub DXMT. Jawnie dostępny backend otrzymuje specjalny wynik explicit. Jeżeli użytkownik lub profil wymaga backendu, a ten jest niedostępny, wynik jest negatywny i konfiguracja nie powinna spaść na inny backend. Dla `Automatic` wybierany jest najwyżej oceniony backend kwalifikujący się do API, architektury i możliwości runtime. Resolver nie korzysta jeszcze z historii udanych uruchomień konkretnej gry.

### 4.4. Rzeczywiste warunki dostępności

Resolver sprawdza:

- D3DMetal: `hasVerifiedD3DMetal`, czyli jednocześnie flaga D3DMetal i pozytywna weryfikacja;
- DXMT: `dxmt == true`, `d3d11Verified == true` oraz zgodność zweryfikowanej architektury;
- DXVK: `dxvk == true`;
- VKD3D: `vkd3d == true`;
- WineD3D: brak dodatkowej flagi komponentu.

Dla DXVK dochodzi kontrola bibliotek zależna od API:

- DX9: `d3d9.dll` dla odpowiednich architektur;
- DX10: `d3d10core.dll`;
- DX11: `d3d11.dll`.

W trybie WoW64 logicznie trzeba uwzględniać część x64 i x32; dla trybów legacy używana jest odpowiednia pojedyncza architektura. To jest kontrola obecności plików, nie test urządzenia Vulkan.

## 5. Instalacja i walidacja runtime

### 5.1. Layout runtime

Canonical layout `RuntimeLayout` zakłada między innymi:

```text
Runtime/
  Wine.app/Contents/Resources/wine/bin/wine
  Wine.app/Contents/Resources/wine/bin/wineserver
  Wine.app/Contents/Resources/wine/bin/wineboot
Dependencies/
Support/
Licenses/
notices/
SBOM/
runtime.json
```

Zainstalowane runtime są odczytywane z `Application Support/Runtimes`. `RuntimeManager` odświeża cechy pakietu, weryfikuje ścieżki i odczytuje wersję przez `wine --version`.

`RuntimeValidation.isReady` wymaga:

- braku brakujących ścieżek;
- spełnienia wymagań manifestu;
- wykrytej wersji;
- zgodności wykrytej wersji z deklaracją.

Dla GPTK dodatkowo wymagana jest weryfikacja D3DMetal. Sama obecność binariów GPTK nie jest dowodem gotowości do uruchamiania gier.

### 5.2. Import lokalny i instalacja z katalogu

`RuntimeManaging.prepareReadyRuntime` kolejno rozpatruje:

1. zgodne, zainstalowane i zwalidowane runtime;
2. kandydatów lokalnych do importu;
3. dostępne runtime z katalogu, jeśli są pobrane i gotowe.

Import GPTK ma osobną ścieżkę wykrywania, ponieważ GPTK może mieć układ plików różniący się od standardowego pakietu Wine. Po imporcie capability są odświeżane i runtime jest ponownie walidowany.

### 5.3. Smoke test runtime

Smoke test tworzy tymczasowy prefix, uruchamia `wineboot --init`, czeka na wymagane ścieżki i sprawdza architektury. Dla GPTK wykonuje również probe D3DMetal/D3D11 x64.

Prefix używany do testu jest jednorazowy. Test nie jest testem konkretnej gry, lecz kontrolą minimalnej integralności runtime i jego podstawowego stosu graficznego.

## 6. Komponenty graficzne

### 6.1. Źródła

`RuntimeManager` zna źródła komponentów:

| Komponent | Źródło używane przez kod |
|---|---|
| DXVK | `Gcenx/DXVK-macOS` |
| DXMT | `3Shain/dxmt` |
| VKD3D | `HansKristian-Work/vkd3d-proton` |

Pobieranie jest ograniczone do HTTPS, sprawdzany jest rozmiar i digest, a archiwum jest rozpakowywane do stagingu. Instalacja nie powinna modyfikować aktywnego prefixu częściowo: komponent jest przygotowywany jako niezmienny artefakt, otrzymuje receipt, a dopiero potem jest używany przez resolver i menedżer backendu.

### 6.2. Minimalne wymagania instalacji

Podczas `installGraphicsComponent`:

- wykrywane są DLL komponentu;
- wbudowany DXVK jest odrzucany jako źródło instalacji;
- wymagane są pliki x64;
- dla DXMT runtime obsługujący x86 musi mieć również pliki x86;
- dla DXMT wymagana jest biblioteka `winemetal.so`;
- komponent otrzymuje manifest i receipt;
- receipt zawiera SHA-256 archiwum oraz SHA-256 każdego opublikowanego pliku DLL/biblioteki; store ponownie weryfikuje pliki przy enumeracji i użyciu komponentu;
- DXMT przechodzi probe D3D11 x64 oraz, jeśli runtime wspiera x86, probe x86;
- wynik DXMT jest zapisany w `d3d11Verified` i `d3d11VerifiedArchitectures`.

Dla DXVK i VKD3D instalacja kończy się na kontroli artefaktów, hashy i metadanych. Kod nie wykonuje dla nich odpowiednika pełnego testu urządzenia, feature level, swapchaina, render targetu, clear i present.

### 6.3. Bieżąca granica implementacji

`refreshingDetectedFeatures` rozpoznaje:

- DXMT po wymaganych DLL x64 i pozostałych artefaktach;
- DXVK po wymaganych DLL x64, w tym wariancie D9VK dla D3D9;
- VKD3D po x64 `d3d12`;
- esync/msync po artefaktach runtime;
- legacy wrappers po manifestach komponentów.

Wynika z tego konkretna granica audytu: obecność x64 DLL jest wystarczająca do deklaracji `dxvk`/`vkd3d` w capability, ale nie dowodzi kompletności obu architektur w każdym scenariuszu ani sprawności renderera na realnym adapterze. Późniejsza ścieżka DXVK dla konkretnego DX9/DX10/DX11 może wymagać konkretnej DLL, jednak nie zastępuje to testu runtime Vulkan.

## 7. Probe D3D11 i walidacja urządzenia

W aplikacji są dwa probe:

```text
BorealGraphicsProbe.exe    PE32+ x86-64
BorealGraphicsProbe32.exe  PE32 i386
```

Probe emituje markery analizowane przez `RuntimeManager`:

```text
BOREAL_DXGI_INITIALIZED
BOREAL_DXGI_ADAPTER_INITIALIZED
BOREAL_D3D11_DEVICE_INITIALIZED
BOREAL_D3D11_FEATURE_LEVEL=11_0
BOREAL_D3D11_SWAPCHAIN_INITIALIZED
BOREAL_D3D11_RENDER_TARGET_INITIALIZED
BOREAL_D3D11_CLEAR_SUCCEEDED
BOREAL_D3D11_PRESENT_SUCCEEDED
```

`D3D11SelfTestResult` wymaga całego łańcucha oraz kodu procesu równemu zero. Samo utworzenie urządzenia bez swapchaina, render targetu, clear i present nie jest uznawane za sukces.

### 7.1. Probe D3DMetal

Dla GPTK uruchomienie probe ustawia między innymi:

- `D3DMETAL_FRAMEWORK_PATH`;
- `DYLD_FALLBACK_LIBRARY_PATH`;
- `WINEDLLPATH`;
- native overrides dla bibliotek D3D.

Po pozytywnym probe runtime otrzymuje potwierdzenie D3DMetal. D3DMetal x86 nie jest dopuszczany w ścieżce self-testu — ten backend jest związany z układem Win64.

### 7.2. Probe DXMT

Dla DXMT aktywowany jest komponent przez `GraphicsBackendManager`, ustawiane są ścieżki DLL i native/builtin overrides, a następnie probe jest uruchamiany dla każdej obsługiwanej architektury. Wynik jest zapisany osobno dla x64 i x86.

To jest najmocniej zweryfikowany obecnie nie-D3DMetalowy backend w systemie: nie wystarcza paczka DLL, musi przejść rzeczywista inicjalizacja D3D11.

### 7.3. Czego probe nie obejmuje

Probe nie jest obecnie ogólnym testem wszystkich backendów. W szczególności nie potwierdza ścieżki Vulkan DXVK ani VKD3D. Z tego powodu status `dxvk == true` albo `vkd3d == true` należy interpretować jako „artefakty i konfiguracja są dostępne”, a nie jako „konkretny adapter hosta przeszedł prezentację dla tego backendu”.

Probe dotyczy osobnego procesu diagnostycznego, a nie procesu gry. Zwykłe uruchomienie nie zapisuje jeszcze niezależnego obserwatora bibliotek/rendererów załadowanych przez grę, więc zgodność `LaunchPlan`, manifestu, DLL i registry potwierdza konfigurację Boreal, ale nie pozwala wyświetlić uczciwego stanu „renderer gry potwierdzony”. W szczególności logi `WINEDEBUG=-all` nie są dowodem załadowania DXVK/DXMT przez grę.

## 8. Budowa i aktywacja backendu w prefixie

### 8.1. `GraphicsBackendManager`

Manager backendu:

1. rozwiązuje backend i sprawdza komponenty przed zmianą aktywnych plików;
2. zapisuje snapshot poprzedniego manifestu, plików backendu i backupów;
3. resetuje poprzednio zarządzane pliki;
4. dobiera wariant x64/x86 do trybu prefixu;
5. kopiuje biblioteki do właściwego katalogu prefixu;
6. zapisuje backup istniejących plików jako `.graphics-backup`;
7. zapisuje manifest `.graphics-backend.json`;
8. zwraca tylko nazwy DLL właściwe dla aktywowanego API do ustawienia w registry.

Jeśli aktywacja plików nie powiedzie się, Boreal odtwarza poprzedni stan prefixu ze snapshotu — również ścieżki DLL, które nie należały do poprzedniego manifestu i byłyby nadpisane przez nowy komponent. Operacje inicjalizacji, konfiguracji, importu registry, instalacji zależności, zmian wskaźnika NGX, snapshotu/restore i usuwania środowiska są dodatkowo serializowane przez wspólną blokadę ścieżki prefixu. Aktory zarządzające środowiskiem lub snapshotami mogą przyjąć kolejne żądanie podczas oczekiwania na proces Wine albo I/O, więc aktor samodzielnie nie serializuje całej operacji.

Zmiana backendu obejmuje także registry: przed aktywacją zapisywane są istniejące wartości obu wariantów nazw DLL (z `*` i bez), dopiero potem aktywowane są pliki i zmieniane overrides. Snapshot pozostaje niezatwierdzony do zakończenia instalacji wymaganych zależności i zapisu `environment.json`; błąd na tych etapach również wywołuje rollback DLL i overrides. Przy błędzie Boreal próbuje przywrócić poprzednie wartości registry oraz snapshot plików; jeśli rollback się nie powiedzie, zwracany jest osobny błąd o niepełnym odtworzeniu.

Ta blokada serializuje operacje Boreal, ale sama nie wykrywa działającego procesu Wine używającego prefixu. Ochrona przed zmianą backendu podczas aktywnej sesji nadal zależy od zabezpieczeń warstwy aplikacji; manager nie ma niezależnego `wineserver`/process guard.

Mapowanie plików jest następujące:

| Prefix | x64 | x86 |
|---|---|---|
| WoW64 | `system32` | `syswow64` |
| legacy Win32 | — | `system32` |
| legacy Win64 | `system32` | — |

Nazwy katalogów są historycznie specyficzne dla Wine: w prefixie `system32` oznacza bibliotekę 64-bit w WoW64, a `syswow64` bibliotekę 32-bit.

### 8.2. Reset i przenoszenie prefixu

`reset` odtwarza backupy i usuwa manifest backendu. `prefixDidMove` aktualizuje ścieżki w manifeście po atomowym przeniesieniu prefixu ze stagingu do finalnego środowiska.

Dzięki temu instalacja backendu nie jest trwale związana ze ścieżką tymczasową i może być wykonywana podczas przygotowania nowego środowiska.

### 8.3. WineD3D i D3DMetal

D3DMetal i WineD3D nie wymagają kopiowania pakietu DLL przez `GraphicsBackendManager` w ten sam sposób co DXMT/DXVK/VKD3D. Dla nich manager zwraca ścieżkę bez aktywacji zewnętrznego komponentu, a właściwe biblioteki/zmienne są dostarczane przez runtime albo konfigurację Wine.

## 9. Tworzenie i konfiguracja środowiska

### 9.1. Lifecycle środowiska

`EnvironmentManager` tworzy strukturę:

```text
Application Support/Boreal/Environments/<UUID>/
  prefix/
  Logs/
  environment.json
```

Nowe środowisko jest tworzone przez staging prefixu. W trakcie inicjalizacji występują między innymi:

1. sprawdzenie zgodności prefix mode;
2. marker `.prefix-installing`;
3. `wineboot -u`;
4. oczekiwanie na wymagane katalogi prefixu;
5. ustawienie Windows version, registry i backendu;
6. instalacja zależności;
7. atomowe przeniesienie staging prefixu do finalnej ścieżki;
8. aktualizacja manifestu komponentu graficznego.

Marker instalacji chroni przed uznaniem niepełnego prefixu za gotowy.

### 9.2. Registry DLL overrides

Przy zastosowaniu backendu Boreal usuwa stare overrides dla:

```text
d3d9 d3d10 d3d10_1 d3d10core d3d11 d3d12 d3d12core dxgi
```

Następnie wpisuje dla aktywnego backendu `native,builtin`. To jest istotne, ponieważ pozostałość z poprzedniego backendu mogłaby sprawić, że prefix deklarowałby inną ścieżkę niż bieżący `LaunchPlan`.

Lista nowych overrides jest filtrowana według API. DXVK/DX11 dostaje `d3d11` i `dxgi`, VKD3D/DX12 dostaje `d3d12`, `d3d12core` i `dxgi`, a DXVK/DX9 nie przejmuje bibliotek D3D11/D3D12. Dzięki temu instalacja pakietu zawierającego wiele translatorów nie wymusza ich wszystkich jednocześnie.

### 9.3. Środowisko procesu Wine

`wineEnvironment` ustawia co najmniej:

- `WINEPREFIX`;
- `PATH`, `WINE` i `WINE64` dla wybranego runtime;
- `WINEARCH` tylko dla trybów legacy;
- `WINEDLLPATH` dla backendów, które go wymagają;
- ścieżki komponentów graficznych;
- ustawienia FSR, jeśli są dozwolone przez capabilities.

Przed uruchomieniem czyszczone są odziedziczone zmienne, które mogłyby przeciekać z innego środowiska, w tym `WINEPREFIX`, `WINEARCH`, `WINEDLLOVERRIDES`, `WINEDLLPATH`, `WINE_D3D_CONFIG`, ścieżki D3DMetal oraz zmienne DXVK/Vulkan. Następnie Boreal ponownie ustawia wartości wynikające z bieżącego planu.

## 10. Proces uruchomienia gry

### 10.1. Od instalacji do startu

Uproszczony przepływ wygląda tak:

```text
wykrycie PE gry
        ↓
profil gry + konfiguracja użytkownika
        ↓
wybór API DirectX
        ↓
wybór prefix mode
        ↓
wybór runtime
        ↓
GraphicsBackendResolver
        ↓
CompatibilityPreparationResolver
        ↓
EnvironmentManager.configure
        ↓
GraphicsBackendManager.activate
        ↓
WindowsProcessRunner / LaunchPlan
        ↓
wine <game.exe>
```

Po instalacji gry `InstallerService` analizuje odkryte executable i ponownie rozwiązuje API, backend i zależności. Automatyczna analiza może objąć właściwy plik gry także wtedy, gdy jego rola pozostała `.unknown`. Dla instalatorów Steam Windows może wymagać jednocześnie obsługi x86 i x86_64, ponieważ sam launcher i gra mogą mieć różne architektury.

### 10.2. `LaunchPlan`

Plan uruchomienia niesie między innymi:

- wybrany runtime i jego ID;
- backend oraz stack graficzny;
- prefix mode;
- API DirectX;
- argumenty gry i argumenty profilu;
- automatyczne zależności;
- fingerprint konfiguracji;
- ścieżkę prefixu i logów.

Plan jest tworzony po uwzględnieniu providerów Steam/Epic/GOG, profilu gry, specjalnych argumentów API oraz ręcznych argumentów. Dla współdzielonego środowiska Steam profil gry może być ograniczony, aby nie przepisać konfiguracji używanej przez inne gry.

### 10.3. WindowsProcessRunner

Runner:

1. buduje argumenty Wine;
2. scala plan z konfiguracją środowiska;
3. czyści zmienne deweloperskie i odziedziczone;
4. aktywuje ścieżki backendu;
5. ustawia D3DMetal albo DXMT, jeżeli plan tego wymaga;
6. stosuje WineD3D fallback, jeżeli został przewidziany;
7. ponownie ustawia `WINEPREFIX`;
8. ustawia lub usuwa `WINEARCH` zgodnie z prefix mode;
9. uruchamia `wineExecutable` wybranego runtime;
10. zapisuje stdout/stderr do logów.

Dla ścieżek plików używanych przez prefix stosowane jest `C:\...`; dla plików spoza prefixu używana jest ścieżka `Z:\...`.

## 11. DirectX, backend i runtime — macierz zgodności

Poniższa macierz opisuje reguły wynikające z katalogu stacków, a nie gwarancję, że każda gra skorzysta z danej ścieżki bez dodatkowego profilu:

| API | D3DMetal | DXMT | DXVK | VKD3D | WineD3D |
|---|---:|---:|---:|---:|---:|
| DX9 | nie | nie jako ogólna reguła | tak | nie | tak |
| DX10 | nie | tak | tak | nie | tak |
| DX11 | tak | tak | tak | nie | tak |
| DX12 | tak | nie | nie | tak | nie |

Dodatkowe ograniczenia:

- D3DMetal wymaga GPTK i zweryfikowanego D3DMetal;
- DXMT wymaga komponentu, `winemetal.so` i pozytywnego self-testu D3D11;
- DXVK wymaga komponentu i właściwych DLL dla wybranego API/architektury;
- VKD3D wymaga komponentu i flagi VKD3D, ale nie ma analogicznego self-testu prezentacji;
- WineD3D jest fallbackiem o niskim priorytecie, ale nadal musi być zgodny z API i architekturą;
- profil gry może zawęzić lub wymusić backend niezależnie od ogólnej macierzy.

## 12. Co jest obecnie poprawnie skonfigurowane i zintegrowane

### Potwierdzone w kodzie

- runtime ma osobny model, layout, katalog, walidację i ścieżkę importu;
- silnik runtime jest powiązany z wymaganiami backendu;
- WoW64 i legacy mają odrębne reguły prefixu i środowiska;
- API DirectX może pochodzić z profilu, ustawień lub detekcji PE;
- resolver sprawdza API, architekturę, capabilities i komponenty;
- ręczne przypięcie runtime/backendu nie powinno być automatycznie zastępowane inną opcją;
- komponenty są instalowane przez staging, mają manifest/receipt i mogą być resetowane;
- backend jest odzwierciedlany zarówno w plikach prefixu, registry DLL overrides, jak i środowisku procesu;
- D3DMetal i DXMT mają dowód urządzenia D3D11 obejmujący swapchain, render target, clear i present;
- process runner reassertuje konfigurację po oczyszczeniu dziedziczonych zmiennych;
- artefakty aplikacji zawierają oba probe i lokalny `BorealLegacyGraphics`.

### Potwierdzone w aktualnym artefakcie aplikacji

W zbudowanym `Boreal.app` znajdują się:

```text
Resources/BorealGraphicsProbe.exe
Resources/BorealGraphicsProbe32.exe
Resources/GraphicsComponents/BorealLegacyGraphics/manifest.json
Resources/GraphicsComponents/BorealLegacyGraphics/x86/ddraw.dll
Resources/GraphicsComponents/BorealLegacyGraphics/x64-unix/winemac.so
```

Probe w aplikacji odpowiada probe w źródłach. Aplikacja nie zawiera jednak pełnego `Runtime/Wine.app`; to jest poprawne dla obecnego modelu, w którym runtime jest instalowany/importowany zewnętrznie.

### Granice poprawności, których kod sam nie dowodzi

- obecność DXVK/VKD3D w runtime nie jest równoznaczna z poprawną prezentacją na aktualnym GPU;
- detekcja DirectX z PE nie dowodzi rzeczywistego API użytego po uruchomieniu;
- pozytywny self-test D3DMetal/DXMT nie oznacza poprawności wszystkich gier i wszystkich ścieżek renderingu;
- lokalny `BorealLegacyGraphics` jest specjalizowanym komponentem dla ścieżki legacy/DirectDraw, a nie ogólnym zamiennikiem DXVK;
- z samego `runtime.example.json` nie można wnioskować o capabilities konkretnego zainstalowanego runtime — jest to przykład pakietu z flagami D3DMetal/DXMT wyłączonymi.

## 13. Diagnostyka problemu — kolejność czytania danych

Jeżeli gra nie startuje albo używa innego renderera niż oczekiwany, należy analizować w tej kolejności:

1. **Wykonywalny plik** — architektura PE, wykryte importy DX9/DX10/DX11/DX12, faktyczna ścieżka startowa.
2. **Profil gry** — backend/API wymuszony, argumenty, wrapper, zależności i zmienne WineD3D.
3. **Konfiguracja środowiska** — `runtimeID`, prefix mode, backend, API, referencje komponentu.
4. **Runtime manifest** — silnik, wersja, capabilities, ścieżki, stan weryfikacji.
5. **Resolver** — czy `runtimeSatisfies` i `GraphicsBackendResolver` uznały konfigurację za kwalifikującą się.
6. **Manifest prefixu** — `.graphics-backend.json`, backupy i docelowe katalogi `system32`/`syswow64`.
7. **Registry** — `HKCU\Software\Wine\DllOverrides` dla bibliotek D3D i DXGI.
8. **Log procesu** — `WINEPREFIX`, `WINEARCH`, `WINEDLLPATH`, D3DMetal/DXMT paths, argumenty i stderr.
9. **Probe** — dla D3DMetal/DXMT markery DXGI/D3D11; dla DXVK/VKD3D obecnie brak równoważnego dowodu w standardowym flow.

Objaw „wybrano DXVK, ale gra zachowuje się jak WineD3D” należy rozdzielić na co najmniej trzy przypadki:

- resolver wybrał WineD3D, ponieważ DXVK nie spełnił capabilities;
- resolver wybrał DXVK, ale aktywacja komponentu/prefixu nie została zastosowana;
- DXVK został aktywowany, lecz gra nie przeszła przez oczekiwane DLL/API albo problem wystąpił dopiero w Vulkanie.

Sam widok ustawień nie rozróżnia tych przypadków. Rozstrzygające są `LaunchPlan`, manifest backendu, log procesu i zawartość prefixu.

## 14. Zalecane kryterium „poprawnie skonfigurowane”

Konfigurację można uznać za poprawnie przygotowaną, gdy wszystkie poniższe warunki są spełnione:

- PE gry ma znaną architekturę lub jawnie wybraną architekturę;
- prefix mode jest obsługiwany przez runtime;
- `runtimeID` jest obecny i runtime przechodzi walidację;
- API DirectX wynika z profilu/ustawień/detekcji i jest zgodne z backendem;
- backend przechodzi resolver dla API i architektury;
- wymagany komponent ma manifest, receipt i właściwe warianty DLL;
- dla D3DMetal/DXMT istnieje pozytywna weryfikacja D3D11 dla używanej architektury;
- `environment.json`, `.graphics-backend.json`, registry i `LaunchPlan` wskazują ten sam backend;
- środowisko procesu nie dziedziczy starego `WINEARCH`, `WINEPREFIX`, override ani ścieżek bibliotek;
- log startu potwierdza wybrany runtime, prefix i komponent;
- obserwacja procesu gry potwierdza faktycznie załadowany backend — obecnie standardowy launch flow nie zbiera jeszcze takiego dowodu, więc tego punktu nie można uznać za spełniony;
- jeśli wymagane jest potwierdzenie Vulkan, obecna implementacja wymaga dodatkowego testu poza standardowym D3D11 probe, ponieważ DXVK/VKD3D nie są obecnie objęte takim testem.

Najpełniejszy obecny dowód wygląda zatem tak:

```text
runtime manifest + runtime validation
        +
compatibility resolver result
        +
environment.json
        +
graphics backend manifest and prefix DLLs
        +
registry overrides
        +
LaunchPlan and process log
        +
D3D11 probe where supported
```

Nie wolno zastępować tego dowodu samym wyborem wartości w UI.

## 15. Pliki i symbole referencyjne

Najważniejsze miejsca implementacji:

| Obszar | Plik |
|---|---|
| modele runtime, capabilities, layout | `Boreal/RuntimeModels.swift` |
| instalacja, walidacja, smoke test, probe | `Boreal/RuntimeManager.swift` |
| prefix mode i konfiguracja środowiska | `Boreal/EnvironmentModels.swift` |
| lifecycle prefixu i registry | `Boreal/EnvironmentManager.swift` |
| backendy, API i stacki | `Boreal/Models.swift`, `Boreal/GameGraphicsProfiles.swift` |
| wybór backendu | `GraphicsBackendResolver` w `Boreal/GameGraphicsProfiles.swift` |
| aktywacja DLL i manifest prefixu | `Boreal/GraphicsBackendManager.swift` |
| capability i komponenty runtime | `Boreal/GraphicsComponentStore.swift`, `Boreal/RuntimeManager.swift` |
| przygotowanie kompatybilnego runtime | `Boreal/CompatibilityPreparation.swift` |
| konfigurator użytkownika | `Boreal/WineCompatibilityConfigurator.swift` |
| przygotowanie launch planu | `Boreal/BorealStore.swift` |
| uruchomienie procesu Windows | `Boreal/ProcessModels.swift`, `Boreal/WindowsProcessRunner.swift` |
| profile konkretnych gier | `Boreal/GameGraphicsProfiles.swift` |
| lokalny wrapper legacy | `Boreal/GraphicsComponents/BorealLegacyGraphics/` |
| przykład manifestu runtime | `Tools/RuntimeBuilder/runtime.example.json` |

## 16. Ostateczny werdykt

Integracja wyboru runtime, prefixu, DirectX i backendu jest w kodzie zaprojektowana jako spójny, capability-aware pipeline. Najważniejsza ścieżka — wybór zgodnego runtime, przygotowanie prefixu, aktywacja DLL, registry overrides i uruchomienie przez `LaunchPlan` — jest obecna i wzajemnie połączona.

Najsilniejszy poziom potwierdzenia dotyczy GPTK/D3DMetal i DXMT, ponieważ te ścieżki mają rzeczywisty probe D3D11. DXVK i VKD3D są poprawnie włączone w model, resolver, instalację komponentów i aktywację prefixu, ale ich obecna walidacja pozostaje deklaratywno-artefaktowa: system sprawdza capabilities i pliki, lecz standardowo nie potwierdza jeszcze urządzenia Vulkan ani prezentacji klatki.

To rozróżnienie powinno być zachowane w diagnostyce i w UI: „backend dostępny” oznacza obecnie różny poziom dowodu zależnie od backendu.

Z pełnej listy rekomendacji z analizy pozostają do wykonania cztery odrębne prace: uogólnienie probe na DX9/DX10/DX11/DX12, rzeczywiste Vulkan device/present verification dla DXVK/VKD3D, obserwator DLL/backendu załadowanego przez proces gry oraz trwały model dowodów i historii sukcesów per gra. Obecne flagi DXVK/VKD3D nadal opisują głównie wykryte capabilities i artefakty, nie dowód działania na adapterze hosta. Zmiany w tym wdrożeniu naprawiają PE imports/delay imports, ograniczają overrides, weryfikują integralność plików komponentów i transakcyjnie zabezpieczają modyfikacje prefixu/registry; nie oznaczają zamknięcia tych pozostałych luk.
