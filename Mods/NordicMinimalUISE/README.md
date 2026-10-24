# Nordic Minimal UI SE

Lekka modyfikacja interfejsu Skyrim SE/AE: paski zdrowia, magicki i kondycji
pojawiają się po zmianie wartości i zanikają po ustawionym czasie. Podczas walki
pozostają widoczne. MCM pozwala zmienić czas zanikania, wyłączyć automatyczne
paski lub kompas. Kompas i znaczniki zadań są domyślnie zachowane, a celownik
ma postać małej, nordyckiej kropki.

Lista tematów dialogowych używa spokojniejszej, nordyckiej palety: jasny,
przygaszony tekst dla nieaktywnych tematów oraz ciepły, stonowany akcent dla
zaznaczenia. Układ, kamera i sterowanie dialogiem pozostają oryginalne.

## Wymagania

- Skyrim Special Edition lub Anniversary Edition;
- SKSE64 zgodny z wersją gry;
- SkyUI z MCM.

## Instalacja

Zaimportuj `NordicMinimalUISE.zip` w Boreal, włącz `NordicMinimalUISE.esp` i
uruchom grę przez SKSE. W MCM wybierz „Nordic Minimal UI”. Konflikty z innymi
modyfikacjami nadpisującymi `Interface/hudmenu.swf` lub
`Interface/dialoguemenu.swf` rozstrzygnij kolejnością ładowania.

## Budowanie

`build.sh` używa BSArch do odczytu oryginalnych SWF z `Skyrim - Interface.bsa`,
JPEXS FFDec do patchowania oraz Caprica do kompilacji Papyrusa. Gra i jej pliki
nie są modyfikowane. Ustaw `SKYRIM_DATA`, `BSARCH_EXE`, `FFDEC_JAR` lub
`CAPRICA_EXE`, jeśli narzędzia znajdują się w innych lokalizacjach.
