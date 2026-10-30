# Nordic Minimal UI SE

Lekka modyfikacja interfejsu Skyrim SE/AE: paski zdrowia, magicki i kondycji
pojawiają się po zmianie wartości i zanikają po ustawionym czasie. Podczas walki
pozostają widoczne. MCM pozwala zmienić czas zanikania, wyłączyć automatyczne
paski lub kompas. Kompas i znaczniki zadań są domyślnie zachowane, a celownik
ma postać małej, nieruchomej kropki z obrysem poprawiającym czytelność.

Podczas jazdy pojawia się osobny panel wierzchowca z jego nazwą oraz paskami
zdrowia i wytrzymałości. Wartości i procenty odświeżają się na bieżąco, a panel
znika po zejściu z konia.

Wybór czasu oczekiwania używa okrągłej tarczy zamiast poziomego suwaka.
Pierścień pokazuje wybraną liczbę godzin w zakresie 1–24; można ustawić ją
kliknięciem lub przeciągnięciem po tarczy, kółkiem myszy, strzałkami, Page Up /
Page Down albo bumperami kontrolera. Potwierdzanie i anulowanie pozostają
oryginalne.

Klawisz Jasnowidzenia (domyślnie H) można przypisać w MCM. Naciśnięcie włącza
nawigację do celu wskazywanego przez silnik Jasnowidzenia. Trasa odświeża się
co 0,5 sekundy z aktualnej pozycji gracza, również podczas jazdy konnej.
Ponowne naciśnięcie wyłącza nawigację. Koszt wynosi zawsze 0 magicki, także
przy pustym pasku; pomocniczy czar nie daje doświadczenia magii.
Odświeżanie jest wstrzymane w menu. Wczytanie zapisu, śmierć gracza lub
wyłączenie skrótu wyłącza nawigację. Dostępność drogi zależy od celu i siatki
nawigacyjnej gry, tak samo jak przy zwykłym Jasnowidzeniu.

Wersję moda określa plik `VERSION`.

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

## Celownik (1.1.0)

| Stan przekazany przez grę | Wygląd |
| --- | --- |
| `NoTarget` | Kropka |
| `Target` | Kropka z pierścieniem: wskazany obiekt do interakcji |
| `Favor` | Kropka w rombie: tryb wydawania poleceń |
| Wariant `Alert` | Ciepły kolor i dodatkowa kreska ostrzegawcza |
| Skradanie (`StealthMode`) | Oryginalne oko i komunikaty wykrycia, bez dodatkowej kropki |
| Menu, dialog, mapa, killcam lub wyłączony celownik | Ukrywanie zgodnie z natywnym trybem HUD |

W MCM, na stronie „HUD i dialogi”, sekcja „Celownik” pozwala ustawić rozmiar
50–200%, krycie 25–100% oraz łagodne pulsowanie (domyślnie wyłączone).
Ustawienia zapisują się w zapisie gry i są ponownie nakładane po wczytaniu.
Wariant Alert pochodzi z gry; nie jest obliczany z walki ani obecności wroga.
Celownik nie udaje informacji o trafieniu, zasięgu ani torze lotu strzały.
Celowanie łukiem i magią nadal podlega natywnej widoczności HUD.

Analiza opiera się na lokalnym, zdekompilowanym `HUDMenu.as` z paczki i na
[źródle HUDMenu](https://github.com/Mardoxx/skyrimui/blob/master/src/hudmenu/HUDMenu.as).
Porównano również [Clean Dot Crosshair](https://www.nexusmods.com/skyrimspecialedition/mods/68167)
oraz [Dot Crosshair — With Sneak Eye](https://www.nexusmods.com/skyrimspecialedition/mods/28119).
Nie dołączono zasobów tych modów. Paczka nadpisuje cały `hudmenu.swf`, więc
wymaga osobnego patcha przy łączeniu ze SkyHUD, iHUD, innymi przebudowami HUD
lub celownikiem SmoothCam; sama kolejność ładowania nie łączy ich funkcji.

## Zakres weryfikacji

Kompilacja FFDec sprawdza ActionScript, Caprica w trybie strict kompiluje Papyrusa.
Nie zastępuje to uruchomienia w Skyrim: wygląd, animacja oka, współdziałanie
z modami HUD i celowanie w obu perspektywach wymagają weryfikacji w silniku gry.
