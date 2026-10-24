# Czary Stwórcy

Pierwsza paczka dodatkowych czarów dla **The Elder Scrolls V: Skyrim Special Edition**. Zawiera dziewięć zaklęć: Pochłonięcie Stwórcy, trzy rangi Bariery Stwórcy, Impuls Stwórcy, Przejęcie Jaźni, Osłabienie Rzeczywistości, Zanik i Odbicie Woli.

## Efekty

- **Pochłonięcie Stwórcy** — ciągły promień o zasięgu około 30 m; wysysa 8 zdrowia i leczy rzucającego o 8 punktów na sekundę; koszt 12 Magicki na sekundę.
- **Bariera Stwórcy I** — 10 s, +167 pancerza i 20% odporności na magię.
- **Bariera Stwórcy II** — 12 s, +250 pancerza i 30% odporności na magię.
- **Bariera Stwórcy III** — 15 s, +333 pancerza i 40% odporności na magię.
- **Impuls Stwórcy** — 15 obrażeń, obszar 16 stóp (około 5 m) oraz efekt odrzutu i stagger.
- **Przejęcie Jaźni** — pojedynczy cel walczy z pobliskimi istotami przez 20 s, bez obrażeń.
- **Osłabienie Rzeczywistości** — spowolnienie ruchu celu przez 10 s.
- **Zanik** — czyste obrażenia zdrowia w czasie: 6 na sekundę przez 5 s.
- **Odbicie Woli** — przez 6 s daje 20% odporności na magię i 20% odbicia obrażeń.

Pancerz jest w Skyrimie dodawany jako wartość, więc procent redukcji fizycznej Bariery jest przybliżeniem zależnym od pozostałego pancerza i limitu redukcji. Osłabienie obniża ruch, ale w tej wersji nie spowalnia szybkości ataku i używa wbudowanego efektu spowolnienia mrozem. Odbicie korzysta z wbudowanej mechaniki Skyrima: odbija ciosy fizyczne, nie obrażenia magiczne. Pełne zwracanie czarów wymagałoby skryptu.

Wtyczka używa istniejących efektów Skyrim. Każdy czar ma własne kopie efektów magicznych z profilem dźwięku; dźwięki trafienia są przypisane efektom, które nakładają się na cel. Pozostałe zaklęcia gry zachowują oryginalne brzmienie. Dźwięki pochodzą z `Skyrim.esm`; paczka nie dodaje plików audio, siatek ani tekstur. Bariera daje aurę flesh zamiast kulistej bańki, Impuls korzysta z efektu fali Unrelenting Force, a Pochłonięcie z czerwonego promienia wampirycznego. Część kolorów i wyglądu odbiega więc od docelowych fioletowych, czarno-czerwonych efektów. Zaklęcia nie wymagają Dawnguard, SKSE ani Papyrusa.

ESP został zbudowany z rekordów `Skyrim.esm` i sprawdzony strukturalnym parserem. Nie udało się uruchomić walidacji xEdit ani testu w grze w tym środowisku, więc zachowanie efektów po czasie trwania wymaga potwierdzenia w grze.

## Instalacja

Zaimportuj `CzaryStwórcy.zip` w Boreal i włącz `CreatorSpells.esp`, albo skopiuj `Data/CreatorSpells.esp` do katalogu `Data` gry i aktywuj plugin w menedżerze modów. Wymagany jest `Skyrim.esm`.

## Dodanie czaru do postaci

Zaklęcia nie są umieszczone u handlarzy ani w świecie. Otwórz konsolę i wyszukaj czar po EditorID, bez dopisywania typu `SPEL`:

```text
help CreatorAbsorptionSpell 4
```

Wyszukiwanie wyświetli FormID aktualne dla bieżącego load order. Następnie wpisz:

```text
player.addspell <FormID>
```

EditorID-y pozostałych czarów:

```text
CreatorBarrier01Spell
CreatorBarrier02Spell
CreatorBarrier03Spell
CreatorImpulseSpell
CreatorMindTakeoverSpell
CreatorRealityWeakeningSpell
CreatorDecaySpell
CreatorWillReflectionSpell
```

Nie wpisuj `01000800` jako runtime FormID. Prefiks zmienia się zależnie od load order; użyj wartości pokazanej przez `help`.

## Źródło pluginu

`Source/build_plugin.py` buduje ESP z `Skyrim.esm` zainstalowanego razem z grą. Ten skrypt jest potrzebny wyłącznie do odtwarzania paczki; do instalacji użyj gotowego archiwum.
