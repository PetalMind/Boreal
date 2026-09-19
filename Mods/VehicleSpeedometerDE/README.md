# Vehicle Speedometer DE — v8

Speedometr dla GTA San Andreas: The Definitive Edition, CLEO Redux x64.

## Wygląd

Kompaktowy cyfrowy HUD znajduje się w prawym dolnym rogu, ponad obszarem
nazwy dzielnicy i komunikatów. Prędkość jest największa, `KM/H` jest pod nią,
a pod spodem znajduje się tylko `D`/`R` oraz cienki segmentowy pasek. Nie ma
widocznej karty ani dużej ramki, a tekst ma natywny krój 3, czarny obrys i cień.
Prędkość nie ma zer wiodących: `0`, `8`, `42`, `108`.

Pozycja jest konfigurowana jako proporcja ekranu, a na granicy renderera tekst
jest przeliczany do wymaganej przez `DISPLAY_TEXT` przestrzeni 640×448.
Prostokąty paska korzystają z tej samej przestrzeni. Dzięki temu układ skaluje
się z HUD-em gry na ekranach ultrawide. Pozycja startowa obejmuje około 82–94%
wysokości ekranu i 88–96% szerokości widgetu.

SA:DE nie udostępnia wiarygodnego RPM ani biegu skrzyni przez używany interfejs.
Pasek pokazuje więc dodatnie obciążenie wynikające z przyspieszenia i nie jest
opisywany jako RPM. Nie pokazujemy fikcyjnego `D3`.

## Naprawa zatrzymywania skryptu

Tablice progów biegów przeniesiono przed główną pętlę. Poprzednio znajdowały
się za `while (true)` i nigdy nie były inicjalizowane. Pierwsze przejście
modelu do jazdy naprzód mogło zakończyć skrypt błędem `ReferenceError`.

Pętla renderująca ma osłonę wyjątków. Błąd pojedynczego odczytu natywnego
ukrywa licznik na bieżącej klatce, zapisuje komunikat najwyżej raz na sekundę
i pozwala następnej klatce ponownie przejąć pojazd. Nie kończy całego skryptu.
Nie jest to sprawdzenie w uruchomionym silniku gry.

## Instalacja

W Boreal zaimportuj aktualny `VehicleSpeedometerDE.zip`.
Wymagania: CLEO Redux x64, Ultimate ASI Loader x64 (`version.dll`),
`IniFiles64.cleo` i GTA SA:DE PC.

Ręcznie:

```sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

Skrypt trafia do `Gameface/Binaries/Win64/CLEO/VehicleSpeedometerDE[fs].js`,
a konfiguracja do tego samego katalogu jako `VehicleSpeedometerDE.ini`.
Instalator zachowuje istniejącą konfigurację. Wersje INI 5, 6 i 7 są obsługiwane:
ustawienia działania pozostają, a wygląd przyjmuje nowe wartości domyślne.
Do ręcznej zmiany pozycji użyj INI v8.

## Konfiguracja

- `layout.anchor_x_percent=955`: prawa kotwica widgetu w przestrzeni 0..1,
  zapisana jako tysięczne.
- `layout.anchor_y_percent=810`: górna pozycja prędkości.
- `layout.speed_text_scale_x100=110`: rozmiar prędkości.
- `layout.unit_text_scale_x100=36`: rozmiar `KM/H`.
- `layout.drive_text_scale_x100=46`: rozmiar `D`/`R`.
- `layout.bar_width_percent=95`, `bar_height_percent=7`, `bar_segments=12`:
  proporcje cienkiego paska obciążenia.
- `layout.font=3`: natywny krój tekstu.
- `visual.show_direction=1`: pokazuje R przy cofaniu.
- `units.speed_multiplier_x100=360`: przelicznik prędkości 3,6.
- `speed.smoothing_percent=14`: wygładzanie wskazania.
- `speed.update_interval_ms=40`: odstęp aktualizacji.

F11 przeładowuje INI. Po zakończeniu skryptu błędem w starej wersji sam F11
nie pomoże — potrzebne jest ponowne załadowanie skryptu lub restart gry.
Parametry przyspieszenia i szacowanych biegów pozostają częścią modelu,
ale nie są wyświetlane jako fikcyjny RPM lub bieg.

Odczyty pojazdu, model, renderer i pętla pozostają oddzielone. Mod korzysta
z FxtStore i DISPLAY_TEXT, nie podmienia plików gry ani fizyki pojazdu.
