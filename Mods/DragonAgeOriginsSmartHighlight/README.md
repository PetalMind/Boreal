# Dragon Age: Origins — Smart Highlight

Mały, natywny helper dla pecetowej wersji **Dragon Age: Origins**. Rozwiązuje
problem trzymania klawisza TAB:

- pierwsze naciśnięcie TAB przełącza natywne podświetlanie obiektów na stałe;
- kolejne naciśnięcie TAB je wyłącza;
- helper reaguje tylko wtedy, gdy aktywne okno należy do DAO;
- po przełączeniu do innej aplikacji zwalnia sztucznie przytrzymany klawisz,
  a po powrocie do gry przywraca stan przełącznika;
- `SmartHighlight.ini` może zsynchronizować ustawienia z add-inem
  **Auto Highlight**: zasięg, odświeżanie nazw, NPC, bohatera, kompanów i
  tagów.

## Instalacja

1. Rozpakuj `DragonAgeOriginsSmartHighlight.zip` do katalogu gry.
2. Skopiuj zawartość `SmartHighlight/` obok `DAOrigins.exe`, najczęściej do
   `bin_ship/SmartHighlight/`.
3. Uruchom `DAO_SmartHighlightTool.exe` przed rozpoczęciem gry.
4. W grze naciskaj TAB jako przełącznik.

Na Windowsie helper nie wymaga AutoHotkey ani podmiany `DAOrigins.exe`.
Po instalacji w katalogu gry Boreal rozpoznaje go jako `Game Action` i uruchamia
w tym samym środowisku Wine/prefixie co DAO.

## Konfiguracja

Edytuj `SmartHighlight.ini` przed uruchomieniem helpera:

```ini
[smart_highlight]
enabled=1
sync_auto_highlight=1
toggle_key=TAB

[auto_highlight]
show_npcs=0
show_hero=0
show_followers=0
show_tags=0
range_m=20
refresh_s=45
```

`range_m` i pozostałe ustawienia sekcji `auto_highlight` są zapisywane do
`Documents/BioWare/Dragon Age/Settings/DragonAge.ini` jako sekcja
`[AutoHighlightOptions]`. Zadziała to wtedy, gdy zainstalowany jest add-in
Auto Highlight. Sam helper nie kopiuje ani nie modyfikuje plików tego
zewnętrznego add-inu.

## Granica możliwości DAO

Natywne podświetlanie TAB i add-in Auto Highlight rozróżniają grupy obiektów
przez ich zachowanie i nazwy. Publicznie dostępna konfiguracja Auto Highlight
nie udostępnia osobnych kolorów ani ikon dla skrzyń, NPC i pozostałych
interaktywnych obiektów. Dlatego ten pakiet daje rzeczywisty przełącznik TAB,
filtry grup NPC/bohater/kompani, tagi oraz zasięg, ale nie obiecuje fikcyjnych
kolorowych markerów, których silnik DAO nie wystawia jako konfigurowalnej
funkcji.

Opcjonalny add-in Auto Highlight można pobrać z jego oryginalnej strony:
<https://www.nexusmods.com/dragonage/mods/114>

Nie dołączam jego plików ani nie modyfikuję ich, ponieważ autor zabrania
redystrybucji i modyfikacji bez zgody.

## Budowanie helpera

DAO jest aplikacją 32-bitową. Na macOS z zainstalowanym MinGW-w64 uruchom:

```sh
./build.sh
```

Skrypt buduje `DAO_SmartHighlightTool.exe` jako PE32, bez zależności od bibliotek
uruchomieniowych MinGW. Wymagany jest `i686-w64-mingw32-g++`.

## Odinstalowanie

Zamknij `DAO_SmartHighlightTool.exe` i usuń katalog `SmartHighlight/`. Wpisy
`[AutoHighlightOptions]` pozostaną w `DragonAge.ini`; można je usunąć ręcznie,
jeśli add-in Auto Highlight nie będzie już używany.
