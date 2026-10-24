# Nearby Harvest & Loot SE

Po aktywowaniu rośliny mod zbiera pozostałe, niezbierane jeszcze rośliny w
ustawionym promieniu. Gdy otworzysz zwłoki wrogiego aktora, mod przenosi do
ekwipunku gracza łup z innych pobliskich wrogich zwłok. Otwarta przez gracza
ofiara pozostaje w standardowym menu łupienia, dzięki czemu można wybrać z niej
konkretne przedmioty.

W MCM SkyUI można osobno włączyć zbieranie roślin i pobliski łup oraz ustawić
promień od 128 do 2048 jednostek gry. Rośliny muszą być widoczne dla gracza;
mod pomija już zebrane rośliny, wyłączone referencje i przedmioty zadaniowe
znajdujące się w ekwipunkach zwłok.

## Wymagania

- Skyrim Special Edition lub Anniversary Edition na Windows;
- SKSE64 zgodny z wersją gry;
- Papyrus Extender zgodny z SKSE;
- SkyUI z MCM.

Skanowanie używa Papyrus Extender do wyszukania roślin w załadowanych komórkach
i aktorów o wysokim poziomie przetwarzania. Funkcja lootowania obejmuje więc
martwych wrogów w aktualnie załadowanym obszarze gry.

## Instalacja

Zaimportuj `NearbyHarvestLootSE.zip` w Boreal, włącz `NearbyHarvestLootSE.esp`
i uruchom grę przez SKSE. Można też rozpakować archiwum do katalogu `Data`.
Po załadowaniu zapisu ustawienia znajdziesz w MCM pod nazwą „Nearby Harvest &
Loot SE”.

## Budowanie

`build.sh` kompiluje skrypty Papyrusa kompilatorem Caprica, tworzy wtyczkę ESP
i archiwum instalacyjne. Wskaż ścieżkę do `Caprica.exe` zmienną `CAPRICA_EXE`,
jeśli kompilator nie znajduje się w `.local-tools/caprica`.

```sh
CAPRICA_EXE=/ścieżka/do/Caprica.exe ./build.sh
```
