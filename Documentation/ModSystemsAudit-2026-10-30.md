# Audyt systemów modów — 2026-10-30

## Zakres i metoda

Przegląd źródeł wspólnego przepływu UI → BorealStore → GameModManaging → adapter → profile/staging/deployment, obejmujący Skyrim SE, GTA SA, GTA SA DE, Dragon Age: Origins, Wiedźmina 2 i Wiedźmina 3. GTA IV ma osobny przepływ XLiveLess; uwzględniono jego blokadę operacji, bez zmiany instalatora.

Zastosowano lokalne instrukcje `swiftui-patterns`, `axiom-swiftui` z referencją `skills/architecture.md` i `macos-app-design`. Dodatkowy `axiom-audit-swiftui-architecture` wskazany przez router nie jest dostępny w instalacji. Nie instalowano zależności. Przegląd opiera się na kodzie; nie wykonuje operacji na rzeczywistych instalacjach gier.

## Potwierdzone problemy i poprawki

| Priorytet | Problem | Poprawka |
| --- | --- | --- |
| P1 | Każdy adapter tłumił błąd odczytu `deployment.json`, uznając wdrożenie za puste. Kolejne wdrożenie mogło utracić wiedzę o właścicielach i kopiach oryginałów. | `ModProfileStorage.loadDeployment`: tylko brak pliku oznacza puste wdrożenie; błąd odczytu/dekodowania, obcy identyfikator gry i nieobsługiwany schemat przerywają operację. Wszystkie adaptery korzystają ze wspólnej reguły. |
| P1 | Usunięcie moda w Skyrim, GTA SA, GTA SA DE i Wiedźminie usuwało staging/archiwum przed zapisem profilu i niezależnie od innych profili. | Najpierw zapis profilu, następnie wspólne sprawdzenie referencji we wszystkich pozostałych plikach profili. Nieczytelny profil zachowuje pakiet. DAO korzysta z tej samej reguły. Usuwanie ograniczono do podkatalogów Archives/Staging; ścieżki spoza magazynu i dowiązania prowadzące poza niego są odrzucane. |
| P1 | Częściowe pokrycie plików z jednym modem wystarczało do rozpoznania archiwum jako jego aktualizacji. | Po nieudanym dopasowaniu nazwy wymagane jest identyczne, jednoznaczne pokrycie wszystkich ścieżek pakietu. Sama kolizja plików nie oznacza aktualizacji. |
| P2 | Ładowanie biblioteki nie wykluczało instalowania, usuwania, wdrażania lub edycji profilu. Starszy wynik mógł zastąpić nowszy stan. | Wspólna blokada na poziomie gry obejmuje ładowanie i wszystkie wejścia mutujące profil. Odświeżanie po błędzie zaczyna się po zwolnieniu blokady operacji. |
| P2 | Zapis udanego stagingu i błąd automatycznego wdrożenia pierwszej instalacji pozostawiały stary stan UI. | Po błędzie instalacji odczytywany jest rzeczywiście zapisany profil dla każdego rodzaju instalacji. Analogiczna synchronizacja po błędzie usuwania. |
| P2 | Wskaźnik aktywnego profilu zapisywano przed jego odczytem. | Aktywacja następuje dopiero po udanym odczycie. |
| P2 | Wszystkie wpisy brakujących masterów miały identyczny, dosłowny identyfikator tekstowy. | Interpolacja nazw plugin/master daje odrębne identyfikatory dla wierszy SwiftUI. |

## Architektura po zmianie

- `ModsView.swift`: istniejący interfejs, wybór, filtry i prezentacja; bez zmiany obsługiwanych opcji.
- `BorealStore.swift`: koordynacja asynchronicznych operacji i publikacja rzeczywistego stanu.
- `GameModManaging.swift`: kontrakt usług modów, niezależny od konkretnego adaptera.
- `ModModels.swift`: typy domenowe, profile, manifesty, stan i walidacja pluginów.
- `ModIdentity.swift`: identyfikacja pakietów i aktualizacji.
- `ExternalModDiscovery.swift`: wspólna reprezentacja i scalanie modów wykrytych poza Boreal.
- `ModConflictResolver.swift`: wspólne reguły konfliktów i fingerprint profilu.
- `SkyrimModAdapter.swift`: wykrywanie gry, ścieżki i metadane pluginów Bethesda.
- `ModProfileStorage.swift`: wspólne zabezpieczenia odczytu manifestu i zwalniania pakietów.
- Istniejące managery: instalowanie/wdrażanie właściwe dla danej gry, bez przenoszenia tej logiki do SwiftUI.

Nie zmieniano formatów zapisanych danych ani minimalnej wersji systemu. Wiedźmin 3 zachowuje osobne reguły konfliktów i ustawień, korzystając z istniejącej wspólnej usługi instalacji Wiedźmina.

## Granice i dalszy dług

To audyt źródeł i wybranych zabezpieczeń, nie certyfikacja wszystkich formatów archiwów i runtime. Instalowanie, aktualizowanie i usuwanie na rzeczywistych grach, przerwanie procesu w połowie wdrożenia, pełny rollback po błędzie dysku i współbieżność z zewnętrznym menedżerem modów pozostają niezweryfikowane. Istniejące mechanizmy rollbacku nadal używają operacji best effort. Nie przebudowywano całego mechanizmu transakcji ani wszystkich zduplikowanych funkcji archiwów/persistencji. Pliki pakietów są celowo zachowywane, gdy nie można wykluczyć referencji z uszkodzonego profilu.

## Weryfikacja

- Build Debug macOS arm64 bez podpisywania: **PASS**. `xcodebuild` uruchomiony przez `/Users/dominik/.codex/bin/codex-build`; kompilacja obejmuje sprawdzanie typów aplikacji.
- Ścisły Swift Format lint siedmiu nowych plików: **PASS**, zero ostrzeżeń. Tymczasowa konfiguracja dopasowana do repozytorium: 4 spacje, 160 znaków.
- Swift Format lint sześciu edytowanych istniejących plików: kod wyjścia **0**, 2093 ostrzeżenia stylu. Nie jest to czysty lint całego repozytorium; nie wykonywano masowego formatowania poza zakresem.
- `git diff --check`: **PASS**. Porównanie inwentarza typów przed i po wydzieleniu zachowuje wszystkie istniejące typy.
- Build zgłasza ostrzeżenia istniejących usług (m.in. izolacja aktora, niezmieniana zmienna) i pominięcie biblioteki `winemac.so` x86_64 dla celu arm64. Bez błędów kompilacji/linkowania.
- Brak testów runtime na prawdziwych instalacjach i brak nowo utworzonych testów. Nie zmieniano plików gier.
- Wersja: **1.0.22**, build **23**; konfiguracja wersji w `Boreal.xcodeproj/project.pbxproj`, wpis w `CHANGELOG.md`.
