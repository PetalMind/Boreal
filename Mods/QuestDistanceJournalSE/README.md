# Quest Distance Journal SE

Dziennik SkyUI pokazuje przy niezakończonych zadaniach drugi wiersz z miastem
lub lokalizacją bieżącego celu i liczbą metrów. Pełne informacje są także w opisie
wybranego zadania. Nazwy miejsc pochodzą z gry i zachowują jej język.

## Używanie

- Domyślnie śledzone zadania są na początku, a pozostałe układane według
  miejscowości i odległości. Zadania ukończone zachowują osobną część listy.
- Klawisz S na stronie zadań lub przycisk Sortowanie zmienia kolejno:
  miejscowość, najbliższe cele, nazwę i kolejność gry.
- W MCM: Ustawienia modów → Quest Distance Journal SE → Dziennik i kompas
  wybierzesz sortowanie, pierwszeństwo śledzonych, widoczność szczegółów
  oraz wiersza pod kompasem. Ustawienia zapisują się w zapisie gry.
- Lista Różnych sortuje konkretne pozycje po jej otwarciu. Kolejność celów
  fabularnych wewnątrz zwykłego zadania pozostaje kolejnością gry.
- MCM zawiera odświeżanie celów i ponowną rejestrację skryptu. Aktualizacja
  moda automatycznie unieważnia starszą pamięć lokalizacji.

## Co oznaczają metry

Wszystkie wartości pozostają w metrach, także powyżej 1000 m.

- W linii prostej: pomiar do rzeczywistej referencji celu w tym samym świecie
  zewnętrznym albo tym samym wnętrzu.
- Do wejścia: pomiar z pozycji gracza do zewnętrznych drzwi prowadzących do
  wnętrza celu; uwzględnione są też bramy oddzielnych światów miast.
- Od wyjścia: pomiar od wyjścia z wnętrza gracza do celu na zewnątrz.
- Między wejściami: pomiar pomiędzy zewnętrznymi drzwiami obu wnętrz.

To odległości w linii prostej, bez długości przejścia po wnętrzach, obchodzenia
przeszkód ani czasu podróży. Wejścia pochodzą z rzeczywistych połączeń drzwi
XTEL aktywnych pluginów. Mod nie przypisuje współrzędnych wnętrza do mapy świata.

Przy kilku celach wybierany jest najbliższy dostępny aktywny cel. Jeśli nie ma
bezpiecznego powiązania aliasu, występują nierozstrzygalne warunki widoczności
albo brakuje wspólnego świata/znanego wejścia, widoczny jest jawny brak danych.
Mod nie zgaduje miasta z tytułu zadania.

## Instalacja

1. Zaimportuj QuestDistanceJournalSE.zip w Boreal, MO2 lub Vortex.
2. Włącz QuestDistanceJournalSE.esp. Ten mod musi wygrywać konflikt dla
   Interface/quest_journal.swf.
3. Uruchom grę przez SKSE. Pierwsze odczyty pojawiają się stopniowo;
   ponowne otwarcia korzystają z pamięci do 128 pozycji zapisanej z grą.

Wymagania: SkyUI oraz SKSE zgodne z wersją gry. Wersja 1.3.0 odczytuje
hierarchię lokalizacji z wygenerowanego indeksu i nie wymaga Papyrus Extender.
Nie dodaje DLL. Nordic Minimal UI SE nie zmienia tego pliku dziennika;
inny zamiennik dziennika wymaga osobnego dopasowania.

## Budowanie

Jedynym źródłem wersji jest manifest.json. Wymagane: Python 3.9+, Java,
JPEXS FFDec oraz Caprica (wersja Windows na macOS wymaga Wine).

    python3 build.py --data "/ścieżka/Skyrim/Data" --plugins "/ścieżka/Plugins.txt" --ffdec "/ścieżka/ffdec.jar" --compiler "/ścieżka/Caprica.exe"

Budowanie odczytuje grę i zapisuje wyłącznie paczkę w katalogu moda. Indeksuje
wygrywające rekordy zadań, rodziców lokalizacji, komórki i teleportujące drzwi.
Identyfikatory formularzy są rozwiązywane z nazw pluginów przy uruchomieniu,
więc samo przesunięcie kolejności ładowania nie zmienia powiązań. Po dodaniu
lub aktualizacji moda zmieniającego zadania, lokalizacje albo drzwi trzeba
przebudować paczkę. Raport wejściowych pluginów i liczebności indeksów jest
w build-report.json.

Istniejący luźny dziennik wymaga jawnego --journal-swf wskazującego zgodny
oryginalny plik SkyUI. Nie nakładaj poprawki ponownie na już zmieniony SWF.
Kompilator sprawdza Papyrusa w trybie ścisłym z ostrzeżeniami jako błędami.
Paczka zawiera tylko własne PEX, nie deklaracje z CompilerImports.

## Granice weryfikacji

Kompilacja Papyrusa i ActionScriptu, ponowny odczyt SWF oraz kontrola paczki
potwierdzają artefakty. Nie zastępują obserwacji interfejsu w działającej grze.
