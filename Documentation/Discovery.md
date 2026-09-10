# Discovery

Discovery to katalog gier, które użytkownik może przejrzeć przed dodaniem ich do biblioteki Boreal. Widok zestawia raporty kompatybilności z AppleGamingWiki z danymi katalogu Steam dla macOS. Nie instaluje gier, nie kupuje ich i nie uruchamia Windowsowego środowiska bez osobnej decyzji użytkownika.

Główne elementy implementacji znajdują się w:

- [`Boreal/Discovery.swift`](../Boreal/Discovery.swift) — modele katalogu, pobieranie danych, `DiscoveryView`, kafelki i ekran szczegółów Discovery;
- [`Boreal/BorealStore.swift`](../Boreal/BorealStore.swift) — stan, zadania asynchroniczne, cache sesji, zapis pozycji i integracja z usługami;
- [`Boreal/ContentView.swift`](../Boreal/ContentView.swift) — wejście z paska bocznego, wyszukiwanie i routing do szczegółów;
- [`Boreal/StoreGameDetailView.swift`](../Boreal/StoreGameDetailView.swift) — wspólny ekran szczegółów używany dla gier z biblioteki i dla pozycji otwartych z Discovery;
- [`Boreal/ITADPriceService.swift`](../Boreal/ITADPriceService.swift) — opcjonalne ceny, oferty i historia cen.

## Wejście do widoku

Po wybraniu **Discovery** w pasku bocznym `ContentView`:

1. ustawia cel nawigacji `SidebarDestination.discovery`;
2. usuwa aktualną ścieżkę szczegółów biblioteki;
3. czyści tekst wyszukiwania Discovery;
4. wyświetla `DiscoveryView` i dodaje do toolbaru wyszukiwarkę z promptem „Search Discovery”.

Wiersz paska bocznego może pokazywać liczbę rekordów z aktualnego katalogu (`trackedCount`). Jest to liczba śledzonych wpisów katalogu, a nie liczba gier zainstalowanych w Boreal.

## Układ widoku

`DiscoveryView` jest przewijalnym widokiem z następującymi sekcjami:

1. nagłówek z profilem bieżącego Maca;
2. podsumowanie katalogu;
3. przełącznik zakresu przeglądania;
4. filtry i sortowanie;
5. opcjonalny pasek informacji o wyszukiwaniu lub źródle danych;
6. karuzela rekomendacji, gdy nie ma aktywnego wyszukiwania;
7. katalog w układzie siatki albo listy;
8. automatyczne doładowywanie kolejnych wyników Steam;
9. informacja o dacie danych albo o użyciu ostatniego zapisanego katalogu.

Przycisk **Data sources** otwiera krótki przewodnik. Wyjaśnia on pochodzenie raportów, metadanych, cen i ograniczenia znaczenia ratingów. Przycisk **Refresh Discovery** uruchamia wymuszone odświeżenie katalogu.

### Profil Maca

Nagłówek wyświetla:

- nazwę procesora albo „Intel Mac”;
- zaokrągloną ilość pamięci fizycznej;
- wersję macOS w formacie `macOS major.minor`.

Dane są odczytywane lokalnie przez `sysctl` i `ProcessInfo`. Profil ma funkcję informacyjną. Nie jest osobnym mechanizmem dopasowania wymagań gry i nie potwierdza, że dany tytuł został uruchomiony na tym konkretnym Macu.

## Zakresy przeglądania

Przełącznik **Browse** ma cztery wartości:

| Zakres | Działanie |
| --- | --- |
| **Recommended** | Pokazuje wszystkie pasujące rekordy, ale wymusza sortowanie rekomendowane. Przy pustym wyszukiwaniu widok może dodatkowo pokazać sekcję „Best compatibility”. |
| **All Games** | Pokazuje wszystkie rekordy katalogu po zastosowaniu pozostałych filtrów. |
| **Mac** | Pokazuje wpisy z natywnym ratingiem, grywalnym ratingiem Rosetta 2 albo deklarowanym wsparciem macOS po stronie Steam. |
| **Windows** | Pokazuje gry, dla których istnieje znany wpis dla CrossOver, Wine albo Parallels. Znany wpis może mieć również status ograniczony, menu-only albo unplayable. |

Sekcja **Best compatibility** jest niezależna od wybranego zakresu: może pojawić się przy pustym wyszukiwaniu, jeśli po bieżących filtrach istnieją gry z co najmniej jednym ratingiem `Perfect`.

W zakresie **Mac** badge rozróżnia trzy sytuacje: `Native macOS` pochodzi z grywalnego ratingu Native, `Rosetta 2` z grywalnego ratingu Rosetta 2, a `macOS` oznacza deklarację wsparcia macOS bez wystarczających danych o architekturze. Boreal nie przedstawia samej deklaracji Steam jako pewnego natywnego Apple Silicon.

W zakresie **Windows** pojawia się dodatkowy filtr **Windows path**. Wartość `All Windows paths` pozostawia wszystkie znane ścieżki. Wybór CrossOver, Wine albo Parallels wymaga już ratingu grywalnego dla konkretnej metody, czyli `Perfect` albo `Playable`.

## Filtry i sortowanie

Filtry są nakładane jednocześnie na każdy rekord:

- **Genre** — lista gatunków jest budowana z gatunków obecnych w aktualnym katalogu; `Not provided` oznacza brak gatunków (`nil` albo pusta tablica);
- **Compatibility** — sprawdza ratingi właściwe dla bieżącego zakresu. Dla `Mac` używany jest rating Native, dla `Windows` — wybrana ścieżka albo wszystkie trzy ścieżki Windows, a dla `Recommended` i `All Games` — wszystkie dostępne ratingi;
- **Store** — `Steam` oznacza obecność `steamAppID`, a `Other / unknown` jego brak;
- **Has compatibility report** — zostawia wpisy, które mają co najmniej jeden rating różny od `Unknown` i `N/A`. Oznacza to obecność raportu źródłowego, a nie test wykonany przez Boreal;
- **Reset filters** — przywraca zakres `All Games`, wszystkie wartości filtrów i sortowania oraz czyści wyszukiwanie. Nie zmienia zapisanego wyboru siatki/listy.

Tekst wyszukiwania dopasowuje tytuł bez rozróżniania wielkości liter. Po zmianie tekstu widok odczekuje 400 ms, aby nie wykonywać żądania dla każdego naciśnięcia klawisza. Jeśli tekst nie jest pusty, wykonywane jest również wyszukiwanie w bieżącym katalogu Steam dla macOS.

Sortowanie ma trzy wartości:

- **Recommended**;
- **Name A–Z**;
- **Name Z–A**.

Wynik rekomendacji jest wyliczany deterministycznie z danych katalogu. Pierwszy rating `Perfect` otrzymuje najwyższą wagę, wcześniejsze metody mają niewielką przewagę, a lepszy `bestRating` poprawia wynik. Artwork nie wpływa na wynik kompatybilności; jest używany dopiero jako tie-breaker przy identycznym wyniku. Nie jest to wynik benchmarku, FPS ani automatycznej walidacji środowiska Wine.

Widok katalogu może być przełączony między siatką i listą. Wybór listy jest przechowywany w `@AppStorage("discoveryListLayout")`, więc pozostaje po ponownym uruchomieniu aplikacji.

## Źródła danych

### AppleGamingWiki

AppleGamingWiki dostarcza główną listę kompatybilności. Usługa:

1. pobiera publiczną stronę master listy;
2. przechodzi przez kolejne strony wskazane przez link `More`;
3. odczytuje tytuł, URL i ratingi dla Native, Rosetta 2, CrossOver, Wine, Parallels oraz Linux ARM;
4. usuwa duplikaty po URL-u i sortuje wyniki po tytule;
5. odrzuca odpowiedź pustą albo podejrzanie krótką — lista musi zawierać co najmniej 100 rekordów.

Model `AppleGamingWikiRating` ma następujące statusy:

| Status źródłowy | Znaczenie w filtrach i UI |
| --- | --- |
| `Perfect` | Najwyższy poziom raportowanej kompatybilności; grywalny. |
| `Playable` | Grywalny według raportu; niższy niż `Perfect`. |
| `Runs` | Uruchamia się, ale z ograniczeniami; nie jest traktowany jako grywalny dla filtra konkretnej ścieżki. |
| `Menu` | Dochodzi do menu, ale nie jest traktowany jako grywalny. |
| `Unplayable` | Raport wskazuje brak grywalności. Nadal liczy się jako znany/testowany rating. |
| `Unknown` | Brak rozstrzygającego raportu. |
| `N/A` | Metoda nie ma zastosowania dla danego wpisu. |

W kafelku pokazywany jest najlepszy raport znaleziony w dostępnych metodach oraz preferowana metoda. W szczegółach można zobaczyć wszystkie dostępne ratingi, wraz z ostrzeżeniem, że są to raporty społecznościowe AppleGamingWiki.

### Steam dla macOS

Steam uzupełnia katalog o żywe wyniki wyszukiwania macOS i metadane sklepu:

- `steamAppID`;
- okładkę;
- gatunki;
- deklarację wsparcia macOS;
- opis, dewelopera i inne metadane używane na ekranie szczegółów.

Pierwsze pobranie katalogu pobiera pierwszą stronę wyników Steam po 100 rekordów i zapisuje `steamOffset` oraz `steamTotal`. Kolejne strony są pobierane automatycznie, gdy niewidoczny element na końcu katalogu pojawi się na ekranie. Mechanizm nie ładuje następnej strony równolegle z innym ładowaniem i zatrzymuje się po osiągnięciu `steamTotal`.

Rekordy Steam są scalane z AppleGamingWiki:

- najpierw po `steamAppID`, jeśli identyfikator już istnieje;
- w przeciwnym razie po znormalizowanym tytule, ale tylko gdy dopasowanie jest jednoznaczne;
- przy scaleniu Steam uzupełnia identyfikator, okładkę, gatunki i flagę wsparcia macOS, nie zastępując raportów kompatybilności.

Wyszukiwanie tytułu korzysta z żywego endpointu Steam. Wyniki są scalane z zapisanym katalogiem lokalnym, dlatego komunikat „combined with local compatibility records” oznacza, że wynik Steam może otrzymać raport z AppleGamingWiki po dopasowaniu rekordu.

### Metadane prezentacyjne

Metadane pojedynczego tytułu są pobierane dopiero wtedy, gdy karta lub ekran szczegółów ich potrzebuje. Usługa próbuje w kolejności:

1. Steam `appdetails`, jeśli znany jest identyfikator;
2. wyszukiwanie Steam po dokładnie znormalizowanym tytule, aby uzyskać identyfikator;
3. API MediaWiki AppleGamingWiki jako fallback.

Metadane obejmują opis, obraz, URL źródłowy, identyfikator Steam, dewelopera i gatunki. Jeśli nie ma opisu ani obrazu, wynik nie jest zapisywany jako poprawne metadane prezentacyjne.

Karty używają następującej kolejności obrazów:

1. obraz nagłówkowy Steam z `steamAppID`;
2. obraz okładki z pobranych metadanych;
3. okładka z rekordu katalogu;
4. lokalny placeholder z nazwą gry.

Pobieranie obrazów korzysta ze wspólnego cache pamięciowego i współdzieli trwające żądanie dla tego samego URL-u. Maksymalny rozmiar obrazu przekazywanego do karty wynosi 560 pikseli.

## Cache i tryb offline

`AppleGamingWikiDiscoveryService` korzysta z trzech plików w katalogu danych Boreal:

```text
~/Library/Application Support/Boreal/Discovery/applegamingwiki.json
~/Library/Application Support/Boreal/Discovery/applegamingwiki-metadata.json
~/Library/Application Support/Boreal/Discovery/applegamingwiki-unavailable.json
```

Własna lokalizacja `Application Support` może być przekazana przez `BorealStore` w testowym albo niestandardowym środowisku.

Zasady ładowania katalogu:

- katalog zapisany lokalnie albo snapshot w bundle jest używany jako fallback;
- świeży katalog jest używany bez żądania sieciowego przez 24 godziny;
- po wygaśnięciu lub przy wymuszonym odświeżeniu AppleGamingWiki i Steam są pobierane równolegle;
- jeśli jedno źródło odpowie, katalog może zostać zbudowany częściowo;
- jeśli źródła są niedostępne, ostatni zapisany katalog jest oznaczany jako `isStale` i pozostaje widoczny;
- jeśli nie ma ani cache, ani snapshotu, a pobieranie się nie powiedzie, widok pokazuje stan błędu z przyciskiem **Retry**.

W stopce widoku pojawia się albo data aktualizacji katalogu, albo komunikat „Showing the last saved catalog.”. Szczegółowe ostrzeżenie o źródle jest dostępne także w panelu **Data sources**.

Cache metadanych ma żywotność 24 godzin. Nieudane wyszukanie metadanych ma osobny negatywny cache przez 15 minut, aby przewijanie katalogu nie powtarzało bez końca tych samych żądań. Jednocześnie maksymalnie cztery pobrania metadanych mogą być obsługiwane przez `BorealStore`.

## Kafelek gry

`DiscoveryGameTile` działa zarówno w siatce, jak i w poziomej liście. Kafelek zawiera:

- artwork i tytuł otwierające szczegóły;
- maksymalnie dwa gatunki;
- etykietę Native, Rosetta 2 albo Windows;
- najlepszy rating lub „Compatibility unknown”;
- raportowaną metodę, jeśli istnieje grywalny raport;
- najlepszą dostępną cenę, stan ładowania albo „Price unavailable”;
- link do strony Steam, jeśli istnieje identyfikator;
- przycisk zapisu pozycji z Discovery.

Przycisk zapisu nie uruchamia zakupu ani instalacji. Przechowuje wybrany rekord jako zainteresowanie użytkownika w `saved-games.json`. W interfejsie stan ten jest opisany jako **Saved**, a nie **In Library**, ponieważ jest to zapisana lista Discovery, odrębna od właściwych rekordów `storeGames` biblioteki. **In Library** jest używane dopiero przez akcję na ekranie szczegółów po faktycznym dodaniu rekordu do biblioteki.

## Ceny i oferty

Ceny są opcjonalne i pochodzą z IsThereAnyDeal. Są ładowane tylko wtedy, gdy w ustawieniach skonfigurowano klucz API. Kraj jest brany z `itadCountryCode`, a niepoprawny kod jest zastępowany regionem systemowym.

Dla tytułu usługa:

1. mapuje identyfikator Steam albo tytuł na identyfikator IsThereAnyDeal;
2. pobiera przegląd bieżącej najlepszej oferty i historycznego minimum;
3. w widoku szczegółów może pobrać pełną listę ofert oraz historię cen;
4. zapisuje przegląd cen w `Discovery/itad-prices.json` na 3 godziny.

Na podstawie relacji ceny bieżącej do minimum historycznego wyświetlany jest opis okazji: `Great price`, `Near historical low`, `Average price` albo `Poor deal`. Brak klucza, błąd sieci i brak oferty są pokazane jako brak danych — nie jako cena zerowa.

Karta szczegółów **Offers** pokazuje sklep, cenę, rabat, platformy, DRM i bezpośredni link do oferty. Historia ma zakresy 3M, 6M, 1Y i All.

## Otwieranie szczegółów gry

Kliknięcie obrazu albo tytułu wywołuje callback z `DiscoveryView`. `ContentView` dodaje trasę `LibraryRoute.discoveryGame(game)` do ścieżki nawigacji.

`DiscoveryGameDetailView`:

1. zapewnia pobranie metadanych prezentacyjnych;
2. próbuje znaleźć jednoznaczny rekord Steam po `steamAppID`, a bez niego po tytule;
3. pobiera aktualną liczbę graczy Steam;
4. przekazuje wynik do wspólnego `StoreGameDetailView` z zachowanym rekordem Discovery.

Jeżeli Steam nie zwróci jednoznacznego rekordu, pojawia się **Game details unavailable**. Boreal nie tworzy wtedy fikcyjnego rekordu tylko po to, aby wypełnić ekran.

### Zakładki szczegółów z Discovery

Dla pozycji otwartej z Discovery widoczne są zależnie od danych:

- **Overview** — cena, podsumowanie kompatybilności, media i pozostałe metadane;
- **Compatibility** — ratingi AppleGamingWiki dla poszczególnych metod, jeśli gra nie jest zadeklarowana jako natywna macOS;
- **Offers** — najlepsza oferta, pełne oferty i historia cen;
- **Files** — tylko gdy istnieje lokalna instalacja albo powiązana aplikacja.

Zakładka **Activity** dotyczy gry już posiadanej w bibliotece i nie jest pokazywana dla samego wpisu Discovery.

W sekcji opisu ekran może dodatkowo sprawdzić obecność tytułu w GOG Revived. Wynik może być: link do strony, sprawdzanie, brak wpisu albo niedostępność usługi. Jest to informacja pomocnicza i nie zmienia źródła głównego rekordu.

## Działania z ekranu szczegółów

Najważniejsza akcja dla nowej pozycji to **Add to Library**. Wykonuje ona `BorealStore.addDiscoveryGameToLibrary`:

- nie dodaje duplikatu, jeśli ten sam provider i `externalID` są już w `storeGames`;
- zapisuje znalezione szczegóły Steam do biblioteki;
- zachowuje pozycję w zapisanych grach Discovery, jeśli nie była wcześniej zapisana;
- zapisuje stan biblioteki i odtwarza dźwięk potwierdzenia.

Po dodaniu do biblioteki podstawowa akcja zmienia się zależnie od realnego stanu gry:

- dla zainstalowanej natywnej wersji macOS — **Play** otwiera lokalną aplikację;
- dla gry powiązanej z aplikacją Windows — używany jest mechanizm uruchamiania Boreal i wybrane środowisko;
- dla wspieranej wersji macOS Steam — Boreal otwiera akcję Steam instalacji albo uruchomienia;
- dla gry Windows-only — użytkownik przechodzi do opcji instalacji lub strony Steam;
- w pozostałych przypadkach dostępne jest **Open in Steam**.

Zakup, logowanie, DRM, pobieranie depotów i zasady instalacji należą do odpowiedniego sklepu. Discovery tylko pokazuje dane i przekazuje użytkownika do właściwej akcji.

## Zapisane pozycje i powiązanie z biblioteką

Zapisane pozycje Discovery są odczytywane przy inicjalizacji `BorealStore` z:

```text
~/Library/Application Support/Boreal/Discovery/saved-games.json
```

Jeżeli użytkownik wróci do głównej biblioteki bez wybranych filtrów źródła, dostępności, kompatybilności i dewelopera oraz nie jest w widoku Favorites, `LibraryView` pokazuje sekcję **Saved from Discovery** z poziomą listą zapisanych gier. Tekst wyszukiwania może dodatkowo zawęzić tę listę. Kliknięcie kafelka otwiera ponownie szczegóły Discovery.

Niezależnie od tego, główna biblioteka może pokazać sekcję **More from <developer> in Discovery**. Pojawia się ona po wybraniu dewelopera z ekranu szczegółów. Boreal wyszukuje wtedy gry tego dewelopera w Steam, a następnie odrzuca tytuły już posiadane po Steam App ID albo po znormalizowanej nazwie.

## Stany i błędy

### Katalog

- `idle` — nic jeszcze nie ładuje katalogu;
- `loading` — trwa pierwsze ładowanie albo odświeżenie; przyciski ładowania są blokowane;
- `loaded` — katalog jest dostępny;
- `failed(message)` — nie udało się pobrać katalogu bez użytecznego fallbacku.

Brak katalogu pokazuje `ContentUnavailableView` z `ProgressView` albo komunikatem błędu i przyciskiem **Retry**. Błąd paginacji jest pokazywany osobno, aby nie ukrywać już wyświetlonych wyników.

### Brak wyników

Jeśli po zastosowaniu wyszukiwania i filtrów nie zostanie żaden rekord, widok pokazuje **No games found** oraz przycisk **Reset filters**. Nie jest to traktowane jako błąd źródła danych.

### Metadane, artwork i ceny

Brak pojedynczego opisu, obrazu, ceny albo oferty pozostaje jawnie pokazany jako placeholder, „Price unavailable” lub komunikat o braku danych. Brak danych opcjonalnych nie usuwa całego kafelka ani nie tworzy wartości zastępczych udających dane źródłowe.

## Snapshot w repozytorium

[`Boreal/DiscoveryCatalog.json`](../Boreal/DiscoveryCatalog.json) i [`Boreal/DiscoveryTags.json`](../Boreal/DiscoveryTags.json) są zasobami bundle używanymi jako lokalny punkt startowy/fallback. Snapshot katalogu jest oznaczony jako potencjalnie nieaktualny i nie powinien być traktowany jako stała liczba dostępnych gier. Przy działającej sieci aplikacja próbuje pobrać nowsze dane AppleGamingWiki i Steam, a aktualny stan sygnalizuje datą lub komunikatem o użyciu cache.

## Granice zaufania do danych

Discovery odpowiada na pytanie „jakie gry i raportowane sposoby uruchomienia warto sprawdzić?”, a nie „czy ta gra na pewno zadziała na tym komputerze?”. W szczególności:

- rating AppleGamingWiki jest raportem społecznościowym;
- wpis Steam z platformą macOS nie potwierdza automatycznie obsługi Apple Silicon ani aktualnego macOS;
- `Playable` wymaga statusu `Perfect` albo `Playable`; dojście do menu jest niewystarczające;
- rekomendacja nie jest wynikiem benchmarku;
- cena może być nieobecna, opóźniona albo zależna od skonfigurowanego regionu;
- dodanie do zapisanych pozycji i dodanie do właściwej biblioteki to dwa różne działania;
- instalacja i uruchomienie następują dopiero po użyciu akcji sklepu albo konfiguracji środowiska.
