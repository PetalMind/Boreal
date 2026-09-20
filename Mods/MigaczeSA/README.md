# Migacze SA

Modyfikacja CLEO dla klasycznego **Grand Theft Auto: San Andreas na PC**.
Poruszające się pojazdy zapalają bursztynowe kierunkowskazy po stronie, w którą
zaczynają skręcać. Skrypt rysuje światła z przodu i z tyłu pojazdu, nie zmienia
AI, trasy, prędkości ani prowadzenia.

## Możliwość techniczna

Tak, ten efekt jest możliwy w GTA SA przez CLEO. Publiczne opcodes pozwalają
enumerować pojazdy, odczytywać ich położenie, prędkość i heading oraz rysować
korony światła (`DRAW_CORONA`). Skrypt korzysta z tych danych i nie patchuje
wersjozależnych adresów pamięci gry.

W tym wydaniu użyty jest **CLEO Redux JavaScript dla hosta `sa`**. W klasycznym
GTA SA CLEO Redux musi działać w trybie delegate razem z CLEO Library; sam
`cleo_redux.asi` w trybie standalone nie jest obsługiwanym trybem dla
klasycznego SA.

## Instalacja

Wymagane są:

- klasyczne GTA SA 1.0 na PC (`gta_sa.exe`, `gta-sa.exe` albo
  `gta_sa_compact.exe`);
- CLEO Library;
- CLEO Redux z włączonym trybem delegate dla klasycznego GTA SA;
- loader ASI wymagany przez daną instalację.

Najprościej uruchomić z tego katalogu:

```sh
./install.sh "/ścieżka/do/katalogu/GTA San Andreas"
```

Instalacja ręczna polega na skopiowaniu:

```text
CLEO/MigaczeSA.js
```

do katalogu `CLEO` w katalogu gry.

## Jak działa wykrywanie skrętu

Co około 120 ms skrypt przegląda pojazdy w promieniu 260 metrów od gracza.
Dla każdego pojazdu porównuje heading z poprzednią obserwacją i sprawdza ruch
boczny. Kierunkowskaz jest aktywny przy rzeczywistej zmianie kierunku lub
ruchu bocznym, a po zakończeniu skrętu pozostaje aktywny jeszcze przez krótką
chwilę. Miganie ma okres około 560 ms.

To oznacza, że kierunkowskaz nie jest wyliczany z zamiaru AI przed skrętem.
Klasyczny publiczny interfejs CLEO nie gwarantuje dostępu do następnego węzła
trasy ani do planowanej decyzji kierowcy, dlatego skrypt nie udaje takiej
informacji. W praktyce światło zapala się, gdy pojazd faktycznie rozpoczyna
manewr.

Pozycja świateł jest wspólnym, bezpiecznym offsetem lokalnym dla różnych
modeli. Nie każdy model GTA SA ma osobne, nazwane dummysy kierunkowskazów, więc
nie jest to podmiana materiału lamp w modelu. Korony są widoczne jako małe,
bursztynowe światła przy przedniej i tylnej części odpowiedniej strony auta.

## Boreal

Archiwum `MigaczeSA.zip` można importować w menedżerze modów klasycznego GTA
SA. Wewnątrz zachowana jest ścieżka `CLEO/MigaczeSA.js`, dzięki czemu Mod
Loader może ją nakładać bez ręcznej podmiany plików gry.

Mod jest przeznaczony dla klasycznego hosta `sa`, nie dla GTA San Andreas:
Definitive Edition (`sa_unreal`).

## Źródła techniczne

- [CLEO Redux — instalacja](https://re.cleo.li/docs/en/installation.html)
- [CLEO Redux — API i host `sa`](https://re.cleo.li/docs/en/api.html)
- [CLEO Redux — relacja z CLEO Library](https://re.cleo.li/docs/en/relation-to-cleo-library.html)
- [CLEO Redux — eventy pojazdów](https://re.cleo.li/docs/en/events.html)
- [Sanny Builder Library — definicje GTA SA](https://github.com/sannybuilder/library/blob/master/sa/sa.json)
