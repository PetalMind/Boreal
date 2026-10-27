# Horse Whistle SE

Lekki mod do Skyrim Special Edition. Pokazuje na mapie i kompasie znacznik ostatnio dosiadanego konia, a po gwizdnięciu przenosi go w pobliże gracza.

## Wymagania

- Skyrim Special Edition
- SKSE64
- SkyUI

Marker konia używa wbudowanej w Skyrim ikony stajni (podkowy), więc CoMAP nie jest wymagany.

## Używanie

- Domyślny klawisz gwizdu: `G`.
- W grze otwórz `Ustawienia modów → Horse Whistle SE → Gwizd i sterowanie`, aby zmienić klawisz, przypisać przycisk myszy/pada lub usunąć przypisanie.
- MCM potwierdza konflikt z innym sterowaniem. Akcja przywracania domyślnej wartości przywraca `G`.
- Gwizd ma własny dźwięk. W MCM można go wyłączyć, ustawić głośność 0–100% i odsłuchać.
- Przywoływany jest koń zwrócony przez `Game.GetPlayersLastRiddenHorse()`.
- Znacznik jest dodawany do mapy bez możliwości szybkiej podróży i co 5 sekund aktualizuje położenie.
- Koń pojawia się 220 jednostek za graczem, gdy jest dalej niż 300 jednostek.

## Budowanie

Wymagane są Caprica Papyrus Compiler, Wine i Python 3. Uruchom `./build.sh`. Gotowe archiwum pojawi się jako `SkyrimHorseWhistleSE.zip`.

Wersja pochodzi z `manifest.json`. Oryginalny dźwięk PCM jest generowany przez
`tools/whistle_audio.py`; paczka nie kopiuje dźwięków innych modów ani gry.
