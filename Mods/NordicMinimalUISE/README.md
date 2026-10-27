# Nordic Minimal UI SE

Lekka modyfikacja interfejsu Skyrim SE/AE: paski zdrowia, magicki i kondycji
pojawiają się po zmianie wartości i zanikają po ustawionym czasie. Podczas walki
pozostają widoczne. MCM pozwala zmienić czas zanikania, wyłączyć automatyczne
paski lub kompas. Kompas i znaczniki zadań są domyślnie zachowane, a celownik
ma postać małej, nordyckiej kropki z delikatnym pulsem i szybszą animacją alarmową.

Podczas jazdy pojawia się osobny panel wierzchowca z jego nazwą oraz paskami
zdrowia i wytrzymałości. Wartości i procenty odświeżają się na bieżąco, a panel
znika po zejściu z konia.

Wybór czasu oczekiwania używa okrągłej tarczy zamiast poziomego suwaka.
Pierścień pokazuje wybraną liczbę godzin w zakresie 1–24; można ustawić ją
kliknięciem lub przeciągnięciem po tarczy, kółkiem myszy, strzałkami, Page Up /
Page Down albo bumperami kontrolera. Potwierdzanie i anulowanie pozostają
oryginalne.

Klawisz Jasnowidzenia można przypisać w MCM. Po postawieniu własnego znacznika
na mapie użyj tego klawisza, aby wywołać wbudowany czar i zobaczyć trasę do celu.

Lista tematów dialogowych używa spokojniejszej, nordyckiej palety: nieomówione
tematy są złote, a wcześniej użyte przygaszone. Przy przycisku wyjścia z rozmowy
pojawia się złota ikona drzwi ze strzałką. Gra nie przekazuje interfejsowi
informacji, czy temat rozpoczyna lub kończy zadanie, więc złoto oznacza nowy
temat, a nie gwarantowany związek z zadaniem. Układ, kamera i sterowanie
dialogiem pozostają oryginalne.

## Wymagania

- Skyrim Special Edition lub Anniversary Edition;
- SKSE64 zgodny z wersją gry;
- SkyUI z MCM.

## Instalacja

Zaimportuj `NordicMinimalUISE.zip` w Boreal, włącz `NordicMinimalUISE.esp` i
uruchom grę przez SKSE. W MCM wybierz „Nordic Minimal UI”. Konflikty z innymi
modyfikacjami nadpisującymi `Interface/hudmenu.swf`,
`Interface/dialoguemenu.swf` lub `Interface/sleepwaitmenu.swf` rozstrzygnij
kolejnością ładowania.

## Budowanie

`build.sh` używa BSArch do odczytu oryginalnych SWF z `Skyrim - Interface.bsa`,
JPEXS FFDec do patchowania oraz Caprica do kompilacji Papyrusa. Gra i jej pliki
nie są modyfikowane. Ustaw `SKYRIM_DATA`, `BSARCH_EXE`, `FFDEC_JAR` lub
`CAPRICA_EXE`, jeśli narzędzia znajdują się w innych lokalizacjach.

## Aktualizacja menu MCM

Podmień poprzednią paczkę tego moda w menedżerze, zachowując jedną aktywną
kopię, i włącz jego ESP. Archiwum zawiera plik SEQ uruchamiający quest
konfiguracji oraz alias gracza odnawiający rejestrację MCM po wczytaniu zapisu.
Poprawiona wersja nie nadpisuje identyfikatorów rekordów SkyUI.

Panel konia wymaga powerofthree's Papyrus Extender. Podczas jazdy odczytuje
aktualnego wierzchowca przez `GetMount`. Ostatnio dosiadany koń jest używany
wyłącznie jako wariant zapasowy, jeśli jego jeźdźcem nadal jest gracz.
