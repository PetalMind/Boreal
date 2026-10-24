# Horse Whistle SE

Lekki mod do Skyrim Special Edition. Pokazuje na mapie i kompasie znacznik ostatnio dosiadanego konia, a po gwizdnięciu przenosi go w pobliże gracza.

## Wymagania

- Skyrim Special Edition
- SKSE64
- Address Library for SKSE Plugins
- SkyUI
- CoMAP z `Data/SKSE/Plugins/MapMarkerFramework.dll`

Instalator FOMOD sprawdza obecność aktywnego Map Marker Framework i SkyUI. Bez CoMAP niestandardowa ikona konia nie zostanie wczytana.

## Używanie

- Domyślny klawisz gwizdu: `G`.
- W grze otwórz `Ustawienia modów → Horse Whistle SE → Ustawienia`, aby zmienić klawisz.
- Przywoływany jest koń zwrócony przez `Game.GetPlayersLastRiddenHorse()`.
- Znacznik jest dodawany do mapy bez możliwości szybkiej podróży i co 5 sekund aktualizuje położenie.
- Koń pojawia się 220 jednostek za graczem, gdy jest dalej niż 300 jednostek.

## Budowanie

Wymagane są Caprica Papyrus Compiler, Wine, Python 3 i Pillow (`python3 -m pip install -r requirements-build.txt`). Uruchom `./build.sh`. Gotowe archiwum pojawi się jako `SkyrimHorseWhistleSE.zip`.
