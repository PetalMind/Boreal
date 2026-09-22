# Wiedźmin 2 — medalion, odnowienie 1 s

Mod zmienia czas ponownego użycia medalionu z wartości zapisanej w lokalnym
`base_scripts.dzip` na **1 sekundę**. Zmieniany jest tylko timer
`OnEnableMedallion` w `game/player/player.ws`; pozostałe skrypty z lokalnej
instalacji są zachowywane, dzięki czemu można zbudować wersję zgodną z innymi
zainstalowanymi modyfikacjami.

## Gotowy plik

`base_scripts.dzip` jest archiwum do katalogu `CookedPC`. Najbezpieczniej
zaimportować je do Boreal — manager zapisze kopię poprzedniego
`base_scripts.dzip` i będzie mógł ją przywrócić po wyłączeniu moda.

Przy ręcznej instalacji:

1. Zamknij grę.
2. Zrób kopię oryginalnego `CookedPC/base_scripts.dzip`.
3. Skopiuj wygenerowany `base_scripts.dzip` do `CookedPC`, zastępując plik o tej
   samej nazwie.

W natywnej wersji GOG na macOS katalog to zwykle:

```text
The Witcher 2 Assassins of Kings Enhanced Edition.app/Contents/Resources/Data/CookedPC/
```

## Budowanie lub odtworzenie po aktualizacji gry

Builder działa na macOS i wymaga tylko Python 3. Przyjmuje ścieżkę do aplikacji
`.app` albo do jej katalogu `Contents/Resources/Data`:

```sh
./build.sh "/ścieżka/The Witcher 2 Assassins of Kings Enhanced Edition.app"
```

Skrypt rozpakowuje lokalne `base_scripts.dzip` do katalogu tymczasowego,
zmienia jeden timer i tworzy ponownie `base_scripts.dzip` w tym katalogu moda.
Nie zapisuje niczego w instalacji gry.

## Zgodność

`base_scripts.dzip` jest wspólnym archiwum skryptów. Inny mod, który zmienia
`game/player/player.ws`, może wejść z nim w konflikt; w takim przypadku trzeba
połączyć zmiany w jednym pliku i ponownie zbudować archiwum. Builder bazujący na
lokalnym pliku zachowuje pozostałe zmiany obecne w tej instalacji.

`tools/dzip.py` korzysta z opisu formatu DZIP i algorytmu LZF rozwijanego w
projekcie [Gibbed.RED](https://github.com/yole/Gibbed.RED), udostępnionym na
licencji zlib.
