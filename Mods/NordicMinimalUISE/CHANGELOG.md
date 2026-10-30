# Changelog

## 1.1.0

- Celownik rozróżnia NoTarget, Target (pierścień), Favor (romb) i natywny wariant Alert (kolor i kreska ostrzegawcza).
- Zastąpiono szybkie pulsowanie nieruchomą kropką z opcjonalnym, łagodnym ruchem.
- Dodano trwałe ustawienia MCM: rozmiar 50–200%, krycie 25–100% i animacja.
- Zachowano natywne oko skradania oraz ukrywanie celownika według trybu HUD i ustawienia gry.
- Wydzielono renderer celownika do Source/Interface/NordicCrosshair.as.
- Manifest odwołuje się do VERSION zamiast przechowywać drugą, nieaktualną wersję.

## 1.0.6

- Nawigacja pod H używa prywatnego czaru o stałym koszcie 0 magicki i nie daje doświadczenia magii.
- Po włączeniu trasa odświeża się co 0,5 sekundy, także podczas jazdy konnej; ponowne H wyłącza nawigację.
- Odświeżanie jest wstrzymane w menu, a nawigacja wyłącza się po wczytaniu zapisu, śmierci lub wyłączeniu skrótu.
- Źródłem wersji moda jest plik VERSION.

## 1.0.5

- Poprawiono nagłówki rekordów ESP do formatu Skyrim SE (44).
- Dodano nowy prywatny rekord uruchamiający HUD w istniejącym zapisie, z zachowaniem ustawień.
- Panel konia jest pozycjonowany względem paska kondycji gracza przed zakotwiczeniem przy krawędzi ekranu.

## 1.0.4

- Panel konia korzysta z aktualnego wierzchowca gracza przez GetMount, zamiast wyłącznie z ostatnio dosiadanego konia.
- Przy ponownej inicjalizacji HUD odnawiane jest ustawienie paneli.

## 1.0.3

- Usunięto kolizję FormID z menedżerem MCM SkyUI; własne rekordy należą do Nordic Minimal UI.
- Poprawiono zapis VMAD i powiązania skryptów menu MCM.
- Dodano plik startowy SEQ oraz ponowną rejestrację MCM po wczytaniu zapisu.

## 1.0.2

- Kropka śledzi aktywny celownik także podczas animacji zbierania przedmiotów.
- Dodano spokojne pulsowanie kropki oraz szybszy, większy puls dla stanu alarmowego.

## 1.0.1

- Zastąpiono krzyżyk celownika małą, nordycką kropką.

## 1.0.0

- Dodano minimalistyczne zanikanie pasków zdrowia, magicki i kondycji.
- Dodano MCM SkyUI do ustawiania czasu zanikania i widoczności pasków oraz kompasu.
- Uspójniono kolory tekstu tematów dialogowych w stonowanej, nordyckiej palecie.
