# Modern Compass DE v1.0

Nowoczesny, kompaktowy kompas dla **Grand Theft Auto: San Andreas – The Definitive Edition** uruchamianej przez **CLEO Redux x64**.

## Założenia

- mechanika poziomego kompasu w stylu współczesnych RPG/open-world;
- kierunek liczony z **aktywnej kamery**, nie z obrotu CJ-a;
- płynne przewijanie z filtrem kątowym;
- N / NE / E / SE / S / SW / W / NW;
- znaczniki co 15 stopni;
- miękki fade przy krawędziach;
- minimalistyczny, półprzezroczysty HUD;
- kompaktowe proporcje przygotowane z myślą o 21:9 / 3440x1440;
- brak odczytu/zapisu pamięci gry i brak ingerencji w kamerę, AI, misje lub save.

## Wymagania

- GTA San Andreas: The Definitive Edition (PC)
- CLEO Redux x64
- `IniFiles64.cleo` w `CLEO/CLEO_PLUGINS`
- plugin Input (standardowo dostępny w instalacji CLEO Redux) dla skrótów F7/F8

## Instalacja

Skopiuj do folderu:

`Gameface/Binaries/Win64/CLEO/`

pliki:

- `ModernCompassDE[fs].js`
- `ModernCompassDE.ini`

Nazwa `[fs]` jest celowa — CLEO Redux wymaga uprawnienia file-system dla odczytu INI.

## Sterowanie

- **F7** — włącz/wyłącz kompas w bieżącej sesji
- **F8** — przeładuj `ModernCompassDE.ini`

Skróty można zmienić w sekcji `[input]` przez Windows Virtual-Key codes.

## Najważniejsze ustawienia

- `width=168` — szerokość paska
- `top_y=18` — odległość od góry
- `visible_half_angle=72` — zakres kompasu na stronę
- `minor_step_deg=15` — gęstość ticków
- `smoothing_ms=72` — płynność ruchu
- `edge_fade_start_percent=62` — początek wygaszania boków
- `show_degree_readout=1` — opcjonalne 000–359

## Architektura / bezpieczeństwo

Kompas korzysta z natywnych `GET_ACTIVE_CAMERA_COORDINATES` i `GET_ACTIVE_CAMERA_POINT_AT`, wylicza heading 0–359, a następnie mapuje względne kąty na wirtualne współrzędne HUD 640x448. Renderer używa tylko lekkich prostokątów i tekstu. Nie przejmuje kamery i powinien współpracować z zewnętrznymi modami kamery.

## Diagnostyka

Jeżeli HUD nie pojawi się:

1. sprawdź `cleo_redux.log`;
2. potwierdź obecność `IniFiles64.cleo` i Input pluginu;
3. upewnij się, że plik skryptu nadal nazywa się `ModernCompassDE[fs].js`;
4. naciśnij F8, aby przeładować INI.

Przy pięciu kolejnych błędach renderera mod wyłącza własny HUD do końca sesji zamiast spamować błędami lub destabilizować grę.
