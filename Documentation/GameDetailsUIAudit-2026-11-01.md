# Audyt interfejsu karty gry — 2026-11-01

Zakres: `StoreGameDetailView`, wspólny widok szczegółów gier biblioteki i odkrywania. Zastosowane umiejętności: `swiftui-patterns`, `axiom-swiftui` (układ adaptacyjny), `macos-app-design`. Audyt źródeł oraz poprawki prezentacji; bez zmian usług, danych, dostępności funkcji i wykonywanych operacji.

| Przed | Po | Efekt dla użytkownika |
| --- | --- | --- |
| `.preferredColorScheme(.dark)` na całym widoku; granatowe gradienty kart | Dziedziczenie wyglądu aplikacji, `controlBackgroundColor`, `separatorColor`; ciemna paleta ograniczona do nagłówka z grafiką | Czytelna treść w jasnym i ciemnym motywie, spójna z resztą aplikacji |
| Poziomy `ScrollView` zakładek, odstępy 28 pt | `ViewThatFits`: rząd albo adaptacyjna siatka z kolumnami min. 144 pt, odstępy 4 pt | Sekcje pozostają widoczne przy zwężaniu okna; bez poziomego przewijania zakładek |
| Mały obszar etykiety zakładki | Min. 44 × 44 pt, akcent, podkreślenie i cecha dostępności zaznaczenia | Wybór sekcji widoczny również niezależnie od koloru; standardowa obsługa przycisków |
| Stały tytuł 28 pt i karty statystyk o wysokości dokładnie 76 pt | Semantyczne `largeTitle`, minimalna wysokość 76 pt bez limitu maksymalnego, zawijane podpisy | Dłuższe teksty mają miejsce w pionie |
| Etykiety metryk wymuszają pełną szerokość | Zawijanie etykiet przy ograniczonej szerokości | Metadane mieszczą się lepiej w bocznej kolumnie |
| Margines 14 pt, część wnętrz 14 pt; ikony nagłówka 40 pt | Margines min. 16 pt, wnętrza kart 16 pt; ikony 44 pt | Spójniejszy rytm odstępów i większe cele kliknięcia |
| Własne wtórne przyciski z cyjanowym tekstem | Systemowe przyciski `.bordered`, rozmiar `.large`; etykieta dostępności menu akcji | Natywne stany interakcji i wygląd zgodny z motywem |

Zachowano istniejące stany ładowania, braku danych, błędów, odłączenia konta i niedostępnego woluminu. Zachowano wszystkie warunkowo dostępne sekcje, potwierdzenia operacji destrukcyjnych oraz obsługę ograniczenia ruchu. Nie dodawano wskaźników ani funkcji bez oparcia w danych.

## Weryfikacja

- Sprawdzanie typów i kompilacja źródeł aplikacji Debug arm64: zakończone bez błędów źródeł. Istniejące ostrzeżenia współbieżności w `GameModManaging` i `ReliabilityServices` pozostają poza zakresem.
- Pełny build: **niepotwierdzony**. Uruchomiono `xcodebuild` przez wymagany `/Users/dominik/.codex/bin/codex-build`. Po wielominutowym oczekiwaniu linkera w systemowym stanie `U`, przy praktycznie zerowym czasie CPU, zatrzymano wyłącznie własne procesy. Xcode zakończył próbę komunikatem `BUILD INTERRUPTED`. Nie jest to pozytywny wynik builda ani dowód błędu źródeł.
- Swift Format lint: kod wyjścia 0; 408 ostrzeżeń stylu w istniejącym `StoreGameDetailView`, wobec 411 w tym pliku z HEAD. Bez zmiany formatowania całego pliku. Nowy `StoreGameDetailTabBar`: lint `--strict` bez ostrzeżeń. Konfiguracja tymczasowa: 4 spacje, limit 160 znaków.
- `git diff --check`: bez błędów.
- Podgląd paska zakładek: **niezweryfikowany**. Próba zbudowania małego podglądu przez `codex-build -- xcrun swiftc` również zatrzymała się w oczekiwaniu systemowym `U`, tym razem podczas wyszukiwania narzędzi Xcode; zatrzymano własne procesy. Nie wygenerowano zrzutów. Nie potwierdzono wyglądu przy 360/768/1024/1440 pt, jasnym/ciemnym motywie, największym tekście, VoiceOver ani zwiększonym kontraście w runtime.
- Wersja w `Boreal.xcodeproj/project.pbxproj`: 1.0.24, build 25; wpis w `CHANGELOG.md`. Nie wykonano commita, ponieważ instrukcje wymagają zielonego pełnego builda przed commitem.
