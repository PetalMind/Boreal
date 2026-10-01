# Analiza i poprawki widoku Odkrywaj — 2026-10-01

## Zakres i rzeczywiste dane

Analiza obejmuje `DiscoveryView`, projekcję filtrów i sortowania, usługę AppleGamingWiki/Steam, cache metadanych i okładek, obsługę cen przez kafelki, zapis zainteresowań oraz przejście do szczegółów. Punktem odniesienia była aktualna wersja plików w roboczym repozytorium, z wcześniejszymi niezapisanymi zmianami. Zmiany innych funkcji zostały zachowane.

Lokalny `Discovery/applegamingwiki.json` początkowo zawierał 23 054 rekordy. Podczas pracy, bez uruchamiania nowej kompilacji aplikacji, plik wzrósł do 26 131 rekordów i osiągnął `steamOffset = steamTotal = 30298`. To obserwacja zmian cache; nie jest pomiarem ruchu sieciowego ani śladem stosu działającej aplikacji.

Kopia końcowego cache użyta do pomiaru zawierała:

| Właściwość | Wartość |
| --- | ---: |
| Rekordy katalogu | 26 131 |
| Unikalne identyfikatory stron | 26 131 |
| Rekordy z identyfikatorem Steam | 25 485 |
| Rekordy z identyfikatorem Steam i gatunkami | 25 483 |
| Offset / liczba wyników źródłowych Steam | 30 298 / 30 298 |

Liczba wyników źródłowych Steam nie jest liczbą unikalnych gier Boreal: parser wybiera odpowiednie rekordy, a katalog łączy je z raportami AppleGamingWiki.

## Przepływ i diagnoza

1. `ContentView` przekazuje tekst wyszukiwania i obsługuje nawigację do szczegółów.
2. `BorealStore` utrzymuje katalog źródłowy, chwilowe wyniki wyszukiwania Steam i katalog prezentacyjny. Metadane i ceny mają osobne limity pamięci.
3. `DiscoveryFilters.project` przygotowuje wyniki poza głównym aktorem. Już przed tą zmianą działały anulowanie starszych projekcji i wyliczanie punktacji przed sortowaniem.
4. `DiscoveryView` przekazywał jednak wszystkie wyniki do `ForEach`, umieszczonego w zagnieżdżonych stosach i siatkach. `LazyVGrid` ogranicza materializację kart, lecz sam nie usuwa kosztu identyfikacji całej kolekcji ani problemów cyklu życia zagnieżdżonej stopki.
5. Kafelki niezależnie pobierały pełne metadane, okładki i opcjonalne ceny. Uzupełnianie metadanych podnosiło rewizję katalogu, co uruchamiało kolejne projekcje.

Najważniejszy problem to suma pracy: rosnący katalog, stopka uruchamiająca następne pobrania, zbędne metadane kart i ponowna projekcja całego zbioru. Sama liczba rekordów nie uzasadniała natychmiastowej migracji do bazy danych.

## Znalezione problemy i naprawy

| Waga | Problem przed zmianą | Wprowadzona korekta |
| --- | --- | --- |
| Wysoka | Każdy układ katalogu przekazywał dziesiątki tysięcy rekordów do `ForEach`. | Katalog nadal jest w pełni przeszukiwany, lecz siatka/lista otrzymuje do 60 wyników bieżącej strony. |
| Wysoka | `.onAppear` stopki mogło uruchamiać kolejne pobranie przy pojawieniu się jej kontenera. Aktualizacja katalogu ponownie tworzyła warunki dla doładowania. | Pobranie następnej strony Steam wymaga użycia przycisku. Paginacja lokalnych wyników nie uruchamia sieci katalogu. |
| Wysoka | Karty Steam z gotowymi gatunkami i artworkiem nadal pobierały pełne opisy. | Karta pobiera metadane tylko przy brakującym identyfikatorze lub gatunkach. Pełny opis pozostaje częścią ładowania szczegółów. Start pobierania karty jest opóźniony o 150 ms. |
| Wysoka | Każda partia metadanych zwiększała rewizję, nawet gdy katalog nie zmienił się semantycznie. | Równy katalog nie jest ponownie publikowany i nie zwiększa rewizji. |
| Wysoka | Ponowne budowanie katalogu z surowego źródła traciło uzupełnienia po eksmisji pełnych metadanych z cache 128 wpisów. | Lekkie pola są zachowane w katalogu źródłowym. Wyniki wyszukiwania również otrzymują dostępne uzupełnienia. |
| Wysoka | Odświeżenie z działającym AppleGamingWiki zastępowało dotychczasowe dane Steam pierwszą świeżą stroną sklepu. | Zachowane są wcześniej odkryte rekordy Steam z deklaracją macOS. Pierwsza świeża strona jest z nimi scalana. |
| Wysoka | Filtr konkretnej metody Windows wymagał `Perfect`/`Playable`. `Wine + Unplayable` było logicznie niemożliwe. | Metoda wymaga znanego raportu, a filtr oceny może wybrać także `Runs`, `Menu` lub `Unplayable`. |
| Średnia | Filtr `Unknown` w całym katalogu korzystał z listy, która już usuwała nieznane oceny. W innych zakresach dowolna nieznana metoda mogła powodować dopasowanie mimo obecnego raportu. | `Unknown` oznacza brak znanego raportu w aktualnym zakresie. Filtr obecności raportu korzysta z tego samego zakresu. |
| Średnia | Scalanie rozpoznawało ID Steam i tytuł, ale nie samą tożsamość strony. Zmieniony tytuł mógł prowadzić do powtórnego dodania tego samego ID strony. | Tożsamość strony jest sprawdzana jako pierwsza. Remisy sortowania rozstrzyga ID. |
| Średnia | Okładki pobierane przez zadania odłączone mogły kontynuować pracę po zniknięciu wszystkich odbiorców. Kolejka slotów nie obsługiwała anulowania. | Wspólne pobranie ma zbiór odbiorców. Ostatni znikający odbiorca anuluje zadanie; anulowany wpis może opuścić kolejkę sześciu slotów. |
| Średnia | Po błędzie Steam usługa mogła próbować pobrać artykuł Wiki na podstawie URL Steam. | Fallback Wiki jest ograniczony do wpisów pochodzących z Wiki. |
| Średnia | Nieudane otwarcie szczegółów kończyło się komunikatem bez dalszej akcji. | Dostępne są ponowienie i link do rzeczywistej strony źródłowej. |
| Średnia | Poziomy pasek zapisanych gier używał zwykłego `HStack`. | Używa `LazyHStack`. |

## Zmiany UI/UX

- Strony po 60 wyników działają zarówno w siatce, jak i liście.
- Użytkownik widzi całkowitą liczbę dopasowań, aktualny zakres oraz liczbę stron.
- Sterowanie stronami jest dostępne nad i pod wynikami. Numer można wpisać bezpośrednio i zatwierdzić Return; błędny numer jest normalizowany do dostępnego zakresu.
- Filtry wracają na pierwszą stronę. Zmiana strony przewija do paska filtrów, aby przypięty nagłówek nie zasłaniał początku wyników.
- Pobranie nowych rekordów sklepu jest oddzielną akcją od przejścia na następną stronę lokalnych wyników.
- Lokalne przeliczanie wyszukiwania ma 180 ms opóźnienia; istniejące opóźnienie żądania Steam pozostaje 400 ms. Starsze zadania są anulowane.
- Nowe akcje i komunikaty mają lokalizację polską.

## Weryfikacja

Kompilacja Debug całego schematu `Boreal`, dla macOS i bez podpisywania, zakończyła się `BUILD SUCCEEDED`. Początkowe uruchomienie w sandboxie nie mogło uruchomić makr SwiftUI/Observation; kompilacja poza tym ograniczeniem zakończyła się powodzeniem. Sprawdzono także `git diff --check` i poprawność JSON katalogu lokalizacji.

Pomiar projekcji wykonano osobnym zoptymalizowanym programem Swift na zamrożonej kopii rzeczywistego cache. Program używał kodu filtrowania i sortowania wyodrębnionego z aktualnego `Discovery.swift`, z minimalnymi definicjami modeli bez UI. Czas obejmuje projekcję po dekodowaniu JSON; nie obejmuje renderowania, obrazu, sieci ani uruchomienia aplikacji.

| Operacja | Dopasowania | Czas jednego pomiaru |
| --- | ---: | ---: |
| Wszystkie gry, kolejność rekomendowana | 26 131 | 147 ms |
| Wyszukiwanie `witcher` | 5 | 24 ms |
| Mac, brak znanego raportu | 25 485 | 142 ms |

Wcześniejszy pomiar tego samego rozmiaru katalogu dał 118 ms dla całości i 23 ms dla `witcher`. Rozrzut wskazuje, że nie należy traktować tych wartości jako gwarantowanej latencji. Niezależnie od rozmiaru całej projekcji do widoku trafia najwyżej 60 kart katalogu plus ewentualne cztery rekomendacje.

Nie dodawano ani nie uruchamiano testów jednostkowych prostych elementów interfejsu. Nie uruchamiano nowej aplikacji nad istniejącą biblioteką użytkownika. Płynność przewijania, wygląd na żywo i błędy zewnętrznych API w nowej kompilacji nie zostały zmierzone; wynik kompilacji i pomiar projekcji nie zastępują tych obserwacji.

## Pozostające ograniczenia funkcjonalności

- Katalog łączy raporty Wiki i gry macOS ze Steam; nie jest kompletnym katalogiem wszystkich gier Windows. Brak raportu nie potwierdza działania ani awarii.
- Wyszukiwanie internetowe tytułu/dewelopera pobiera do jednej strony Steam po 100 wyników. Lokalna wyszukiwarka działa na całym zapisanym katalogu, lecz nowe wyniki internetowe mogą być niepełne.
- Ręczne doładowanie ogólnego katalogu jest ukryte podczas wyszukiwania. Przy aktywnych filtrach może pobrać stronę, która nie doda żadnego pasującego wyniku; dane źródłowe są filtrowane dopiero lokalnie.
- Offset Steam jest pozycją w zmiennym katalogu. Odświeżenie rozpoczyna go od świeżej pierwszej strony, zachowując znalezione wcześniej rekordy i deduplikując kolejne strony. Zachowanie dawnych rekordów nie potwierdza ich dzisiejszej dostępności w sklepie.
- Parsowanie HTML zależy od formatu stron źródłowych. Obsługa błędu i fallback chronią dostępność widoku, ale nie zapewniają kompletności danych.
- Ceny są opcjonalne. Nadal wymagają skonfigurowanego IsThereAnyDeal; podsumowania są pobierane dla widocznych kart z limitem czterech operacji. Nie sprawdzano na żywo cen, zmiany regionu ani zachowania limitów API.
- Samo ponowienie szczegółów nie zapewni dopasowania tytułu, którego nie ma w jednoznacznym rekordzie Steam. Link do źródła daje w takim przypadku dalszą drogę.

Główne poprawki są w `Boreal/Discovery.swift` i `Boreal/BorealStore.swift`; tłumaczenia w `Boreal/Localization/Localizable.xcstrings`. Opis przepływu w `Documentation/Discovery.md` został zaktualizowany do obecnego zachowania.
