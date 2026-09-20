# GTA San Andreas DE — Skip Intro Videos

Mały mod dla **Grand Theft Auto: San Andreas – The Definitive Edition**, który
pomija dwa filmy odtwarzane przy uruchamianiu gry:

- logo/stinger Rockstar,
- ekran creditsów otwierających grę.

Mod nie zmienia cutscen misji, intro pierwszej misji ani filmów uruchamianych z
menu. Podmienia wyłącznie pliki startowe w `Gameface/Content/Movies/1080` na
poprawne, jednoklatkowe filmy H.264. Dzięki temu odtwarzacz Unreal kończy każdy
film niemal natychmiast, a gra przechodzi do kolejnego ekranu.

## Instalacja przez Boreal

Zaimportuj `GTASkipIntroDE.zip` w widoku modów GTA SA:DE, a następnie wdróż
aktywny profil. Boreal podmieni bezpośrednio:

```text
Gameface/Content/Movies/1080/GTA_SA_RSTAR_STINGER_FINAL_1920x1080.mp4
Gameface/Content/Movies/1080/GTA_SA_CREDITS_FINAL_1920x1080.mp4
```

Oryginalne pliki gry pozostają nietknięte i są chronione przez kopię zapasową
menedżera modów.

## Instalacja ręczna

Rozpakuj archiwum w katalogu głównym gry. Zawartość archiwum odtwarza ścieżkę:

```text
Gameface/Content/Movies/1080/
```

Przed ręczną podmianą zachowaj oryginalne pliki. Aby wyłączyć mod, przywróć
oryginalne MP4.

## Zakres zgodności

Mod korzysta z nazw plików używanych przez lokalną instalację GTA SA:DE:

```text
Gameface/Content/Movies/1080/GTA_SA_RSTAR_STINGER_FINAL_1920x1080.mp4
Gameface/Content/Movies/1080/GTA_SA_CREDITS_FINAL_1920x1080.mp4
```

Jeżeli przyszła aktualizacja gry zmieni nazwy lub ścieżki filmów, ten mod nie
będzie miał wpływu na te nowe pliki. Nie należy wtedy podmieniać plików
`pakchunk*.pak` ręcznie.

## Odtworzenie pakietu

`generate_skip_movie.m` wycina pierwszy sample H.264 z lokalnego filmu i tworzy
z niego jednoklatkowy MP4 przy użyciu systemowego AVFoundation na macOS.

W archiwum instalacyjnym nie używam PAK-a: GTA SA:DE ma te filmy jako luźne
pliki i właśnie ich podmiana jest potrzebna, aby gra rzeczywiście je pominęła.
