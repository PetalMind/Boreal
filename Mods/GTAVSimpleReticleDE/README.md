# GTA V Simple Reticle — San Andreas Definitive Edition

Własna podmiana standardowego celownika na biały punkt z ciemnym obrysem,
inspirowana wariantem **Simple** z GTA V. Grafika jest tworzona proceduralnie.
To nie jest eksport tekstury z GTA V ani pełny port systemu celowania:
widocznością, skalą, kolorem i reakcją na strzały nadal steruje SA:DE.
Celownik snajperski i inne osobne tekstury pozostają bez zmian.

## Instalacja i przywracanie

Zamknij grę. Uruchom z tego katalogu (macOS, Linux lub Windows z Pythonem 3):

```sh
python3 install.py "/ścieżka/do/Grand Theft Auto San Andreas Definitive Edition"
```

Instalator kopiuje `GTAVSimpleReticleSA_P.pak` do `Gameface/Content/Paks/~mods`.
Rozpoznaje też istniejący katalog `~Mods`. Dotychczasowy
`WatchDogs2DotReticleSA.pak`, `SimpleReticleSA.pak` lub `SimpleReticleSA-V2.pak`
przenosi do `BorealModBackups/GTAVSimpleReticleDE` poza katalogiem Paks.
Pozostałe mody celownika należy wyłączyć osobno — lista nie obejmuje wszystkich nazw.
Oryginalne paczki gry nie są modyfikowane.

Przywrócenie poprzedniego stanu:

```sh
python3 install.py "/ścieżka/do/Grand Theft Auto San Andreas Definitive Edition" --uninstall
```

Archiwum `GTAVSimpleReticleDE.zip` można też importować jako mod PAK w Boreal.
Przy tej metodzie trzeba wcześniej wyłączyć inny mod celownika w Boreal.
Import przez Boreal nie używa instalatora ani jego kopii zapasowej.

## Zakres i budowanie

PAK V3/Zlib, mount point `../../../`, dokładnie dwa pliki:

```text
Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uasset
Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uexp
```

Asset wyodrębniono z lokalnego `pakchunk0-WindowsNoEditor.pak` 20.09.2026.
Generator wymaga zgodności SHA-256 oryginalnego `.uexp`, zachowuje metadane
i zmienia wyłącznie payload BC3/DXT5 128 × 128. Punkt ma średnicę do 10
pikseli tekstury wraz z krawędzią; to nie jest gwarantowany rozmiar ekranowy.

Odtworzenie paczki za pomocą [repak 0.2.3](https://github.com/trumank/repak):

```sh
repak unpack "pakchunk0-WindowsNoEditor.pak" -o original -i '**/T_crosshair_BC.*'
mkdir -p build/Gameface/Content/SanAndreas/Textures/txd
cp original/Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uasset build/Gameface/Content/SanAndreas/Textures/txd/
python3 build_reticle_asset.py original/Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uexp build/Gameface/Content/SanAndreas/Textures/txd/T_crosshair_BC.uexp
repak pack build GTAVSimpleReticleSA_P.pak --version V3 --compression Zlib --mount-point ../../../
```

## Analiza modów z sieci

- [Simple Reticle, Anon2971](https://www.nexusmods.com/grandtheftautothetrilogy/mods/30):
  podmiana standardowego celownika na punkt, instalowana jako PAK w `~mods`.
  Zastosowano tę samą metodę podmiany assetu.
- [Circle Reticle 1.2, ITSM0VER](https://www.nexusmods.com/grandtheftautothetrilogy/mods/712):
  celownik i luneta inspirowane GTA V/Max Payne 3, osobny większy wariant SA.
  Autor wymaga zgody na modyfikowanie i wykorzystanie swoich assetów;
  żaden plik tego moda nie został użyty.
- Analiza objęła opisy, instrukcje i changelog autorów, nie kod źródłowy
  ani binaria tych modów. Własny asset oparto na lokalnych plikach gry
  i generatorze BC3 istniejącym w `WatchDogs2DotReticleDE`.

Paczka została zbudowana; wygląd w uruchomionej grze nie został zweryfikowany.
