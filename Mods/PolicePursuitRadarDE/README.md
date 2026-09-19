# Police Pursuit Radar DE

Radarowy mod dla **Grand Theft Auto: San Andreas – The Definitive Edition**
uruchamianej jako `sa_unreal` przez CLEO Redux x64.

Ta wersja jest przeznaczona dla instalacji widocznej w Boreal, czyli 64-bitowej
wersji DE. Nie jest to plugin `.asi` dla klasycznego GTA SA 1.0 US.

## Funkcje

- radarowa warstwa HUD w lewym dolnym rogu ekranu;
- wykrywanie policjantów w aktywnym wanted levelu przez natywne handle DE;
- rozpoznawanie jednostek pieszych, radiowozów, motocykli, łodzi i helikopterów;
- osobne markery dla typów jednostek oraz marker kierunku gracza;
- testy `IS_LINE_OF_SIGHT_CLEAR` i `HAS_CHAR_SPOTTED_CHAR`;
- stany `PURSUIT`, `LOSING CONTACT`, `SEARCHING` i `ESCAPED`;
- zamrożona pozycja ostatniego kontaktu;
- kołowy obszar poszukiwań wokół ostatniej znanej pozycji;
- opcjonalne markery jednostek poza zakresem radaru;
- konfiguracja INI i przeładowanie przez F11;
- diagnostyka przez `cleo_redux.log`.

## Wymagania

- GTA San Andreas: The Definitive Edition PC;
- CLEO Redux 1.5.0 lub nowszy x64;
- Ultimate ASI Loader x64 jako `version.dll`;
- `IniFiles64.cleo`.

Radar nie wymaga `ImGuiReduxWin64.cleo`. Renderowanie korzysta z natywnej
komendy `DRAW_RECT`, ponieważ oficjalny instalator CLEO Redux wyłącza
ImGuiRedux dla GTA San Andreas: The Definitive Edition.

W katalogu gry powinien być aktywny tylko jeden proxy Ultimate ASI Loader:
`version.dll`. Jeżeli instalator wykryje drugą kopię UAL jako `dinput8.dll`,
przeniesie ją do pliku `dinput8.dll.disabled-duplicate-ual-*` zamiast usuwać,
żeby CLEO Redux nie było uruchamiane przez dwa konkurujące punkty wejścia.

Przy uruchomieniu przez Wine/Boreal dla `SanAndreas.exe` musi być ustawiony
natywny override `version=n,b`. Boreal ustawia go automatycznie tylko dla tego
wykonywalnego, dzięki czemu Wine ładuje UAL i CLEO Redux zamiast wbudowanego
`version.dll`.

CLEO Redux rozpoznaje ten host jako `sa_unreal` i używa definicji
`sa_unreal.json`. Oficjalna dokumentacja CLEO Redux opisuje obsługę DE,
JavaScript oraz dostęp do natywnych komend:
[DE FAQ](https://re.cleo.li/docs/en/the-definitive-edition-faq.html),
[JavaScript API](https://github.com/cleolibrary/CLEO-Redux/blob/master/docs/en/api.md),
[definicje `sa_unreal`](https://re.cleo.li/docs/en/definitions.html).

## Instalacja

Jeżeli używasz Boreal, zaimportuj plik `PolicePursuitRadarDE.zip` z tego
katalogu w sekcji modów gry. Menedżer rozpozna skrypt CLEO Redux, zachowa go w
bibliotece i wdroży do `Gameface/Binaries/Win64/CLEO` po zatwierdzeniu profilu.
Plik `.js` otrzyma przy wdrożeniu wymagany sufiks `[fs]`.

```sh
chmod +x install.sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

Instalator kopiuje:

```text
Gameface/Binaries/Win64/CLEO/PolicePursuitRadar[fs].js
Gameface/Binaries/Win64/CLEO/PolicePursuitRadar.ini
```

Sufiks `[fs]` jest wymagany do zapisu konfiguracji przez IniFiles. Jeżeli
istnieje wcześniejsza wersja skryptu, instalator tworzy kopię zapasową.

## Jak działa wykrywanie

DE nie udostępnia skryptom listy `CWanted::m_pCopsInPursuit` ani prywatnego
renderera klasycznego radaru. Skrypt korzysta więc z publicznego interfejsu
CLEO Redux:

1. odczytuje wanted level gracza;
2. próbuje znaleźć najbliższe postacie w próbkowanych punktach wokół gracza;
3. filtruje postacie typu policjant i rozpoznaje ich aktualny pojazd;
4. sprawdza LOS oraz to, czy policjant widzi gracza;
5. rysuje własny radar przez natywną komendę HUD `DRAW_RECT` w miejscu HUD
   radaru.

Oznacza to, że radar jest oparty o rzeczywiście dostępne dane DE, ale nie
udaje dostępu do wewnętrznego pursuit poolu z klasycznej wersji gry.

## Konfiguracja

Plik `PolicePursuitRadar.ini` pozwala zmienić między innymi:

- zasięg skanowania i radaru;
- częstotliwość skanowania;
- czas przejścia z utraty kontaktu do wyszukiwania;
- promień obszaru poszukiwań;
- położenie i rozmiar warstwy radaru;
- obrót radaru względem kierunku gracza;
- widoczność poszczególnych typów jednostek;
- tryb debugowania.

F11 przeładowuje plik bez ponownego uruchamiania gry.

## Ograniczenia

- Skrypt nie zmienia wanted levelu, AI, spawnów ani misji.
- Próbkowanie świata jest ograniczone, aby nie wykonywać ciężkiego skanu co
  klatkę. Jednostki mogą pojawić się na radarze z niewielkim opóźnieniem.
- Skrypt jest ładowany jako zwykły skrypt CLEO Redux przy rozpoczęciu nowej
  gry lub wczytaniu zapisu. Samo wejście do menu głównego nie uruchamia jego
  pętli rozgrywki; wpis `Police Pursuit Radar DE loaded` można sprawdzić w
  `cleo_redux.log` po wczytaniu zapisu.
- Zachowanie końcowe zależy od wersji CLEO Redux, aktualizacji gry DE i
  zainstalowanych komponentów ASI.
