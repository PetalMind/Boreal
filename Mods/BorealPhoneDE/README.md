# Boreal Phone DE

Mod CLEO Redux x64 dla **Grand Theft Auto: San Andreas – The Definitive Edition**.
Po naciśnięciu `F8` otwiera telefonowy interfejs HUD z:

- **ZAPIS GRY** — otwiera oryginalny ekran zapisu GTA, więc zapis korzysta z
  prawdziwego systemu gry;
- **RADIO** — pozwala wybrać stację i wyłączyć radio. Zmiana stacji działa, gdy
  gracz jest w pojeździe;
- **ZBROJOWNIA** — kategorie broni i kamizelka, saldo postaci, ceny oraz
  ekran potwierdzenia zakupu;
- **ZAMKNIJ** — zamyka telefon.

Interfejs jest inspirowany telefonem z Watch Dogs 2: ciemna obudowa,
geometryczna tapeta, turkusowy kafelek zapisu z ikoną dyskietki i różowy
kafelek radia z ikoną nuty. Zbrojownia ma złoty kafelek z ikoną kamizelki.
Wybrana aplikacja ma jasną ramkę. Radio ma
osobny widok z sześcioma widocznymi stacjami i wskaźnikiem przewijania.
Grafika jest rysowana przez HUD gry, bez dodatkowych tekstur.

## Sterowanie

- `F8` — otwórz/zamknij telefon;
- `W`/`S` lub strzałki góra/dół — wybór; na ekranie głównym działają również
  `A`/`D` i strzałki lewo/prawo;
- `Enter`/`Spacja` — zatwierdź;
- `Esc`/`Backspace` — powrót o ekran wyżej lub anulowanie zakupu;
- w widoku radia `A`/`D` lub strzałki lewo/prawo zmieniają zaznaczenie.

Domyślnie telefon blokuje sterowanie postacią podczas otwarcia. Można to
wyłączyć w `BorealPhoneDE.ini` przez `freeze_player=0`. `F11` przeładowuje
plik konfiguracyjny.

## Zbrojownia

Wybierz kategorię, produkt, a następnie potwierdź zakup kolejnym naciśnięciem
`Enter`. Kategorie: pistolety, pistolety maszynowe, strzelby, karabiny,
materiały wybuchowe i ochrona. Dostępne jest 15 broni oraz kamizelka.

Ceny i pakiety amunicji odpowiadają bazowemu cennikowi
[Ammu-Nation w GTA SA](https://www.igrandtheftauto.com/gtasa/guides/ammu-nation).
Sklep w telefonie nie stosuje narzutu 20% sklepów Las Venturas, blokad
fabularnych ani zmian cennika wprowadzanych przez inne mody.

Ponowny zakup posiadanej broni dodaje pakiet amunicji. Inna broń w tym samym
slocie zostaje zastąpiona — ekran potwierdzenia ostrzega o tym przed zakupem.
Ładunek wybuchowy jest dostarczany z detonatorem. Kamizelka uzupełnia pancerz
do limitu postaci; pełnego pancerza nie można ponownie kupić.

Model broni jest ładowany przed pobraniem pieniędzy. Po dostawie skrypt
odczytuje ekwipunek; w razie błędu próbuje przywrócić poprzednią broń i saldo.
Niepotwierdzony stan powoduje blokadę dalszych zakupów i komunikat o logu CLEO.
Zamknięcie telefonu podczas ładowania anuluje zakup bez pobrania pieniędzy.

## Radio poza pojazdem — ograniczenie

Nie jest zaimplementowane w tej paczce. Dostępne polecenie
[`SET_RADIO_CHANNEL`](https://library.sannybuilder.com/#/sa_unreal?q=SET_RADIO_CHANNEL)
steruje radiem pojazdu, nie uruchamia przenośnego odtwarzacza. Obsługa radia
na piechotę wymaga dodatkowej integracji audio dopasowanej do wersji gry;
usunięcie warunku sprawdzającego pojazd nie rozwiązuje problemu.

## Instalacja

Wymagane są:

- Ultimate ASI Loader x64 jako `version.dll`;
- CLEO Redux x64;
- `IniFiles64.cleo` w `Gameface/Binaries/Win64/CLEO/CLEO_PLUGINS`.

Najprościej zaimportować `BorealPhoneDE.zip` w widoku modów GTA SA:DE w
Boreal, a następnie wdrożyć profil. Mod można też zainstalować ręcznie:

```sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

Skrypt trafia do:

```text
Gameface/Binaries/Win64/CLEO/BorealPhoneDE[fs].js
```

Konfiguracja trafia obok niego jako `BorealPhoneDE.ini`.

Po aktualizacji ponownie zaimportuj archiwum i wdróż profil przed kolejnym
uruchomieniem gry. Samo `F11` przeładowuje konfigurację, nie kod interfejsu.

## Ważne ograniczenie zapisu

Telefon może wywołać systemowy ekran zapisu w dowolnym momencie rozgrywki.
Ostateczna możliwość zapisania konkretnego stanu nadal zależy od reguł
oryginalnego ekranu GTA, np. od sytuacji, w której gra nie pozwala zapisać
stanu podczas określonej aktywności.
