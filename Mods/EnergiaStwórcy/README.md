# Energia Stwórcy

Trzy osobne rangi celowanego czaru do **The Elder Scrolls V: Skyrim Special Edition**. Obrażenia nie rosną automatycznie wraz z umiejętnością.

## Efekty

- **Energia Stwórcy I** — zadaje 25 pkt obrażeń magicznych w promieniu 10 stóp; koszt bazowy 25 Magicki.
- **Energia Stwórcy II** — zadaje 40 pkt obrażeń magicznych w promieniu 10 stóp; koszt bazowy 45 Magicki.
- **Energia Stwórcy III** — zadaje 60 pkt obrażeń magicznych w promieniu 10 stóp; koszt bazowy 70 Magicki.

Każda ranga przechwytuje duszę przeciwnika, jeśli gracz zabije go w ciągu **5 sekund od trafienia**. Najpierw używa odpowiedniego wolnego klejnotu z ekwipunku. Gdy go brakuje, gracz otrzymuje za darmo czarny klejnot, który zostaje napełniony duszą. Dotyczy to białych i czarnych dusz; istoty bez możliwej do przechwycenia duszy nie dają klejnotów.

MCM w SkyUI pozwala wyłączyć przechwytywanie dusz oraz niezależnie zdecydować,
czy mod ma dodawać darmowy czarny klejnot, gdy w ekwipunku brakuje pustego.

Każda ranga to szybki, jednoręczny pocisk z czasem przygotowania 0,3 s. Obrażenia podlegają odporności na magię; czar nie zadaje obrażeń od ognia ani innych żywiołów. Koszt bazowy może zostać obniżony przez poziom szkoły magii i odpowiednie atuty.

Pocisk korzysta z fioletowo-niebieskiego efektu Turn Undead oraz artów i shaderów Pułapki Dusz obecnych w Skyrim. Paczka nie dodaje własnych modeli ani tekstur. Dźwięki kastowania, trafienia i uderzenia pocisku pochodzą z `Skyrim.esm`; nie dodano plików audio.

## Instalacja

Zaimportuj `EnergiaStwórcy.zip` w Boreal i włącz `CreatorEnergy.esp`, albo skopiuj całą zawartość `Data/` do katalogu `Data` gry i aktywuj plugin w menedżerze modów. Uruchom grę przez SKSE i po rejestracji konfiguracji otwórz `Ustawienia modów → Energia Stwórcy`.

Wymagane są `Skyrim.esm`, SKSE zgodny z wersją gry oraz SkyUI z MCM. Dołączone skrypty Papyrusa znajdują się w paczce.

## Dodanie czaru

Czary nie są umieszczone u handlarzy ani w świecie. W konsoli wyszukaj wybraną rangę:

```text
help CreatorEnergySpell 4
```

Użyj FormID wyświetlonego dla wybranego EditorID:

```text
player.addspell <FormID>
```

EditorID-y:

```text
CreatorEnergySpell
CreatorEnergySpell02
CreatorEnergySpell03
```

Do dodawania rang służy `Source/add_spell_ranks.py`; skrypt aktualizuje istniejący ESP bez potrzeby odtwarzania efektów z mastera. `Source/add_spell_sounds.py` osobno przypisuje dźwięki do efektu i eksplozji. `Source/add_soul_capture.py` dodaje skrypt efektu, quest MCM i ustawienia do ESP.

## Budowanie

Wersja moda ma jedno źródło prawdy w `manifest.json`. Uruchom `./build.sh` z kompilatorem Caprica (domyślnie `.local-tools/caprica/Caprica.exe`). Domyślne deklaracje API są w `Source/CompilerImports`; opcjonalnie wskaż pełne źródła Papyrus przez `PAPYRUS_IMPORTS`. Skrypt buduje PEX, aktualizuje ESP i pakuje ZIP. `Source/add_soul_capture.py` dodaje przechwytywanie dusz do istniejących rang.
