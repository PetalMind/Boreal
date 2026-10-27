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
   w miarę pierwszego odczytywania celów. Kolejne otwarcia przywracają zapisane
informacje bez ponownego rozwiązywania celów.

W `Ustawienia modów → Quest Distance Journal SE` możesz ukryć lub ponownie
włączyć wiersz odległości pod kompasem. Informacje o celach w dzienniku nadal
pozostają dostępne.

Wymagania: SkyUI, SKSE zgodne z grą i powerofthree's Papyrus Extender.
Mod nie dodaje własnej DLL, więc nie używa adresów pamięci zależnych od wersji
gry. Przy budowaniu skryptów potrzebne są źródła SKSE zgodne z używaną wersją.
Istniejący Nordic Minimal UI SE zmienia HUD/dialogi/sen, a ten mod wyłącznie
moduł dziennika SkyUI. Inny zamiennik dziennika wymaga osobnego dopasowania.

## Jak interpretować dane

- Odległość jest liczona do bieżącej referencji aliasu celu, nie do dowolnej
  postaci lub miasta wybranego na podstawie tytułu zadania.
- Przy kilku celach zapamiętuje cel najbliższy w momencie odczytu, dla którego
  można policzyć odległość. Inne cele mogą znajdować się we wnętrzach lub innych światach.
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
własne skrypty PEX, w tym menu MCM. Mod nie nadpisuje questów gry ani ich skryptów.

## Granice weryfikacji

Kompilacja Papyrusa i ActionScriptu oraz kontrola struktury paczki potwierdzają
zbudowanie artefaktów. Poprawnego wyglądu i zachowania w uruchomionej grze
nie potwierdza sama kompilacja.

## Pamięć celów i kompas

Mod przechowuje 128 ostatnio odwiedzonych pozycji dziennika w zmiennych questu;
zapis Skyrim zachowuje je razem z postępem gry. Otwarcie dziennika odtwarza
przechowane informacje. Zmiana etapu lub stanu celu aktualizuje powiązanie
w tle podczas rozgrywki. Odległość aktualizuje się z pozycji gracza do
przechowanej referencji, bez ponownego przeszukiwania aliasów przy otwarciu.

Pod kompasem pojawia się nazwa i liczba metrów do ostatnio wybranego
w dzienniku zadania, które jest zaznaczone do śledzenia. Dla „Różnych” wybierz
konkretną pozycję na liście celów. Jeśli poprzedni wybór przestaje być
śledzony, mod wybiera inne zapisane, śledzone zadanie i pokazuje jego nazwę.
Przy pierwszym użyciu otwórz dziennik, aby mod zapamiętał listę zadań.
Nie zmienia zaznaczenia questów i nie pokazuje odległości do nieśledzonych
zadań. Przy oddzielnych wnętrzach nadal widnieje brak dostępnej odległości.
Widoczność tego wiersza zmienisz w MCM.

Licznik jest tworzony wewnątrz natywnego kompasu, respektuje jego widoczność
i nie wymaga zastępowania pliku HUD. Dystans dotyczy zapamiętanego celu
wybranego zadania, a nie znacznika własnego ustawionego na mapie.
