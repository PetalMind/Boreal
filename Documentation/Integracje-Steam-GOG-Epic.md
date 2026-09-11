# Dokumentacja integracji Boreal z Steam, GOG.com i Epic Games Store

**Stan dokumentu:** 2026-09-11
**Zakres:** aktualny kod aplikacji macOS Boreal, lokalne helpery CLI, lokalne dane użytkownika, synchronizacja bibliotek, instalacja, utrzymanie plików i uruchamianie gier.
**Źródło prawdy:** implementacja w katalogu `Boreal/`; istniejące dokumenty etapowe są materiałem uzupełniającym.

Ten dokument opisuje rzeczywisty kontrakt integracji. Nie zakłada funkcji, których provider ani Boreal nie implementują. W szczególności nie należy traktować trzech sklepów jako jednego identycznego API: Steam pozostaje klientem zarządzającym własną instalacją, Epic korzysta z Legendary, a GOG z `heroic-gogdl`.

## 1. Streszczenie architektury

Boreal jest aplikacją lokalną. Nie ma osobnego serwera Boreal, który przechowywałby konta lub wykonywał instalacje zdalnie. Orkiestracja znajduje się w `BorealStore`, a operacje providerowe są przekazywane do usług i adapterów złożonych w `BorealServices`.

```text
SwiftUI / AppKit
        │
        ▼
BorealStore (@MainActor)
        │  stan UI, synchronizacja, lifecycle instalacji i launchu
        ▼
BorealServices
        │
        ├── SteamLibraryService       lokalny macOS Steam + publiczne API Steam
        ├── SteamWindowsService       SteamSetup.exe + klient Windows w Wine
        ├── LegendaryEpicService      helper Legendary i dane Epic
        ├── GOGService                 helper heroic-gogdl i dane GOG
        ├── GameStoreProviderRegistry  wspólny punkt wyboru adaptera
        ├── InstallationService        delegowanie install/update/verify/uninstall
        ├── RuntimeManager             wybór i walidacja Wine/GPTK
        ├── EnvironmentManager         prefixy, konfiguracja i środowiska
        ├── LaunchCoordinator           bezpieczny plan i start procesu
        └── WindowsProcessRunner       Wine, wineserver, sesja i zatrzymanie
```

Najważniejsze pliki:

| Obszar | Implementacja |
| --- | --- |
| Wspólny kontrakt providerów | [`GameStoreProvider.swift`](../Boreal/GameStoreProvider.swift) |
| Model biblioteki i stany operacji | [`Models.swift`](../Boreal/Models.swift) |
| Trwałe rekordy instalacji i układ danych | [`BorealStorage.swift`](../Boreal/BorealStorage.swift) |
| Składanie usług | [`BorealServices.swift`](../Boreal/BorealServices.swift) |
| Orkiestracja aplikacji | [`BorealStore.swift`](../Boreal/BorealStore.swift) |
| Integracja lokalnego Steam | [`SteamLibraryService.swift`](../Boreal/SteamLibraryService.swift) |
| Steam dla Windows | [`SteamWindowsService.swift`](../Boreal/SteamWindowsService.swift) |
| Epic przez Legendary | [`LegendaryEpicService.swift`](../Boreal/LegendaryEpicService.swift) |
| GOG przez heroic-gogdl | [`GOGService.swift`](../Boreal/GOGService.swift) |
| Wspólna instalacja/utrzymanie | [`ArchitectureServices.swift`](../Boreal/ArchitectureServices.swift) |
| UI kont i logowania | [`AccountsView.swift`](../Boreal/AccountsView.swift) |
| UI szczegółów gry i akcji | [`StoreGameDetailView.swift`](../Boreal/StoreGameDetailView.swift) |

## 2. Model danych i tożsamość gry

### 2.1. Provider i zewnętrzny identyfikator

W kodzie provider jest jednym z trzech enumów:

```swift
enum GameLibraryProvider: String {
    case steam = "Steam"
    case epic = "Epic Games"
    case gog = "GOG"
}
```

Gra jest identyfikowana przez parę:

```text
provider + externalID
```

Nie wolno łączyć rekordów wyłącznie po nazwie. Nazwy mogą się różnić między sklepami, mogą zawierać edycję, promocję albo lokalizację językową. `StoreReference` przechowuje oba pola razem:

```text
StoreReference {
    provider: Steam | Epic Games | GOG
    externalID: identyfikator sklepu
}
```

Przykłady:

| Provider | `externalID` |
| --- | --- |
| Steam | numeryczny AppID, np. `475150` |
| Epic | `app_name` z Legendary, zwykle identyfikator alfanumeryczny |
| GOG | numeryczny identyfikator release, np. `1196955511` |

### 2.2. Rozdzielenie rekordów

`StoreLibraryGame` jest rekordem biblioteki sklepowej. Zawiera ownership/metadata oraz most do lokalnej instalacji:

- `provider`, `externalID`, `name`;
- opis, twórcę i media;
- ocenę sklepową, jeśli provider ją zwróci;
- deklarowane platformy (`supportsWindows`, `supportsNativeMacOS`);
- `isInstalled`, `installPath`, `installedPlatform`, `storageBytes`;
- szacunek rozmiaru i zgodność ProtonDB, jeśli są dostępne;
- lokalnie zmierzony czas i sesje Boreal.

`GameInstallation` jest kanonicznym rekordem instalacji. Zawiera:

- `gameID` oraz opcjonalny `StoreReference`;
- `InstallationLocation` (`managed(relativePath:)` albo `external(path:)`);
- platformę instalacji (`windows` albo `nativeMacOS`);
- powiązane `environmentID`;
- wykryte pliki wykonywalne i wybrany plik główny;
- rozmiar i `InstallationState`.

`WindowsApplication` opisuje uruchamialny element w Boreal, czyli konkretny executable, środowisko i stan procesu. Dla Epic/GOG jest to zwykle gra powiązana z własnym prefixem. Dla Windows Steam osobny rekord hosta opisuje klienta Steam, a rekord gry wskazuje na ten sam klient i AppID.

### 2.3. Stany instalacji i procesu

Stan plików i stan procesu są niezależne:

```text
InstallationState:
unknown → installing → installed
                    ├→ missing
                    └→ broken
uninstalled

ApplicationStatus / sesja:
ready → preparing → starting → running → ready
                                      └→ needsAttention
unavailable
```

Usunięcie konta sklepowego nie oznacza odinstalowania plików. Odinstalowanie gry nie oznacza odebrania jej z konta sklepowego.

## 3. Macierz obsługiwanych możliwości

Macierz wynika z `GameStoreProviderCapabilities` i zachowania UI. Brak capability oznacza brak obsługi danej operacji przez adapter, a nie pustą akcję udającą sukces.

| Możliwość | Steam | Epic Games | GOG |
| --- | :---: | :---: | :---: |
| Import biblioteki | Tak | Tak | Tak |
| Metadata w trakcie importu | Steam cache + Store API | Legendary JSON | Galaxy Library + GamesDB |
| Osobne `details` po imporcie | Tak | Nie jako osobna capability; dane są w `library()` | Nie jako osobna capability; dane są w `library()` |
| Szacunek rozmiaru | Tak, z wymagań sklepu | Tak, z manifestu | Tak, z manifestu |
| Bezpośrednia instalacja przez Boreal | Nie | Tak | Tak |
| Instalacja przez zarządzanego klienta | Steam client | Nie | Nie |
| Aktualizacja | Steam client | Tak, Legendary | Tak, `gogdl update` |
| Weryfikacja plików | Steam client | Tak, Legendary `verify` | Tak, `gogdl repair` |
| Odinstalowanie przez adapter | Nie; `steam://uninstall` | Tak, Legendary | Nie przez helper; przeniesienie do Trash przez Boreal |
| Plan uruchomienia | Nie dla bezpośredniego executable; AppID + Steam client | Tak | Tak |
| Własne środowisko Wine/GPTK gry | Tylko dla importu Windows poza wspólnym Steam clientem; standardowo wspólny host | Tak | Tak |
| Natywna aplikacja macOS | Tak, przez lokalny Steam | Katalog może raportować Mac, ale ścieżka Boreal jest Windows | Tak, jeśli release zawiera `.app` |

W kodzie adapter Steam reklamuje wyłącznie:

```text
library, details, sizeEstimate, clientManagedInstall
```

Adaptery Epic i GOG reklamują:

```text
library, sizeEstimate, directInstall, update, verify, uninstall, launchPlan
```

To rozdzielenie jest celowe. Steam nie może zostać przypadkowo przepchnięty przez wspólny mechanizm direct install/verify/uninstall, ponieważ Steam client posiada własne depot permissions, DRM, DLC, Steam Guard, aktualizacje i launch options.

## 4. Lokalizacja danych i komponentów

Domyślny katalog aplikacji to:

```text
~/Library/Application Support/Boreal/
```

Układ danych używany przez aplikację:

```text
Boreal/
├── Library/
│   ├── library.json       kanoniczna biblioteka i instalacje
│   ├── favorites.json
│   ├── sessions.json       sesje i czas zmierzony przez Boreal
│   └── downloads.json      wznowienie i stan operacji download
├── State/
│   └── app-state.json
├── Environments/<uuid>/
│   ├── environment.json
│   ├── prefix/
│   ├── Logs/
│   └── pliki stanu prefixu i backendu
├── Runtimes/<runtime-id>/
├── Games/
│   ├── Epic/
│   └── GOG/
├── Accounts/
│   ├── Epic/
│   └── GOG/
├── Tools/
│   ├── Legendary/0.21.0/
│   └── GOGDL/1.3.0/
└── Installers/Steam/
    └── SteamSetup.exe
```

Katalog bazowy gier może zostać zmieniony w Settings → Storage. Domyślnie jest to `~/Library/Application Support/Boreal/Games`, a podkatalog providerowy jest wyznaczany następująco:

```text
Games/Epic
Games/GOG
Games/Steam       tylko nazwa logiczna; Windows Steam wybiera faktyczną bibliotekę w swoim kliencie
```

Steam dla Windows faktycznie przechowuje pliki tam, gdzie użytkownik wybierze bibliotekę w Windows Steam, wewnątrz wspólnego prefixu. `Games/Steam` nie jest mechanizmem instalacji Windows Steam.

### 4.1. Izolacja konfiguracji helperów

Epic:

```text
Tools/Legendary/0.21.0/legendary
Accounts/Epic/
└── user.json
```

Każde uruchomienie helpera dostaje:

```text
LEGENDARY_CONFIG_PATH=<Application Support>/Boreal/Accounts/Epic
```

GOG:

```text
Tools/GOGDL/1.3.0/gogdl
Accounts/GOG/
├── auth.json
└── gogdl/
```

Każde uruchomienie helpera dostaje:

```text
GOGDL_CONFIG_PATH=<Application Support>/Boreal/Accounts/GOG/gogdl
```

oraz jawny argument:

```text
--auth-config-path <Application Support>/Boreal/Accounts/GOG/auth.json
```

Dzięki temu Boreal nie korzysta przypadkiem z globalnej konfiguracji Legendary lub GOG z innej instalacji launchera.

## 5. Instalacja helperów i model zaufania

Epic i GOG nie są wbudowane jako kod źródłowy w target aplikacji. Boreal pobiera gotowy helper po jawnej akcji użytkownika, sprawdza SHA-256, zapisuje plik tymczasowy, nadaje mu prawo wykonania i dopiero wtedy przenosi go na ścieżkę docelową.

### 5.1. Legendary

**Projekt:** [legendary-gl/legendary](https://github.com/legendary-gl/legendary)
**Wersja używana przez kod:** `0.21.0`
**Licencja deklarowana w UI/dokumentacji:** GPL-3.0

| Architektura macOS | Artefakt | SHA-256 |
| --- | --- | --- |
| arm64 | `legendary_macOS_arm64` | `28f5f7d0eb8c029679d4faaa483ec85888af17a9a75977ae9170c21d8ce3428b` |
| x86_64 | `legendary_macOS_x64` | `1352dac6940cdfd4b28ce46dc7ac1f496cd9d49417b5d9d69ce462db27399665` |

Źródła download są zakodowane w [`LegendaryEpicService.swift`](../Boreal/LegendaryEpicService.swift). Jeżeli architektura nie jest `arm64` ani `x86_64`, `prepareSupport()` kończy się `unsupportedArchitecture`.

### 5.2. heroic-gogdl

**Projekt:** [Heroic-Games-Launcher/heroic-gogdl](https://github.com/Heroic-Games-Launcher/heroic-gogdl)
**Wersja używana przez kod:** `1.3.0`
**Licencja deklarowana w UI/dokumentacji:** GPL-3.0

| Architektura macOS | Artefakt | SHA-256 |
| --- | --- | --- |
| arm64 | `gogdl_macos_arm64` | `a85ae9ef80a3e7840b19a416dd4b3c5db2054508c6147315f1c22faa63a29b38` |
| x86_64 | `gogdl_macos_x86_64` | `a3d1e20f09371eb9032a4837eb576b585456728a6f2f420e6877e5cccd4c434d` |

Helper trafia do `Tools/GOGDL/1.3.0/gogdl` i jest wykonywalny dopiero po przejściu kontroli digestu.

### 5.3. SteamSetup.exe

Windows Steam nie korzysta z helpera CLI Boreal. `SteamWindowsService` pobiera oficjalny bootstrapper z:

```text
https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe
```

Plik jest zapisany jako:

```text
<Application Support>/Boreal/Installers/Steam/SteamSetup.exe
```

Aktualny kontrakt walidacji SteamSetup nie zawiera przypiętego SHA-256. Kod sprawdza:

- status HTTP `200`;
- końcowy URL nadal ma schemat `https`;
- host końcowego URL jest taki sam jak host URL źródłowego;
- rozmiar jest większy niż 1 MB;
- pierwsze dwa bajty to sygnatura PE `MZ`.

Jeżeli warunek nie przejdzie, instalator nie jest uruchamiany.

## 6. Łączenie kont

### 6.1. Steam

Steam nie ma formularza logowania w Boreal. W Accounts → Steam akcja **Open Steam to sign in** otwiera:

```text
steam://openmain
```

Następnie **Refresh Library** odczytuje konto już zalogowane w lokalnej aplikacji Steam dla macOS. Boreal:

- nie prosi o hasło Steam;
- nie odczytuje ani nie kopiuje hasła, Steam Guard, cookie ani tokenu sesji;
- nie przenosi logowania z macOS Steam do Windows Steam;
- nie używa macOS Steam jako źródła poświadczeń dla Windows Steam.

Logowanie do Steam dla Windows odbywa się osobno w oknie `steam.exe` uruchomionym w zarządzanym prefixie. Użytkownik sam wykonuje tam logowanie i Steam Guard.

### 6.2. Epic Games

Przebieg w Accounts:

1. Użytkownik wybiera **Connect**.
2. Jeśli Legendary nie istnieje, Boreal pobiera i weryfikuje komponent.
3. Boreal otwiera `https://legendary.gl/epiclogin` w domyślnej przeglądarce.
4. Użytkownik loguje się na stronie Epic, w tym wykonuje CAPTCHA/MFA, jeśli Epic tego wymaga.
5. Na stronie wynikowej użytkownik kopiuje wartość `authorizationCode` z JSON-a.
6. Wklejony tekst trafia do `LegendaryEpicService.authenticate(authorizationCode:)`.
7. Boreal normalizuje tekst i uruchamia:

   ```text
   legendary auth --code <one-time authorization code>
   ```

8. Legendary zapisuje swoje dane konta pod `LEGENDARY_CONFIG_PATH`.
9. Boreal przechodzi do `connected` i uruchamia synchronizację biblioteki.

Boreal akceptuje wartość surową, tekst otoczony cudzysłowami albo JSON zawierający `authorizationCode`. Kod jednorazowy nie jest zapisywany przez Boreal do biblioteki ani do ustawień.

### 6.3. GOG.com

Przebieg w Accounts:

1. Użytkownik wybiera **Connect**.
2. Jeśli `gogdl` nie istnieje, Boreal pobiera i weryfikuje komponent.
3. Boreal otwiera URL autoryzacyjny GOG:

   ```text
   https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=client2
   ```

4. Użytkownik loguje się na stronie GOG.
5. Użytkownik wkleja końcowy URL albo kod z wyniku autoryzacji.
6. Boreal wyciąga parametr `code`, wartość JSON `code`/`authorizationCode` albo używa surowego tekstu.
7. Boreal uruchamia:

   ```text
   gogdl --auth-config-path <Accounts/GOG/auth.json> auth --code <one-time code>
   ```

8. `gogdl` zapisuje tokeny do `Accounts/GOG/auth.json`.
9. Boreal ustawia stan `connected` i uruchamia synchronizację biblioteki.

Hasło, CAPTCHA, MFA, cookie i sesja przeglądarki pozostają po stronie GOG. Boreal przekazuje helperowi tylko kod jednorazowy.

### 6.4. Stany kont

Epic i GOG używają osobnych, ale równoległych stanów:

```text
checking
supportNotInstalled
disconnected
preparingSupport
authenticating
connected(displayName: ...)
failed(message)
```

`connected` oznacza, że helper i lokalne poświadczenia są dostępne. Nie jest to gwarancja, że każdy endpoint sklepu odpowie albo że każda gra ma build dla wybranej platformy.

### 6.5. Rozłączanie kont

**Epic:**

- Boreal wywołuje `legendary auth --delete`.
- Wiersze Epic są usuwane z biblioteki Boreal.
- Pobrane pliki gier pozostają na dysku.
- Ownership w Epic nie jest zmieniany.

**GOG:**

- Boreal usuwa lokalny `Accounts/GOG/auth.json`.
- Wiersze GOG są usuwane z biblioteki Boreal, z zachowaniem rekordów ręcznie dodanych jako metadata-only, jeśli takie istnieją.
- Pobrane pliki gier pozostają na dysku.
- Ownership w GOG nie jest zmieniany.

**Steam:** nie ma operacji disconnect w Boreal. Odświeżenie zależy od lokalnego klienta Steam i jego zalogowanego konta.

## 7. Import i synchronizacja bibliotek

Wszystkie synchronizacje są uruchamiane przez `BorealStore.syncLibrary(_:)` i są blokowane, gdy dla innego providerowego importu trwa już synchronizacja. Po udanym imporcie:

1. rekordy są normalizowane;
2. istniejące identyfikatory Boreal są zachowywane po `externalID`;
3. zachowywane są lokalne sesje, czas i dodatkowo zapisane metadata;
4. lista jest sortowana po nazwie;
5. `library.json` jest zapisywany;
6. opcjonalnie ładowana jest kompatybilność ProtonDB dla gier bez natywnego macOS.

Błąd importu ustawia `LibrarySyncState.failed` i prezentuje problem. Kod nie zastępuje wcześniej zapisanej listy pustym wynikiem tylko dlatego, że chwilowo nie działa sieć, token albo helper.

### 7.1. Steam: lokalny klient macOS jako źródło biblioteki

`SteamLibraryService` domyślnie czyta:

```text
~/Library/Application Support/Steam/
```

#### Odczytywane pliki

| Plik/katalog | Znaczenie |
| --- | --- |
| `config/loginusers.vdf` | mapowanie SteamID64 do lokalnych kont |
| `userdata/<account-id>/config/localconfig.vdf` | lokalnie znane AppID, playtime i `LastPlayed` |
| `userdata/<account-id>/config/librarycache/<appid>.json` | cache opisu i skojarzeń developerów |
| `appcache/librarycache/<appid>/library_600x900.jpg` | lokalna okładka portrait |
| `steamapps/libraryfolders.vdf` | dodatkowe biblioteki Steam |
| `steamapps/appmanifest_<appid>.acf` | zainstalowany stan, `SizeOnDisk`, `installdir` |

Importer:

- rozpoznaje zalogowane lokalne katalogi użytkowników;
- łączy dane z wielu użytkowników do jednego AppID;
- bierze kandydatów nie tylko z `localconfig.vdf`, ale także z numerowanych plików cache biblioteki;
- skanuje domyślną i dodatkowe biblioteki wskazane przez `libraryfolders.vdf`;
- uznaje tytuł za zainstalowany dopiero po znalezieniu manifestu `appmanifest_<appid>.acf`;
- wylicza ścieżkę `steamapps/common/<installdir>` i rozmiar;
- nie modyfikuje plików macOS Steam.

#### Wzbogacenie online

Dla każdego AppID importer równolegle próbuje pobrać:

```text
GET https://store.steampowered.com/api/appdetails
    ?appids=<appid>&l=<język systemu>

GET https://store.steampowered.com/appreviews/<appid>
    ?json=1&language=all&purchase_type=all&num_per_page=0
```

Z `appdetails` mapowane są między innymi:

- nazwa, developer/publisher i opis;
- portrait, header i background;
- screenshoty;
- media wideo (`hls_h264`, MP4 albo DASH jako fallback);
- dostępność Windows/macOS;
- wymagania systemowe i wykrywalna informacja o architekturze.

Z `appreviews` wyliczany jest pozytywny procent i liczba recenzji. Jeśli nie ma oceny użytkowników, kod może użyć wyniku Metacritic jako `criticScore`.

Niedostępność API nie kasuje lokalnego importu. W takim przypadku pozostają dane z cache/manifestów, a pola online są puste albo zachowują poprzednią wartość.

#### Wyszukiwanie Steam poza biblioteką

`searchStoreGame(named:)` używa publicznego:

```text
https://store.steampowered.com/api/storesearch/
```

Wynik jest tokenizowany, normalizowany bez wielkości liter i diakrytyki, a dodatki typu DLC/demo/soundtrack są odrzucane, jeśli zapytanie nie prosi o dodatek. Niepewne remisy nie są automatycznie wybierane.

### 7.2. Epic: biblioteka konta przez Legendary

`LegendaryEpicService.loadLibrary()` najpierw sprawdza lokalne `user.json`, a potem uruchamia równolegle:

```text
legendary list --platform Windows --json
legendary list-installed --json --show-dirs
```

`list` dostarcza ownership i katalog dostępnych gier. `list-installed` dostarcza lokalny `install_path` oraz rozmiar, jeśli Legendary go raportuje. Boreal łączy oba wyniki po `app_name`.

Z JSON-a Legendary mapowane są:

- `app_name` → `externalID`;
- `app_title` → nazwa;
- `metadata.developer` albo `metadata.publisher` → developer;
- `longDescription`, `description` albo `shortDescription` → opis;
- `metadata.keyImages` → portrait/header/background;
- pozostałe szerokie obrazy → media;
- `metadata.releaseInfo[].platform` → deklarowane platformy;
- `install_path` → stan i ścieżka instalacji.

Epic nie raportuje ratingu ani trailera w kontrakcie, który Boreal obecnie wykorzystuje. Brak danych pozostaje brakiem danych; Boreal nie tworzy sztucznej oceny ani sztucznego trailera.

Po imporcie `BorealStore` dociąga profil kompatybilności dla gier, które nie mają natywnego macOS, i ponownie sprawdza stan połączenia konta.

### 7.3. GOG: Galaxy Library i GamesDB

`GOGService.loadLibrary()` wykonuje następujący przepływ:

1. `gogdl auth` zwraca lokalne credentials z `auth.json`.
2. Boreal pobiera stronicowaną bibliotekę z:

   ```text
   GET https://galaxy-library.gog.com/users/<userID>/releases
   Authorization: Bearer <accessToken>
   ```

3. Czytane są `items`, `next_page_token`, `external_id`, `platform_id` i `certificate`.
4. Zachowywane są wyłącznie wpisy z `platform_id == "gog"`.
5. Kolejne strony są pobierane do wyczerpania `next_page_token`.
6. Duplikaty `externalID` są usuwane.
7. Dla każdego release pobierane są dane z:

   ```text
   GET https://gamesdb.gog.com/platforms/gog/external_releases/<externalID>
   Authorization: Bearer <accessToken>
   X-GOG-Library-Cert: <certificate, jeśli provider go zwrócił>
   ```

8. Odpowiedź jest mapowana do `StoreLibraryGame`.

GamesDB dostarcza między innymi:

- tytuł i developerów;
- opis;
- `vertical_cover`, logo i background;
- screenshoty;
- `supported_operating_systems`;
- `aggregated_rating` albo `rating` jako wynik krytyków.

Przygotowanie katalogu GOG sprawdza lokalnie, czy istnieje poprawny:

```text
goggame-<externalID>.info
```

Importer obsługuje również zagnieżdżony układ, w którym helper umieścił grę w:

```text
<root>/<externalID>/<tytuł gry>/
```

Wynik jest deduplikowany także dla wariantów promocyjnych z sufiksami `Amazon Prime`, `Amazon Luna` i `Prime Giveaway`, gdy istnieje odpowiadający im tytuł bazowy.

## 8. Instalacja gier

### 8.1. Wspólny przepływ Epic/GOG

W szczegółach gry przycisk **Install** uruchamia `BorealStore.installStoreGame`. Provider i platforma są wybierane przez kod, a miejsce docelowe jest sprawdzane przed utworzeniem operacji:

```text
1. sprawdź, czy dysk/katalog docelowy jest dostępny i zapisywalny;
2. wybierz platformę instalacji;
3. utwórz StoreDownloadRecord;
4. oznacz GameInstallation jako installing;
5. uruchom adapter providerowy;
6. odbierz progress ze stdout/stderr helpera;
7. po sukcesie odnajdź instalację;
8. zapisz GameInstallation jako installed;
9. odśwież bibliotekę providerową.
```

Operacje Epic/GOG są zapisywane pod kluczem:

```text
<provider.rawValue>::<externalID>
```

### 8.2. Platforma instalacji

Aktualny wybór w `BorealStore.preferredStoreInstallationPlatform(for:)` jest następujący:

| Provider | Wybór platformy |
| --- | --- |
| Steam | native macOS, jeśli gra deklaruje macOS; w przeciwnym razie Windows przez Steam client |
| Epic | zawsze Windows dla ścieżki providerowej Boreal |
| GOG | native macOS, jeśli metadata deklarują macOS; w przeciwnym razie Windows |

Ważne: Epic może zwrócić w katalogu informację o platformie Mac, lecz aktualna ścieżka `prepareStoreGame` i `launchPlan` dla Epic jest kontraktem Windows + Wine/GPTK. Sama obecność flagi `supportsNativeMacOS` w metadanych nie tworzy natywnego instalatora Epic w Boreal.

### 8.3. Epic: instalacja i operacje helpera

Domyślna ścieżka to:

```text
<gameInstallationBaseRoot>/Epic
```

Boreal uruchamia:

```text
legendary -y install <appName> \
  --platform Windows \
  --base-path <destinationRoot> \
  --skip-dlcs
```

Bezpośredni serwis obsługuje też wariant `Mac`, ale orchestrator Boreal dla Epic wybiera Windows.

Przed instalacją można pobrać rozmiar:

```text
legendary info <appName> --platform Windows --json
```

Boreal czyta z `manifest`:

- `download_size`;
- `disk_size`;
- `build_id`;
- możliwą architekturę executable.

Po zakończeniu instalacji Legendary pozostaje źródłem ścieżki instalacji. `list-installed --json --show-dirs` jest używane przy imporcie, relokacji i potwierdzaniu stanu.

### 8.4. GOG: instalacja Windows i native macOS

Domyślna ścieżka to:

```text
<gameInstallationBaseRoot>/GOG/<externalID>
```

Przed pobraniem `gogdl info` może dostarczyć rozmiary:

```text
gogdl info <externalID> \
  --platform windows|osx \
  --lang en-US \
  --skip-dlcs
```

Boreal używa:

- `download_size` jako rozmiaru pobierania;
- `disk_size` jako rozmiaru instalacji;
- `buildId` jako identyfikatora buildu;
- manifestu do inferencji architektury.

Instalacja:

```text
gogdl download <externalID> \
  --path <destinationRoot>/<externalID> \
  --platform windows|osx \
  --skip-dlcs
```

Po zakończeniu kod wymaga wykrycia instalacji:

- Windows: plik `goggame-<externalID>.info` w katalogu gry albo w jego zagnieżdżonym podkatalogu;
- macOS: poprawny pakiet `.app` z `Contents/MacOS`.

Jeśli download zakończy się kodem 0, ale taki artefakt nie istnieje, operacja kończy się `installationIncomplete`, a gra nie jest oznaczana jako poprawnie zainstalowana.

### 8.5. Steam native macOS

Natywna instalacja i uruchamianie są delegowane do lokalnego klienta Steam:

```text
steam://install/<AppID>
steam://rungameid/<AppID>
steam://uninstall/<AppID>
```

Boreal nie kopiuje plików Steam i nie zarządza depotami. Jeżeli gra jest już zainstalowana w lokalnej bibliotece, importer potrafi pokazać jej manifest i ścieżkę, a akcja Play używa `steam://rungameid` albo otwiera znalezioną natywną aplikację `.app` w przypadku rekordu z platformą `nativeMacOS`.

### 8.6. Steam dla Windows

Windows Steam jest osobnym, zarządzanym przypadkiem.

#### Pierwsze przygotowanie

1. `SteamWindowsService` pobiera i waliduje `SteamSetup.exe`.
2. `InstallerService` wybiera runtime mogący obsłużyć zarówno bootstrapper x86, jak i przyszłe gry x86/x86_64.
3. Powstaje środowisko o celu `.sharedStore`.
4. Instalator jest uruchamiany w prefixie.
5. Boreal wykrywa `steam.exe` w:

   ```text
   drive_c/Program Files (x86)/Steam/steam.exe
   drive_c/Program Files/Steam/steam.exe
   ```

6. Powstaje rekord hosta **Steam for Windows**.
7. Klient Steam jest uruchamiany z `-silent`.
8. Boreal przekazuje klientowi akcję:

   ```text
   steam.exe steam://install/<AppID>
   ```

9. Stan operacji przechodzi w `awaitingProvider`.

Boreal wyświetla wtedy komunikat: użytkownik ma zalogować się w Windows Steam, dokończyć instalację i odświeżyć status.

#### Współdzielenie prefixu

Jeden host **Steam for Windows** i jego prefix może obsługiwać wiele gier Steam. Kolejna gra nie instaluje drugiej kopii klienta Steam. Konfiguracje na poziomie prefixu, takie jak architektura i główny renderer, pochodzą z hosta.

Argumenty launchu, ustawienia overlay, mapowanie kontrolera i diagnostyka procesu pozostają właściwościami profilu gry.

#### Potwierdzanie instalacji

Po kliknięciu **Refresh Windows Steam Status** Boreal szuka:

```text
appmanifest_<AppID>.acf
```

w bibliotekach Steam wewnątrz prefixu. Dopiero wtedy czyta `AppState.installdir`, sprawdza katalog `steamapps/common/<installdir>` i aktualizuje rekord gry jako zainstalowany.

Otwarcie klienta Steam albo samo uruchomienie instalatora nie jest dowodem, że gra została pobrana.

## 9. Postęp pobierania, anulowanie i wznowienie

`StoreGameOperationProgress` może zawierać:

- fazę: `preparing`, `downloading`, `installing`, `verifying`;
- procent;
- przesłane i całkowite bajty;
- prędkość sieciową i dyskową;
- ETA;
- skrócony surowy fragment wyjścia helpera.

Parser obsługuje m.in.:

```text
37.5%
progress: 37.5
progress: 25.00 536870912/2147483648
1234 / 5678 MB
```

Parser buforuje niepełne linie stdout/stderr, ponieważ callback `readabilityHandler` może otrzymać fragment jednej linii.

### 9.1. Epic i GOG

Postęp jest pobierany z wyjścia procesu helpera. `StoreProgressAccumulator` scala osobne linie, w tym rozdzielone komunikaty GOG `Progress`, `Download` i `Disk`. Aktywność dyskowa GOG pozostaje częścią pipeline’u download/dekompresji, a nie fałszywym przejściem do niezależnej operacji.

Przycisk Pause/Cancel:

- anuluje proces helpera;
- zachowuje pobrane pliki;
- zapisuje `StoreDownloadRecord.status = paused`;
- zachowuje ostatni postęp i próbki prędkości;
- pozwala uruchomić **Resume** z zapisanej ścieżki i platformy.

Po ponownym uruchomieniu Boreal operacje, które były `downloading`, są odzyskiwane jako wstrzymane. Nie są automatycznie deklarowane jako zakończone.

### 9.2. Steam Windows

Steam Windows nie jest objęty tym samym bezpośrednim parserem pobierania. Boreal pokazuje stan `awaitingProvider`, ponieważ właściwy procent, depot progress, aktualizacje i błędy instalacji należą do Windows Steam UI.

## 10. Przygotowanie środowiska i uruchamianie

### 10.1. Epic: plan zwracany przez Legendary

Po zakończeniu instalacji przycisk **Prepare to Play** wykonuje w uproszczeniu:

```text
1. znajdź katalog instalacji;
2. przeanalizuj executable i wymagane architektury;
3. wybierz Wine albo GPTK oraz backend graficzny;
4. utwórz izolowany ManagedBorealEnvironment;
5. zainicjalizuj prefix i zależności;
6. zapytaj Legendary o świeży plan launchu;
7. zweryfikuj plan;
8. utwórz WindowsApplication;
9. zapisz rekord i udostępnij Play.
```

Zapytanie do Legendary:

```text
legendary launch <appName> \
  --json \
  --wine <managed runtime>/wine \
  --wine-prefix <managed environment>/prefix
```

Z JSON-a czytane są między innymi:

- `game_parameters`;
- `game_executable`;
- `game_directory`;
- `egl_parameters`;
- `launch_command`;
- `working_directory`;
- `user_parameters`;
- `environment`;
- `pre_launch_command`.

Walidacja odrzuca plan, gdy:

- `pre_launch_command` nie jest pusty — Boreal nie wykonuje arbitralnych poleceń shellowych helpera;
- pierwszy element `launch_command` nie jest dokładnie wybranym executable runtime;
- executable nie istnieje albo wychodzi poza katalog instalacji gry;
- working directory wychodzi poza katalog instalacji gry.

Przed przekazaniem planu do Wine Boreal usuwa z environment helpera `WINEPREFIX` i `PATH`, a następnie wstrzykuje własne zarządzane wartości. Provider nie może przejąć kontroli nad prefixem ani runtime’em Boreal.

Plan jest odświeżany przy launchu. Parametry Epic mogą się zmieniać lub wygasać, więc nie są traktowane jako wieczna, ręcznie zapisana komenda.

### 10.2. GOG: `goggame-<id>.info` jako źródło play task

GOG nie zwraca w aktualnej implementacji osobnego JSON planu startowego. Boreal czyta plik:

```text
<installation directory>/goggame-<externalID>.info
```

Wybierany jest:

1. pierwszy `playTask` z `isPrimary == true`, który nie jest `URLTask`;
2. w przeciwnym razie pierwszy task niebędący `URLTask`.

Z taska pobierane są:

- `path` executable;
- opcjonalny `workingDir`;
- `arguments` jako tablica albo prosty command line string.

Ścieżki są normalizowane z separatorów Windows i muszą pozostać dziećmi katalogu instalacji. Odrzucane są ścieżki absolutne, ścieżki z drive letter, traversal i working directory poza instalacją.

Następnie `GOGService` tworzy `WindowsLaunchPlan`, a Boreal przekazuje executable do wybranego runtime’u Wine/GPTK i prefixu.

### 10.3. Steam Windows: klient i AppID jako tożsamość launchu

Gra Steam Windows nie jest uruchamiana przez wykryty bezpośrednio `.exe` gry. Plan ma postać:

```text
executable: <prefix>/drive_c/Program Files (x86)/Steam/steam.exe
arguments:  -applaunch <AppID>
workingDirectory: katalog steam.exe
sessionScope: processGroup
```

Steam wybiera właściwy executable gry, parametry, DLC, Steamworks i DRM. Boreal może przechowywać wykryty executable jako wskazówkę do identyfikacji procesu, ale nie zastępuje nim `steam.exe` w komendzie uruchomienia.

### 10.4. Natywne uruchamianie macOS

Jeśli rekord ma platformę `nativeMacOS`, Boreal otwiera znaleziony pakiet `.app` przez `NSWorkspace`. W przypadku Steam native może użyć też `steam://rungameid/<AppID>`. Natywna aplikacja nie przechodzi przez Wine, GPTK ani `WindowsProcessRunner`.

## 11. Runtime, prefix i grafika

### 11.1. Epic/GOG

Gry Epic i GOG instalowane jako Windows otrzymują osobne środowisko Boreal. Podczas przygotowania środowiska kod:

- analizuje architekturę plików PE;
- buduje `RuntimeSelectionRequest`;
- respektuje wymuszony engine/providerowy profil gry, jeśli istnieje;
- rozwiązuje DirectX API i backend graficzny;
- ustawia tryb prefixu (`win32`, `win64` albo nowoczesny WoW64);
- instaluje wymagane zależności;
- dopiero potem zapisuje gotowe środowisko.

W UI dla Epic/GOG użytkownik może wybrać rekomendowany runtime, Game Porting Toolkit (D3DMetal) albo Wine (WineD3D), o ile runtime i jego capability są dostępne.

### 11.2. Windows Steam

Steam Windows używa wspólnego środowiska hosta. Dlatego ustawienia prefix-level nie mogą być dowolnie zmieniane przez każdą grę z osobna. Wspólne są między innymi:

- architektura i tryb prefixu;
- wersja Windows;
- główny renderer;
- zależności środowiska;
- ustawienia kontrolera zależne od prefixu.

Ustawienia per gra, które mogą pozostać lokalne dla launchu, obejmują argumenty, overlay, diagnostykę i wybór procesu monitorowanego.

### 11.3. Wbudowane profile provider + externalID

`GameGraphicsProfiles` zawiera profile związane z konkretną parą provider/ID, a nie globalne reguły po samej nazwie gry. Przykłady znajdujące się w kodzie:

| Provider / ID | Reguła |
| --- | --- |
| GOG `1887281589` | GPTK + D3DMetal, DirectX 11, wyłączenie `Rewired_WindowsGamingInput` |
| Steam `1466060` | GPTK + D3DMetal, DirectX 11, ta sama korekta WinRT |
| Steam `1593500` | preferowany DXMT i scoped `DXMT_CONFIG` |
| Steam `1547000` | DirectX 12 i `-dx12` |
| Steam `200710` | wymuszony WineD3D dla DirectX 9 |
| GOG `1446463013` | DX11 wymaga `Darksiders2.wsl`; dostępny także DX9 |
| GOG `1787707874` | wymuszony WineD3D z `WINED3D_RENDERER=gl` |

`GOGService` ma także providerowy fallback dla znanych z kodu identyfikatorów:

- GOG `1196955511` (Titan Quest): przy Wine wybiera `/dx9` i `WINED3D_RENDERER=vulkan` zamiast primary `/dx11`;
- GOG `2022341186`: GPTK preferuje `-dx10`, a Wine `-dx9` i `WINED3D_RENDERER=vulkan`.

Te reguły są wyjątkami jawnie związanymi z ID. Nie wolno uogólniać ich na wszystkie gry GOG, Epic albo Steam.

## 12. Aktualizacja, weryfikacja i odinstalowanie

### 12.1. Epic

Akcje są widoczne tylko dla zainstalowanej gry i tylko wtedy, gdy adapter ma odpowiednią capability.

**Aktualizacja:**

```text
legendary -y install <appName> --update-only --skip-dlcs
```

**Weryfikacja:**

```text
legendary verify <appName>
```

**Odinstalowanie:**

```text
legendary -y uninstall <appName>
```

Jeśli gra ma powiązane środowisko Boreal, środowisko i rekord aplikacji są usuwane w ramach tej operacji, a następnie Legendary czyści własny rekord instalacji. Ownership w Epic pozostaje.

### 12.2. GOG

Aktualizacja i weryfikacja wymagają istniejącej ścieżki instalacji.

**Aktualizacja:**

```text
gogdl update <externalID> \
  --path <installationPath> \
  --platform windows|osx \
  --skip-dlcs
```

**Weryfikacja/repair:**

```text
gogdl repair <externalID> \
  --path <installationPath> \
  --platform windows|osx \
  --skip-dlcs
```

Jeżeli offline installer ma bazę hashy, ale nie ma jeszcze lokalnego manifestu `gogdl`, `repair` może zwrócić `No manifest stored locally`. Boreal przechodzi wtedy do kontrolowanego `download` na tej samej ścieżce, aby przyjąć istniejącą instalację i odbudować manifest.

Odinstalowanie GOG jest operacją systemową Boreal:

1. jeśli istnieje środowisko, Boreal usuwa powiązaną aplikację i environment;
2. sprawdza, że rekord aplikacji zniknął;
3. przenosi katalog instalacji do macOS Trash przez `FileManager.trashItem`;
4. czyści `isInstalled`, `installPath`, platformę i rozmiar;
5. oznacza `GameInstallation` jako `uninstalled`;
6. odświeża bibliotekę GOG.

Pliki są przenoszone do Trash, a nie bezwarunkowo usuwane rekurencyjnie.

### 12.3. Steam

Steam nie wystawia w Boreal bezpośrednich update/verify/uninstall capabilities. Akcje są delegowane do klienta:

```text
steam://uninstall/<AppID>
```

Steam pozostaje właścicielem usuwania plików, aktualizacji, weryfikacji, DLC i launch options. Boreal nie oznacza gry jako odinstalowanej na podstawie samego otwarcia ekranu klienta; stan importuje ponownie z manifestów Steam.

## 13. Ręczne wskazanie istniejącej instalacji

Jeżeli gra jest już pobrana poza bieżącym przepływem Boreal, akcja **Locate Installed Game** pozwala wskazać:

- dla native macOS: pakiet `.app`, gdy provider i metadata pozwalają na native macOS;
- dla Windows: główny plik `.exe`.

Boreal odrzuca pliki wyglądające jak:

- installer;
- updater;
- uninstaller;
- helper albo crash handler;
- plik nieistniejący albo niebędący regularnym executable.

Dla istniejącej instalacji Windows Boreal:

1. analizuje wybrany executable i katalog gry;
2. wybiera kompatybilny runtime;
3. tworzy nowy zarządzany environment;
4. nie kopiuje i nie nadpisuje oryginalnego executable;
5. zapisuje `installerPath = "existing-installation"`;
6. zapisuje instalację przez `GameInstallation`;
7. wykrywa dodatkowe executable jako Game Actions.

Jeśli w katalogu istnieje `goggame-<id>.info`, instalacja może zostać rozpoznana jako GOG i powiązana z odpowiednim `externalID`, również podczas uruchamiania Boreal i normalizacji starych rekordów.

## 14. Reguły bezpieczeństwa

### 14.1. Poświadczenia

- Steam macOS: odczyt lokalnej biblioteki, bez kopiowania credentials.
- Steam Windows: login i Steam Guard tylko w Windows Steam.
- Epic: Boreal przekazuje jednorazowy `authorizationCode`; tokeny zapisuje helper w izolowanej konfiguracji.
- GOG: Boreal przekazuje jednorazowy kod; tokeny są w `Accounts/GOG/auth.json` zarządzanym przez helper.
- Disconnect usuwa lokalne credentials, ale nie pliki gier.

### 14.2. Integralność komponentów

- Legendary i `gogdl` mają przypięte wersje oraz SHA-256 per architektura.
- Plik z niezgodnym digestem nie zastępuje istniejącego helpera.
- SteamSetup ma walidację połączenia, hosta, rozmiaru i sygnatury `MZ`, ale nie ma obecnie przypiętego digestu.

### 14.3. Walidacja identyfikatorów i ścieżek

- Epic `appName` dopuszcza tylko znaki alfanumeryczne, `_` i `-` w operacjach wymagających bezpiecznego ID.
- GOG `externalID` musi być niepustym ciągiem cyfr.
- GOG `path`, `workingDir` i executable są rozwiązywane przez symlinki i muszą zostać wewnątrz katalogu instalacji.
- Epic executable i working directory muszą zostać wewnątrz `gameDirectory` zwróconego przez Legendary.
- `WINEPREFIX` i `PATH` są kontrolowane przez Boreal, nie przez wartości z helpera.
- Niepusty `pre_launch_command` Epic jest odrzucany, a nie wykonywany po cichu.
- Steam AppID w Windows jest używany przez `appmanifest_<AppID>.acf` i plan `-applaunch`, a nie jako dowolny fragment ścieżki.

### 14.4. Brak fałszywych stanów

- otwarcie Steam nie oznacza ukończonej instalacji gry;
- kod 0 helpera GOG nie wystarcza bez znalezienia manifestu lub `.app`;
- brak metadata nie jest zamieniany na sztuczną ocenę, trailer albo kompatybilność;
- rating sklepu i ProtonDB są przechowywane jako różne pojęcia;
- instalacja i status procesu są przechowywane osobno.

## 15. Obsługa błędów i diagnostyka

### 15.1. Najczęstsze stany

| Objaw | Znaczenie | Działanie użytkownika |
| --- | --- | --- |
| `supportNotInstalled` | Helper Epic/GOG nie został jeszcze przygotowany | Kliknij Connect i pozwól pobrać komponent |
| `disconnected` | Brak lokalnych credentials | Zaloguj się przez providerowy flow |
| `invalidAuthorizationCode` | Wklejono pusty lub nieprawidłowy kod | Skopiuj końcowy kod/JSON ponownie |
| `notAuthenticated` | Token helpera nie działa lub został usunięty | Połącz konto ponownie |
| `verificationFailed` | Digest pobranego helpera nie pasuje | Nie używaj pliku; ponów po sprawdzeniu sieci/źródła |
| `noBuildsFound` | Provider nie ma buildu dla wybranej platformy | Wybierz inną platformę albo ręcznie dodaj kompatybilną instalację |
| `installationIncomplete` | Download nie utworzył oczekiwanego artefaktu | Sprawdź helper output i ścieżkę instalacji |
| `invalidLaunchPlan` | Manifest/JSON zwrócił niebezpieczny lub niepełny launch | Sprawdź pliki gry i manifest; nie omijaj walidacji |
| `awaitingProvider` Steam | Steam client wymaga loginu albo dokończenia pobierania | Dokończ akcję w Windows Steam, potem odśwież status |

### 15.2. Gdzie szukać danych

```text
Biblioteka:       ~/Library/Application Support/Boreal/Library/library.json
Operacje:         ~/Library/Application Support/Boreal/Library/downloads.json
Środowiska:       ~/Library/Application Support/Boreal/Environments/<uuid>/
Logi środowiska:  ~/Library/Application Support/Boreal/Environments/<uuid>/Logs/
Epic config:      ~/Library/Application Support/Boreal/Accounts/Epic/
GOG config:       ~/Library/Application Support/Boreal/Accounts/GOG/
Legendary:        ~/Library/Application Support/Boreal/Tools/Legendary/0.21.0/
gogdl:            ~/Library/Application Support/Boreal/Tools/GOGDL/1.3.0/
Steam bootstrap:  ~/Library/Application Support/Boreal/Installers/Steam/SteamSetup.exe
```

Dla problemu z biblioteką Steam najpierw sprawdza się lokalny katalog Steam, `loginusers.vdf`, `localconfig.vdf`, `libraryfolders.vdf` i `appmanifest_*.acf`. Dla Epic/GOG najpierw sprawdza się stan helpera, plik credentials, ostatni output procesu i czy provider zwraca poprawny JSON.

Nie należy diagnozować błędu launchu wyłącznie na podstawie tego, że katalog gry istnieje. Plan może zostać odrzucony przez brak executable, niebezpieczną ścieżkę, niezgodny runtime, brak WoW64 albo providerowy profil grafiki.

## 16. Relokacja gier

Zmiana lokalizacji gier w Settings → Storage dotyczy bezpośrednich instalacji Epic i GOG, nie biblioteki Windows Steam wybieranej przez klienta.

**Epic:** Boreal wywołuje:

```text
legendary -y move <appName> <destinationRoot>
legendary list-installed --json --show-dirs
```

**GOG:** Boreal odszukuje kontener `<externalID>`, przenosi strukturę do nowego katalogu i aktualizuje rekord ścieżki. Dla GOG zachowywany jest zagnieżdżony katalog gry, jeśli helper tak go utworzył.

Relokacja jest blokowana, gdy gra działa, environment jest zajęty albo trwa operacja providerowa. Po zmianie aktualizowane są `GameInstallation`, `StoreLibraryGame.installPath`, rozmiar i powiązane `WindowsApplication`.

## 17. Kontrakt rozszerzania integracji

Dodanie nowego providerowego działania powinno przebiegać w tej kolejności:

1. zdefiniować źródło prawdy dla ownership, metadata, instalacji i launchu;
2. dodać lub rozszerzyć protokół usług providerowych;
3. dodać adapter `GameStoreProvider`;
4. przypisać wyłącznie rzeczywiście obsługiwane `GameStoreProviderCapabilities`;
5. zarejestrować adapter w `BorealServices`;
6. dodać bezpieczne mapowanie ID, ścieżek i środowiska;
7. rozdzielić native macOS, Windows przez Wine/GPTK i client-managed path;
8. podłączyć synchronizację oraz zachowanie istniejących rekordów;
9. pokazać akcję w UI dopiero na podstawie capability i realnego stanu instalacji;
10. opisać błędy i granicę weryfikacji.

Nie należy:

- implementować Steam przez SteamCMD, jeśli akcja należy do klienta Steam;
- kopiować poświadczeń między providerami;
- wykonywać `pre_launch_command` z zewnętrznego JSON-a;
- pozwalać helperowi na nadpisanie `WINEPREFIX` albo `PATH`;
- uznawać tytułu za zainstalowany bez providerowego manifestu/rekordu;
- dodawać ratingu, media albo kompatybilności tylko dlatego, że inne źródło ma podobne dane;
- opierać deduplikacji na nazwie zamiast `provider + externalID`;
- reklamować capabilities, których adapter nie potrafi wykonać.

## 18. Granice aktualnego kontraktu

Dokumentacja opisuje integrację zaimplementowaną w kodzie. Nie oznacza to, że każda kombinacja konto–gra–runtime została uruchomiona na żywo. Wynik end-to-end nadal zależy od:

- ważności konta i tokenu danego użytkownika;
- dostępności sieci i odpowiedzi providerowych endpointów;
- aktualnego artefaktu helpera i zgodności przypiętego digestu;
- dostępności wybranego runtime’u oraz jego komponentów;
- wymagań DRM, anti-cheat i usług online konkretnej gry;
- kompatybilności konkretnego buildu Windows z Wine/GPTK.

Najważniejsza granica funkcjonalna jest następująca:

```text
Steam macOS       → import lokalnych danych + steam://
Steam Windows     → wspólny Windows Steam client w jednym prefixie
Epic Windows      → Legendary download + osobny environment + launch plan
GOG Windows       → gogdl download + osobny environment + manifest playTask
GOG native macOS  → gogdl build/.app, jeśli release jest rzeczywiście dostępny
```

### Powiązana dokumentacja

- [`P1-Steam-Library.md`](P1-Steam-Library.md)
- [`P1.2-Epic-Library.md`](P1.2-Epic-Library.md)
- [`P1.3-GOG-Library.md`](P1.3-GOG-Library.md)
- [`P1.4-Rich-Metadata-and-Steam-Windows.md`](P1.4-Rich-Metadata-and-Steam-Windows.md)
- [`Backend-and-Runtime-Architecture.md`](Backend-and-Runtime-Architecture.md)
- [`Graphics-Capabilities.md`](Graphics-Capabilities.md)
