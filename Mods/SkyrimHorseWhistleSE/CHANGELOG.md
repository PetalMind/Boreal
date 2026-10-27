# Changelog

## 1.2.3

- Przeniesiono konfigurację do nowego prywatnego zadania MCM z oficjalnym aliasem SkyUI; usuwany jest wyłącznie dawny pusty wpis menu.

## 1.2.2

- Naprawiono puste menu konia zapisane w rejestrze SkyUI: odtwarzanie inicjalizacji MCM i ponowna rejestracja wyłącznie tego menu.

## 1.2.1

- Zapisana blokada powtarzania gwizdu nie blokuje przywołania po ponownym uruchomieniu gry.

## 1.2.0

- Rozbudowano MCM: zmiana i wyłączenie przypisania, mysz/pad, przywracanie G i potwierdzanie konfliktu klawiszy.
- Dodano własny dwutonowy dźwięk gwizdania, głośność, przełącznik i odsłuch w MCM.
- Ustawienia zapisują się w grze; menu odświeża się także przy aktualizacji istniejącego zapisu.
- Ograniczono powtarzanie gwizdu do jednego użycia na 1,5 sekundy.
- Źródłem wersji jest manifest.json; metadane instalatora są generowane przy budowie.

## 1.1.2

- Po inicjalizacji i wczytaniu zapisu alias gracza uruchamia także rejestrację konfiguracji MCM przez SkyUI OnGameReload.
- Poprawiono stałą kierunku układania opcji zgodnie z interfejsem SkyUI.

## 1.1.1

- Przywracanie działania skryptu po wczytaniu zapisu i otwarciu MCM.
- Dodano plik SEQ uruchamiający zadanie moda w istniejących zapisach.
- Poprawiono strukturę komórki zawierającej znacznik konia oraz typ zmiennej klawisza gwizdu.

## 1.1.0

- Zastąpiono własną ikonę wbudowanym znacznikiem stajni Skyrim.
- Usunięto wymaganie CoMAP.

## 1.0.0

- Dodano przywoływanie ostatnio dosiadanego konia edytowalnym klawiszem MCM.
- Dodano ruchomy znacznik konia na mapie i kompasie z ikoną CoMAP.
- Dodano CoMAP i SkyUI jako wymagania instalatora.
