# Synchronizacja Wine: ESync i MSync

Sekcja „Wydajność” w konfiguratorze gry zapisuje preferencje ESync i MSync w profilu. Dostępność zależy od wybranego Wine, a nie od renderera DXMT, DXVK lub D3DMetal.

## Wykrywanie

Podczas odczytu lub importu środowisk `RuntimeManager` ponownie sprawdza ich pliki. Zmienna `WINEESYNC` lub `WINEMSYNC` musi występować zarówno w wybranym `wineserver`, jak i w bibliotece klienta `ntdll`. Wyszukiwanie obejmuje biblioteki w `lib` i `lib64`, w katalogu pakietu oraz względem rzeczywistego pliku Wine. Historyczne flagi w metadanych nie zastępują tego sprawdzenia.

Wykrycie kodu obsługi nie jest potwierdzeniem działania konkretnej gry ani pomiarem wydajności.

## Stosowanie ustawień

`WineProcessEnvironment.applySynchronization` wyznacza wspólne wartości dla tworzenia i konfiguracji prefiksu oraz uruchamiania gier i narzędzi:

- Obsługiwany i włączony MSync: `WINEMSYNC=1`; obsługiwany ESync: `WINEESYNC=0`.
- Wyłączony lub niedostępny MSync: obsługiwany ESync otrzymuje `WINEESYNC=1` lub `0`, zgodnie z preferencją.
- Obsługiwany i wyłączony MSync: `WINEMSYNC=0`.
- Zmienne nieobsługiwanych mechanizmów są usuwane, również po scaleniu konfiguracji dostawcy gry.

Pierwszeństwo MSync odpowiada implementacji [wine-msync](https://github.com/marzent/wine-msync/blob/main/msync-staging.patch). Zmiana obowiązuje przy nowej sesji Wine, po zakończeniu wszystkich procesów Windows korzystających z tego prefiksu.

## Interfejs i brak obsługi

Niedostępny przełącznik jest wyłączony i pokazuje stan nieaktywny. Zapisana preferencja pozostaje w profilu, aby wróciła po wybraniu Wine z obsługą danego mechanizmu. Komunikat wskazuje brakujący mechanizm i możliwość importu odpowiedniej wersji Wine.

Boreal nie modyfikuje istniejących binariów Wine w miejscu. MSync wymaga kompilacji Wine zawierającej tę implementację. Podczas prac 1 października 2026 sprawdzono lokalne pakiety: GPTK zawierały znaczniki ESync, a żaden z zainstalowanych pakietów nie zawierał znaczników MSync po stronie serwera i klienta.

## Przygotowanie Wine z MSync w aplikacji

Ustawienia → środowiska Wine → „Wine z MSync” → „Przygotuj Wine z MSync…” uruchamia osobny proces przygotowania:

1. Domyślnie automatyczne przygotowanie bibliotek x86_64. Opcjonalnie można wyłączyć automat i wskazać własny katalog bibliotek.
2. Sprawdzenie narzędzi Xcode, Bison, Flex, Make, pkg-config i obu kompilatorów MinGW. Na Apple silicon sprawdzana jest też Rosetta. Tryb automatyczny pobiera źródła GMP 6.3.0, Nettle 3.10.2, GnuTLS 3.8.13 i FreeType 2.14.3 z przypiętymi sumami SHA-256. Buduje biblioteki i nagłówki x86_64 w prywatnym katalogu, a następnie sprawdza architekturę bibliotek. GnuTLS używa dołączonych źródeł libtasn1 i libunistring.
3. Pobranie źródeł Wine 9.15 i poprawki `msync-devel.patch` z rewizji `be7f3e2ff40670018cd7aa9042bad487fa7a83ec`. Oba pliki mają przypięte i sprawdzane sumy SHA-256.
4. Sprawdzenie poprawki bez modyfikowania źródeł, nałożenie jej bez dopasowania przybliżonego, konfiguracja WoW64, kompilacja i instalacja do katalogu roboczego.
5. Sprawdzenie obecności MSync w serwerze i kliencie oraz jego rzeczywistego startu z `WINEMSYNC=1` w jednorazowym prefiksie. Import wymaga komunikatu serwera `msync: up and running.` i poprawnego kodu zakończenia wineboot.
6. Standardowy import i weryfikacja środowiska Wine. Dopiero wtedy pakiet pojawia się na liście zainstalowanych środowisk.

Nowy pakiet jest eksperymentalnym Wine 9.15 z MSync, bez D3DMetal i GStreamera. Numer wersji wynika ze sprawdzonej zgodności z opublikowaną poprawką; ta receptura nie przenosi jej na Wine 11 ani GPTK. Źródła Wine z licencją, poprawka i opis kompilacji pozostają w pakiecie `Contents/Resources/MSync-Sources`. Tryb automatyczny dołącza biblioteki dynamiczne do `wine/lib`, zachowuje ich aliasy i zmienia odwołania do bibliotek na `@loader_path`. Źródła zależności również pozostają w pakiecie. Procesy konfiguracji i uruchamiania używają bibliotek z wybranego pakietu Wine. W trybie ręcznym własne biblioteki muszą pozostać w wybranym katalogu.

Etapy są pokazywane w ustawieniach bez szacowanych procentów. Logi trafiają do `Application Support/Boreal/RuntimeBuilds/MSync-<UUID>/Logs`. Źródła i pliki kompilacji trafiają do osobnego katalogu tymczasowego `Boreal-MSync-<UUID>`, aby ścieżki źródeł nie zawierały spacji. Błąd zachowuje katalog roboczy do diagnozy; po udanym imporcie jest on usuwany, a logi pozostają. Próba startu MSync ma limit 120 sekund. Proces nie wymaga uprawnień administratora i nie instaluje narzędzi ani bibliotek systemowych. Braki narzędzi są zgłaszane przed pobieraniem źródeł. Diagnostyka zapisuje `preflight.log` także wtedy, gdy przygotowanie zatrzyma się przed pierwszym procesem. Błędy przygotowania MSync mają własny typ i nie są opisywane jako błędy importu istniejącej aplikacji Wine.

Po zakończeniu przygotowania należy wybrać „Wine MSync” w konfiguracji środowiska gry. Aplikacja nie przełącza istniejących gier automatycznie.

Walidacja naprawy: produkcyjny kod przygotował GMP 6.3.0, Nettle 3.10.2, GnuTLS 3.8.13 i FreeType 2.14.3 jako biblioteki x86_64. Sprawdzono pakowanie, relokację, aliasy bibliotek i ich rzeczywiste ładowanie z katalogu pakietu. Program x86_64 potwierdził FreeType 2.14.3 oraz GnuTLS 3.8.13 po inicjalizacji obu bibliotek. Konfiguracja Wine 9.15 z przypiętą poprawką MSync, FreeType, GnuTLS i WoW64 zakończyła się powodzeniem. Kompilacja Boreal przeszła. Pełnej kompilacji nowego Wine i sesji gry z MSync nie wykonano w tej weryfikacji.
