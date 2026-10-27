# Smart Loot SE

Automatycznie zbiera wybrane przedmioty leżące w pobliżu gracza w Skyrim Special Edition:

- złoto,
- klejnoty oznaczone słowem kluczowym `VendorItemGem`,
- mikstury oznaczone `VendorItemPotion`,
- strzały (bełty są pomijane),
- luźne składniki alchemiczne.

Mod skanuje teren co 0,5 sekundy w promieniu 220 jednostek gry. Zbiera wyłącznie
widoczne przedmioty leżące w świecie; nie otwiera pojemników i nie zabiera rzeczy
z ekwipunku aktorów. Przedmioty zadaniowe są pomijane. Automatyczne zbieranie
wstrzymuje się podczas walki, w menu i po śmierci gracza.

Menu MCM w SkyUI pozwala włączyć lub wyłączyć mod, wybrać zbierane kategorie
oraz ustawić promień i odstęp skanowania. Pomijanie przedmiotów zadaniowych,
sprawdzanie widoczności i pauza w walce pozostają aktywne.

## Wymagania

- Skyrim Special Edition lub Anniversary Edition na Windows;
- SKSE64 zgodny z wersją gry;
- [Papyrus Extender](https://github.com/powerof3/PapyrusExtenderSSE) zgodny z SKSE;
- SkyUI z Mod Configuration Menu.

Wtyczka Papyrus Extender `FindAllReferencesOfFormType` wyszukuje referencje
w załadowanych komórkach w określonym promieniu. `IsQuestItem` pozwala pominąć
przedmioty zadaniowe.

## Instalacja

Zaimportuj `SmartLootSE.zip` w Boreal, włącz `SmartLoot.esp` i uruchom grę przez
SKSE. Po rejestracji menu wybierz `Ustawienia modów → Smart Loot SE`. Można też
rozpakować archiwum bezpośrednio do katalogu `Data`.

## Budowanie

`build.sh` kompiluje skrypty Papyrusa kompilatorem Caprica i tworzy archiwum
instalacyjne z menu MCM oraz plikiem SEQ. Wskaż ścieżkę do `Caprica.exe`
zmienną `CAPRICA_EXE`. Deklaracje używanych funkcji natywnych są tylko
nagłówkami dla kompilatora i nie trafiają do paczki.

```sh
CAPRICA_EXE=/ścieżka/do/Caprica.exe ./build.sh
```
