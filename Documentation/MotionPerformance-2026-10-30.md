# Animacje i wydajność interfejsu — 2026-10-30

## Wprowadzone zmiany

- `BorealMotion.swift`: wspólne czasy reakcji — naciśnięcie 120 ms, hover 160 ms, kontrolki 200 ms, zmiana stanu 240 ms, panel 280 ms, nawigacja 320 ms, okładka 360 ms. Sprężyny nawigacji nie mają odbicia; natywne sprężyny zachowują ciągłość przy zmianie celu. Przewijanie, wejście kontrolera i postęp mają własne wspólne parametry.
- `Components.swift`: kliknięcie ulubionych wykonuje akcję natychmiast. Usunięto opóźnienie 80 ms i trzy planowane bloki animacji. Symbol serca korzysta z efektów systemowych. Pulsowanie aktywności łagodnie wraca do początku i zatrzymuje się po zniknięciu widoku.
- `ContentView.swift`: pokazanie szczegółów czeka na zakończenie animacji okładki. Dotychczasowy timer 160 ms usuwał połączenie geometrii jeszcze podczas ruchu. Sprawdzanie identyfikatora i fazy chroni przed spóźnionym zakończeniem po użyciu Wstecz.
- `GameActionStyles.swift`, `LibraryView.swift`, `DiscoveryViews.swift`, `ConsoleModeView.swift`: ujednolicone parametry reakcji; wyłączone powiększanie i zmniejszanie elementów przy ograniczeniu ruchu. Hover w bibliotece nie nakłada już szerokiej transakcji animacji na całe poddrzewo karty.
- `DownloadsView.swift`, `EnvironmentsView.swift`, `StoreGameDetailView.swift`: rozwijanie używa wspólnej animacji, a ograniczenie ruchu usuwa przesunięcia, skalowanie i opóźnione kaskady.
- `LibraryProjectionCache.swift`, `LibraryProjectionRequest.swift`: pamięć filtrowanych i posortowanych wyników biblioteki oraz trybu konsolowego. Wynik jest unieważniany przez zmiany źródłowych aplikacji, gier, instalacji, ukrytych elementów i odpowiednich filtrów. Ulubione są częścią klucza, gdy wpływają na wynik. Filtr daty „ostatnie” w bibliotece celowo pomija pamięć wyniku, aby zachować aktualny próg czasu.
- `LibraryPresentation.swift`: pominięcie normalizacji tekstu każdej gry, gdy zapytanie wyszukiwania jest puste.
- `Controller2DView.swift`, `Controller3DView.swift`: wspólny czas interpolacji wejścia. Podgląd 3D zapamiętuje referencje węzłów po utworzeniu sceny i pomija transakcję, gdy stan kontrolera się nie zmienił.

## Pomiar i granice wniosków

Przed zmianami pobrano trzysekundową próbkę CPU działającej wersji 1.0.19. Próbka dotyczyła spoczynku i pokazała oczekiwanie głównego wątku w pętli zdarzeń. Nie jest dowodem płynności przewijania ani pomiarem FPS.

Tymczasowy program porównawczy używał rzeczywistego modułu Boreal i 1000 sztucznych rekordów gry GOG, bez odczytu lub zapisu biblioteki użytkownika. Mierzył 100 powtórzeń tej samej projekcji. Dane wejściowe i checksum pozostawały takie same; obie wersje modułu były zbudowane w konfiguracji Debug. Pomiary obejmują wyłącznie kod projekcji, nie renderowanie i nie płynność całej aplikacji.

| Wariant | Czas 100 powtórzeń | Checksum |
| --- | ---: | ---: |
| 1.0.19, bez pamięci wyniku | 0,906369 s | 100000 |
| 1.0.20, bez pamięci wyniku, pominięta zbędna normalizacja | 0,115616 s | 100000 |
| 1.0.20, trafienie w rozgrzaną pamięć wyniku | 0,000057 s | 100000 |

To pojedynczy pomiar kontrolny. Ostatni wiersz dotyczy ponownych odczytów identycznych danych i filtrów; pierwsze przeliczenie oraz zmiana danych nadal wykonują potrzebną pracę.

## Weryfikacja

- Build Debug arm64 i pełne sprawdzenie typów: **PASS**, macOS 27 SDK, przez `codex-build`. Aplikacja ma lokalny podpis ad hoc ze stabilnym identyfikatorem `STDMSolution.Boreal`, wymagany do istniejącej zakładki lokalizacji danych.
- Rygorystyczny Swift Format: **PASS** dla wspólnych parametrów ruchu, obu plików pamięci projekcji, stylów akcji i podglądu 3D. Pozostałe edytowane pliki przechodzą lint bez błędów, lecz zachowują istniejące ostrzeżenia formatowania.
- Tymczasowy program porównawczy: **PASS** zgodności wyników z bezpośrednią projekcją, zmiany wyszukiwania, sortowania, źródła, dostępności, kompatybilności, producenta, ulubionych, ukrytych elementów i danych gry; dodatkowo wszystkie zakresy konsoli oraz zmiana ulubionych. Program nie został dodany jako test do repozytorium.
- `git diff --check`: **PASS**.
- Uruchomiono podpisany build 1.0.20 (21) i potwierdzono główne okno „Biblioteka” procesu z nowego artefaktu.
- Nie wykonano porównawczego pomiaru klatek ani reprezentatywnej sesji Instruments ze sterowaniem całym interfejsem. Zmniejszony koszt projekcji nie jest deklaracją określonego FPS. Płynność podłączonego fizycznego kontrolera nie została zmierzona.
- Wersja **1.0.20**, build **21**; konfiguracja w `Boreal.xcodeproj/project.pbxproj`, wpis w `CHANGELOG.md`.
