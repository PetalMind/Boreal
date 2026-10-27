# Changelog

## 1.3.1

- Naprawiono częściowo zainicjalizowaną pamięć celów w istniejących zapisach; każda brakująca tablica jest odtwarzana osobno przed obliczeniem odległości.

## 1.3.0

- Naprawiono odczyt po pierwszej inicjalizacji i powrocie do dziennika; dodano handshake SKSE, odświeżanie i migrację pamięci istniejących zapisów.
- Szczegóły korzystają z natywnego pola wiersza i są również w opisie zadania.
- Metry do celów we wnętrzach mogą korzystać z rzeczywistych wejść oraz bram miast, z opisem rodzaju pomiaru.
- Dodano sortowanie po miejscowości, odległości, nazwie lub kolejności gry oraz pierwszeństwo śledzonych. Przełączanie w MCM, przyciskiem i klawiszem S.
- Rozbudowano MCM o widoczność szczegółów, odświeżanie i licznik zapisanych zadań.
- Hierarchia lokalizacji nie wymaga już Papyrus Extender; indeks obejmuje także połączenia drzwi i działa przy zmianie indeksów pluginów.
- Nieznane lub warunkowe cele mają jawny brak danych zamiast pustego wiersza.

## 1.2.0

- Dodano MCM do włączania i ukrywania wiersza odległości pod kompasem.
- Dodano ponowną rejestrację menu po wczytaniu zapisu.

## 1.1.0

- Informacje o celach są przechowywane w zapisie gry i przywracane po otwarciu dziennika bez ponownego rozwiązywania aliasów.
- Zmiany etapów i odległości aktualizowane są w tle podczas rozgrywki.
- Kompas pokazuje nazwę i odległość w metrach do ostatnio wybranego, śledzonego zadania.

## 1.0.0 — 2026-10-27

- Pierwsza wersja: lokalizacja i odległość wprost przy zadaniach dziennika SkyUI.
- Bieżące referencje celów pobierane z aliasów niezakończonych celów zadań.
- Nazwy miast i regionów z lokalizacji gry, w języku zainstalowanej gry.
- Osobne stany ustalania celu, nieznanej lokalizacji i niedostępnej odległości.
- Pakiet przygotowywany z faktycznie zainstalowanych pluginów, z uwzględnieniem nadpisań.
