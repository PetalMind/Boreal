# Police Pursuit Radar DE — wersja 1.2 stabilizacja HUD/blipów

Mod dla **Grand Theft Auto: San Andreas – The Definitive Edition** uruchamianej
jako `sa_unreal` przez CLEO Redux x64.

Wersja 1.2 zawiera własną warstwę HUD rysowaną natywnym `DRAW_RECT`,
ograniczony cykl życia standardowych blipów oraz rozdzielone odświeżanie
istniejących jednostek od wyszukiwania nowych. HUD `DRAW_RECT` jest obecnie
wyłączony domyślnie, ponieważ w tej wersji powodował blokadę renderera UE4
podczas ładowania. Standardowe blipy CLEO pozostają bezpiecznym uzupełnieniem
minimapy.

## Funkcje

- wykrywanie pobliskich policjantów oraz ich aktualnych pojazdów;
- własny radar HUD z półprzezroczystym tłem, pierścieniami i markerem gracza;
- markery pieszych, samochodów, motocykli, łodzi i helikopterów;
- kierunek ruchu/patrzenia jednostki przez chevron oraz stożek widzenia;
- półprzezroczysty obszar `SEARCH` wokół zamrożonego
  `lastKnownPlayerPosition`;
- stany `PURSUIT → SEARCH → ESCAPED`;
- sprawdzanie LOS przez `IS_LINE_OF_SIGHT_CLEAR` oraz kontaktu przez
  `HAS_CHAR_SPOTTED_CHAR`;
- stabilne klucze logiczne jednostek niezależne od wrapperów JavaScript;
- ograniczona pula natywnych blipów oraz wolniejsza aktualizacja markerów
  kierunku, aby nie wyczerpywać puli blipów gry;
- brak zmian wanted levelu, AI, spawnów, misji i zachowania policji.

Nie ma ctOS, Jam Com ani nowych spawnów policji. Renderer jest celowo
oparty na `DRAW_RECT`, ponieważ nie korzysta z ImGui ani prywatnego renderera
radaru UE4.

## Wymagania

- GTA San Andreas: The Definitive Edition PC;
- CLEO Redux 1.5.0 lub nowszy x64;
- Ultimate ASI Loader x64 jako `version.dll`;
- `IniFiles64.cleo`.

CLEO Redux dla DE używa hosta `sa_unreal` i pliku definicji
`sa_unreal.json`. Dokumentacja CLEO Redux opisuje obsługę JavaScript i natywów
gry:
[DE FAQ](https://re.cleo.li/docs/en/the-definitive-edition-faq.html),
[JavaScript API](https://re.cleo.li/docs/en/api.html),
[definicje hostów](https://re.cleo.li/docs/en/definitions.html).

## Instalacja

Jeśli używasz Boreal, zaimportuj `PolicePursuitRadarDE.zip` z tego katalogu w
sekcji modów gry. Menedżer wdroży:

```text
Gameface/Binaries/Win64/CLEO/PolicePursuitRadar[fs].js
Gameface/Binaries/Win64/CLEO/PolicePursuitRadar.ini
```

Sufiks `[fs]` pozwala CLEO Redux rozwiązać ścieżkę INI względnie do skryptu.

Instalacja ręczna:

```sh
chmod +x install.sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

## Jak działa renderer

Pozycje świata są przeliczane do konfigurowalnego, znormalizowanego układu HUD:

1. pozycja jednostki jest obracana względem headingu gracza, jeśli
   `rotate_with_player=1`;
2. odległość jest skalowana przez `range_m`;
3. punkty są ograniczane do elipsy radaru;
4. wypełnienia są rasteryzowane poziomymi prostokątami `DRAW_RECT`.

W ten sposób renderer może narysować obszar poszukiwań i stożki jako
półprzezroczyste trójkąty/ellipse, mimo że natywny primitive udostępniony
skryptom jest tylko prostokątem. Stożki są skierowane zgodnie z headingiem
policjanta, a kolorem rozróżniają kontakt aktywny od jednostki, która nie widzi
gracza.

## Mechanika pościgu

Przy aktywnym wanted levelu skrypt próbuje znaleźć policjantów w próbkowanych
obszarach wokół gracza. Natywne zapytanie zwraca jedną najbliższą postać na
próbkę, dlatego skan używa stałej, ograniczonej siatki punktów i najpierw
odświeża już wykryte jednostki. Jeśli policjant przejdzie oba testy — LOS oraz
`HAS_CHAR_SPOTTED_CHAR` — stan przechodzi do `PURSUIT`, a
`lastKnownPlayerPosition` jest aktualizowane.

Po utracie kontaktu pozycja zostaje zamrożona. Po `lost_sight_delay_ms` stan
przechodzi do `SEARCH`, a radar pokazuje żółty punkt i półprzezroczysty obszar
poszukiwań. Po wyzerowaniu wanted levelu markery są usuwane, stan przechodzi do
`ESCAPED`, a po krótkim okresie wraca do `IDLE`.

Przejścia stanów i współrzędna ostatniego kontaktu są zapisywane w
`cleo_redux.log`.

## Konfiguracja HUD

Sekcja `[hud]` pozwala zmienić:

- `range_m`, `size_px`, `screen_x_percent`, `screen_y_percent` — skalę i
  pozycję własnego radaru;
- `rotate_with_player` — radar obracany z graczem albo północą u góry;
- `background_alpha_percent` i `ring_alpha_percent` — wygląd podstawy HUD;
- `search_fill_alpha_percent` i `search_border_alpha_percent` — obszar
  poszukiwań;
- `cone_length_m`, `cone_fov_deg`, `cone_fill_alpha_percent` i
  `cone_border_alpha_percent` — stożki policji.

`max_units` ogranicza liczbę jednostek rysowanych przez HUD, a `draw_budget`
ustala maksymalną liczbę wywołań `DRAW_RECT` na jedną klatkę. Przekroczenie
budżetu obcina tylko dalsze elementy tej klatki i nie wyłącza całej gry.

`hud.enabled=1` włącza eksperymentalny renderer `DRAW_RECT`, ale w dostarczonej
konfiguracji pozostaje wyłączony do czasu zastąpienia go bezpieczniejszym
rendererem sprite'owym. Jeśli zostanie ręcznie włączony, ma limit 6 jednostek,
około 15 FPS, domyślnie 96 wywołań na klatkę (maksymalnie 120) i automatyczną
pauzę po błędzie. Po wykryciu gameplayu skrypt odczekuje 5 sekund, aby nie
wykonywać odczytów świata podczas kończenia ładowania.
`blips.show_native_blips=1` włącza standardowe blipy CLEO na oryginalnej
minimapie. `max_native_blips` ogranicza liczbę blipów śledzących, a
`max_direction_blips`, `direction_update_distance_m` i
`direction_update_interval_ms` ograniczają koszt markerów kierunku. F11
przeładowuje konfigurację bez restartu gry.

## Ograniczenia

- CLEO Redux nie udostępnia skryptowi prywatnej transformacji radaru UE4.
  Pozycja własnej warstwy jest dlatego konfigurowalną aproksymacją HUD, a nie
  odczytem wewnętrznego layoutu gry.
- Natywne skanowanie zwraca pojedynczą postać dla jednego obszaru; jednostki są
  więc próbkowane rotującymi pierścieniami. Wyszukiwanie nowych jednostek jest
  wykonywane rzadziej niż odświeżanie już znanych, aby nie obciążać puli ruchu
  ulicznego i AI.
- `DRAW_RECT` jest prostym primitive 2D. Renderer daje wypełnione obszary i
  stożki, ale nie używa tekstur ani prawdziwego wektorowego clippingu UE4.
- Repozytorium nie zawiera instalacji gry, więc nie deklaruje zweryfikowanego
  runtime smoke testu.
