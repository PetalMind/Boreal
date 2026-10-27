# Quest Distance Journal SE

Przy niezakończonych zadaniach w liście dziennika SkyUI dodaje drugą linię:
miasto lub lokalizacja oraz odległość od postaci, np.
`Biała Grań | 420 m w linii prostej`. Nazwy miejsc pochodzą z gry, więc
zachowują język jej tłumaczenia. Lista nadal obsługuje zaznaczanie zadań,
klawiaturę, kontroler i pokazywanie celów na mapie.

## Instalacja

1. Zaimportuj `QuestDistanceJournalSE.zip` w Boreal, MO2 lub Vortex.
2. Włącz `QuestDistanceJournalSE.esp`. W konflikcie plików ten mod musi wygrywać
   dla `Interface/quest_journal.swf`.
3. Uruchom grę przez SKSE i otwórz dziennik. Dane pojawiają się stopniowo,
   w miarę odczytywania celów. Zamknięcie dziennika zatrzymuje obliczenia.

Wymagania: SkyUI, SKSE zgodne z grą i powerofthree's Papyrus Extender.
Pakiet zbudowano dla lokalnej instalacji Skyrim SE 1.7.99.0 / SKSE 2.3.0.
Mod nie dodaje własnej DLL, więc nie używa adresów pamięci z innej wersji gry.
Istniejący Nordic Minimal UI SE zmienia HUD/dialogi/sen, a ten mod wyłącznie
moduł dziennika SkyUI. Inny zamiennik dziennika wymaga osobnego dopasowania.

## Jak interpretować dane

- Odległość jest liczona do bieżącej referencji aliasu celu, nie do dowolnej
  postaci lub miasta wybranego na podstawie tytułu zadania.
- Przy kilku celach pokazuje najbliższy cel, dla którego można policzyć
  odległość. Inne cele mogą znajdować się we wnętrzach lub innych światach.
- To odległość w linii prostej: nie długość drogi, czas podróży ani trasa
  uwzględniająca góry i drzwi.
- Odległość ma sens w tym samym świecie zewnętrznym albo tym samym wnętrzu.
  Dla oddzielnych wnętrz/światów widnieje `odległość niedostępna`.
- Nazwa miasta pochodzi z hierarchii lokalizacji celu. Dla miejsc poza miastem
  pokazuje lokalizację i region, jeśli gra udostępnia te dane.
- Cele z warunkami widoczności nie są zgadywane: bez możliwości rozstrzygnięcia
  warunków widnieje komunikat o braku pewnej lokalizacji. Cele bez aliasu lub
  jeszcze niewypełnione również mają jawny stan braku danych.
- Zadania różne dostają szczegóły po otwarciu ich listy celów.
- Powiązania celów i aliasów są indeksowane podczas budowania na podstawie
  wygrywających rekordów aktywnych pluginów. Stan celów i pozycje są odczytywane
  podczas gry. Po dodaniu lub aktualizacji moda zmieniającego zadania należy
  ponownie zbudować pakiet. Samo przesunięcie indeksów pluginów nie zmienia
  powiązań, ponieważ baza używa identyfikatorów edytora zadań.

## Budowanie

Wersja ma jedno źródło prawdy: `manifest.json`. Skrypt odczytuje grę, ale
zapisuje wyłącznie pakiet w katalogu moda; nie instaluje go automatycznie.
Wymaga Python 3.9+, Java, JPEXS FFDec oraz Caprica; Windowsowa Caprica na macOS
wymaga Wine. `WINEPREFIX` można ustawić na osobny katalog roboczy.

```sh
python3 build.py \
  --data "/ścieżka/do/Skyrim/Data" \
  --plugins "/ścieżka/do/Plugins.txt" \
  --ffdec "/ścieżka/do/ffdec.jar" \
  --compiler "/ścieżka/do/Caprica.exe"
```

Istniejący luźny plik dziennika wymaga jawnego `--journal-swf`. Nieznany układ
kodu SkyUI przerywa budowanie zamiast nakładać niepewną poprawkę.
`build-report.json` zapisuje listę wejściowych pluginów i indeks celów.
Deklaracje `Source/CompilerImports` służą wyłącznie kompilacji; paczka zawiera
tylko cztery własne skrypty PEX. Mod nie nadpisuje questów gry ani ich skryptów.

## Granice weryfikacji

Kompilacja Papyrusa i ActionScriptu oraz kontrola struktury paczki potwierdzają
zbudowanie artefaktów. Poprawnego wyglądu i zachowania w uruchomionej grze
nie potwierdza sama kompilacja.
