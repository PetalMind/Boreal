# Boreal Phone DE

Mod CLEO Redux x64 dla **Grand Theft Auto: San Andreas – The Definitive Edition**.
Po naciśnięciu `F8` otwiera telefonowy interfejs HUD z:

- **ZAPIS GRY** — otwiera oryginalny ekran zapisu GTA, więc zapis korzysta z
  prawdziwego systemu gry;
- **RADIO** — pozwala wybrać stację i wyłączyć radio. Zmiana stacji działa, gdy
  gracz jest w pojeździe;
- **ZAMKNIJ** — zamyka telefon.

## Sterowanie

- `F8` — otwórz/zamknij telefon;
- `W`/`S` lub strzałki góra/dół — wybór;
- `Enter`/`Spacja` — zatwierdź;
- `Esc`/`Backspace` — powrót z radia albo zamknięcie telefonu;
- w widoku radia `A`/`D` lub strzałki lewo/prawo zmieniają zaznaczenie.

Domyślnie telefon blokuje sterowanie postacią podczas otwarcia. Można to
wyłączyć w `BorealPhoneDE.ini` przez `freeze_player=0`. `F11` przeładowuje
plik konfiguracyjny.

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

## Ważne ograniczenie zapisu

Telefon może wywołać systemowy ekran zapisu w dowolnym momencie rozgrywki.
Ostateczna możliwość zapisania konkretnego stanu nadal zależy od reguł
oryginalnego ekranu GTA, np. od sytuacji, w której gra nie pozwala zapisać
stanu podczas określonej aktywności.
