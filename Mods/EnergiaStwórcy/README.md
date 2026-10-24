# Energia Stwórcy

Pierwsza wersja prostego czaru do **The Elder Scrolls V: Skyrim Special Edition**.

## Działanie

- szybki, celowany pocisk do rzucania jedną ręką;
- 25 punktów obrażeń zdrowia, odporność na magię;
- niewielki obszar działania: 10 stóp (około 3 m);
- koszt bazowy 25 Magicki, bez automatycznego przeliczania kosztu;
- czas przygotowania 0,3 s;
- lekki efekt trafienia i mały rozbłysk energii;
- brak obrażeń od ognia i innych żywiołów.
- dźwięki rzucania, trafienia oraz uderzenia pocisku oparte na zasobach magii z Skyrim.

Efekty wizualne korzystają z fioletowo-niebieskiego pocisku Turn Undead oraz
artów i shaderów Pułapki Dusz obecnych w Skyrim. Paczka nie dodaje własnych
modeli ani tekstur.

Paczka używa dźwięków zapisanych w `Skyrim.esm`; nie dodaje plików audio.
Dźwięki kastowania i trafienia są przypisane do `CreatorEnergyDamage`, a dźwięk
uderzenia pocisku do `CreatorEnergyExplosion`.

## Instalacja

Zaimportuj `EnergiaStwórcy.zip` w Boreal i włącz `CreatorEnergy.esp`, albo
skopiuj `Data/CreatorEnergy.esp` do katalogu `Data` gry i aktywuj plugin w
menedżerze modów.

Wymagane jest tylko `Skyrim.esm`. Mod nie wymaga SKSE ani skryptów Papyrus.

## Dodanie czaru

Czar nie jest umieszczony u handlarzy ani w świecie. W konsoli gry wpisz:

```text
help CreatorEnergySpell 4
```

Następnie użyj FormID wyświetlonego dla `CreatorEnergySpell`:

```text
player.addspell <FormID>
```
