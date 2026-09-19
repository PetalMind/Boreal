# Watch Dogs 2 Dot Reticle DE

Własny mod `.pak` dla **Grand Theft Auto: San Andreas – The Definitive
Edition**, który zastępuje domyślny reticle małą białą kropką z subtelnym
ciemnym obrysem. To podmiana assetu HUD-u, więc kropka pojawia się dokładnie w
tych samych sytuacjach co oryginalny celownik — tylko podczas celowania — bez
CLEO, skryptów wykonywanych co klatkę i zmian stanu HUD-u.

## Zmieniony asset

Mod zawiera wyłącznie:

```text
Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uasset
Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uexp
```

Oryginalna tekstura została odczytana z PAK-a SA:DE w wersji gry
`1.0.113.21181`. Zachowane zostały format DXT5/BC3, canvas 128 × 128,
metadane assetu i ścieżka Unreal. Zmienione są wyłącznie dane pikseli: tło jest
przezroczyste, a środek zawiera kropkę.

## Instalacja przez Boreal

Zaimportuj `WatchDogs2DotReticleDE.zip` w widoku modów GTA SA:DE. Boreal
rozpozna archiwum jako mod Unreal PAK i wdroży plik do:

```text
Gameface/Content/Paks/~mods/WatchDogs2DotReticleSA.pak
```

Nie instaluj jednocześnie starej wersji CLEO `watch_dogs2_dot_reticle[fs].js`.
Została usunięta z tej wersji, ponieważ nakładka CLEO mogła dorysowywać drugi
celownik i zmieniała stan gry.

## Instalacja ręczna

Skopiuj plik `WatchDogs2DotReticleSA.pak` do:

```text
Gameface/Content/Paks/~mods/
```

Jeżeli katalog `~mods` nie istnieje, utwórz go. Aby wyłączyć mod, usuń tylko
ten plik `.pak`; oryginalny `pakchunk0-WindowsNoEditor.pak` nie jest zmieniany.

## Dlaczego PAK zamiast CLEO

Pierwsza wersja używała `DRAW_CROSSHAIR(false)` i `DRAW_CROSSHAIR(true)`.
Definicja SA:DE opisuje `DRAW_CROSSHAIR` jako wymuszenie wyświetlania
celownika, a nie przełącznik do zapisywania i odtwarzania poprzedniego stanu.
To powodowało pozostawanie celownika po użyciu i mogło destabilizować sesję.

Publiczne CLEO nie udostępnia bezpiecznego natywu „ukryj tylko standardową
teksturę celownika”. Podmiana właściwego assetu Unreal rozwiązuje problem bez
ingerencji w logikę gry, wejście, minimapę, misje i HUD.

## Źródła techniczne

- [Simple Reticle — przykład podmiany domyślnego reticle przez `.pak`](https://www.nexusmods.com/grandtheftautothetrilogy/mods/30)
- [Dokumentacja instalacji modów PAK w Trilogy DE](https://www.gta.cz/san-andreas-definitive-edition/clanek/vkladani-modifikaci/)
- [Sanny Builder Library — definicje natywów SA:DE](https://github.com/sannybuilder/library/blob/master/sa_unreal/sa_unreal.json)
- [repak — narzędzie do odczytu i zapisu Unreal PAK](https://github.com/trumank/repak)

Nie użyłem plików graficznych ani PAK-a z Simple Reticle. Asset został
przygotowany niezależnie z plików lokalnej instalacji gry.
