# Czary Stwórcy

Paczka 21 zaklęć do **The Elder Scrolls V: Skyrim Special Edition**: po trzy osobne rangi Pochłonięcia, Bariery, Impulsu, Przejęcia Jaźni, Osłabienia Rzeczywistości, Zaniku i Odbicia Woli. Rangi są oddzielnymi zaklęciami; ich siła nie rośnie automatycznie wraz z umiejętnością.

## Efekty

- **Pochłonięcie Stwórcy I** — wysysa 8 pkt zdrowia na sekundę i przywraca je rzucającemu; zasięg 30 m; koszt bazowy 12 Magicki na sekundę.
- **Pochłonięcie Stwórcy II** — wysysa i przywraca 12 pkt zdrowia na sekundę; zasięg 30 m; koszt bazowy 18 Magicki na sekundę.
- **Pochłonięcie Stwórcy III** — wysysa i przywraca 16 pkt zdrowia na sekundę; zasięg 30 m; koszt bazowy 24 Magicki na sekundę.
- **Bariera Stwórcy I** — przez 10 s dodaje 167 pkt pancerza i 20% odporności na magię; koszt bazowy 35 Magicki.
- **Bariera Stwórcy II** — przez 12 s dodaje 250 pkt pancerza i 30% odporności na magię; koszt bazowy 50 Magicki.
- **Bariera Stwórcy III** — przez 15 s dodaje 333 pkt pancerza i 40% odporności na magię; koszt bazowy 65 Magicki.
- **Impuls Stwórcy I** — zadaje 15 pkt obrażeń i zachwiewa cele w promieniu 16 stóp; koszt bazowy 45 Magicki.
- **Impuls Stwórcy II** — zadaje 25 pkt obrażeń i zachwiewa cele w promieniu 16 stóp; koszt bazowy 75 Magicki.
- **Impuls Stwórcy III** — zadaje 40 pkt obrażeń i zachwiewa cele w promieniu 16 stóp; koszt bazowy 120 Magicki.
- **Przejęcie Jaźni I** — istota do poziomu 50 atakuje pobliskie cele przez 20 s; koszt bazowy 45 Magicki.
- **Przejęcie Jaźni II** — istota do poziomu 75 atakuje pobliskie cele przez 25 s; koszt bazowy 80 Magicki.
- **Przejęcie Jaźni III** — istota do poziomu 100 atakuje pobliskie cele przez 30 s; koszt bazowy 120 Magicki.
- **Osłabienie Rzeczywistości I** — spowalnia ruch celu o 75% przez 10 s; koszt bazowy 40 Magicki.
- **Osłabienie Rzeczywistości II** — spowalnia ruch celu o 75% przez 15 s; koszt bazowy 65 Magicki.
- **Osłabienie Rzeczywistości III** — spowalnia ruch celu o 75% przez 20 s; koszt bazowy 90 Magicki.
- **Zanik I** — zadaje 6 pkt obrażeń zdrowia na sekundę przez 5 s; koszt bazowy 40 Magicki.
- **Zanik II** — zadaje 8 pkt obrażeń zdrowia na sekundę przez 6 s; koszt bazowy 65 Magicki.
- **Zanik III** — zadaje 10 pkt obrażeń zdrowia na sekundę przez 8 s; koszt bazowy 100 Magicki.
- **Odbicie Woli I** — przez 6 s odbija 20% obrażeń fizycznych i dodaje 20% odporności na magię; koszt bazowy 40 Magicki.
- **Odbicie Woli II** — przez 8 s odbija 30% obrażeń fizycznych i dodaje 30% odporności na magię; koszt bazowy 70 Magicki.
- **Odbicie Woli III** — przez 10 s odbija 40% obrażeń fizycznych i dodaje 40% odporności na magię; koszt bazowy 100 Magicki.

Koszt bazowy może zostać obniżony przez poziom szkoły magii i odpowiednie atuty. Pancerz jest w Skyrimie dodawany jako wartość, więc jego wpływ na redukcję obrażeń zależy od pozostałego pancerza i limitu redukcji. Osłabienie obniża ruch, ale nie szybkość ataku, i używa wbudowanego efektu spowolnienia mrozem. Odbicie działa na ciosy fizyczne, nie na obrażenia magiczne. Impuls zachwiewa celami; nie odrzuca ich.

Wtyczka używa istniejących efektów Skyrim. Rangi danego czaru korzystają z tych samych efektów magicznych, a każda ranga ma osobny koszt i parametry. Pozostałe zaklęcia gry zachowują oryginalne brzmienie. Dźwięki pochodzą z `Skyrim.esm`; paczka nie dodaje plików audio, siatek ani tekstur. Bariera daje aurę flesh zamiast kulistej bańki, Impuls korzysta z efektu fali Unrelenting Force, a Pochłonięcie z czerwonego promienia wampirycznego. Część kolorów i wyglądu odbiega więc od docelowych fioletowych, czarno-czerwonych efektów. Zaklęcia nie wymagają Dawnguard, SKSE ani Papyrusa.

## Instalacja

Zaimportuj `CzaryStwórcy.zip` w Boreal i włącz `CreatorSpells.esp`, albo skopiuj `Data/CreatorSpells.esp` do katalogu `Data` gry i aktywuj plugin w menedżerze modów. Wymagany jest `Skyrim.esm`.

## Dodanie czaru do postaci

Zaklęcia nie są umieszczone u handlarzy ani w świecie. W konsoli wyszukaj czar po EditorID, bez dopisywania typu `SPEL`:

```text
help CreatorAbsorptionSpell 4
```

Wyszukiwanie wyświetli FormID aktualne dla bieżącego load order. Następnie wpisz:

```text
player.addspell <FormID>
```

EditorID-y wszystkich rang:

```text
CreatorAbsorptionSpell
CreatorAbsorption02Spell
CreatorAbsorption03Spell
CreatorBarrier01Spell
CreatorBarrier02Spell
CreatorBarrier03Spell
CreatorImpulseSpell
CreatorImpulse02Spell
CreatorImpulse03Spell
CreatorMindTakeoverSpell
CreatorMindTakeover02Spell
CreatorMindTakeover03Spell
CreatorRealityWeakeningSpell
CreatorRealityWeakening02Spell
CreatorRealityWeakening03Spell
CreatorDecaySpell
CreatorDecay02Spell
CreatorDecay03Spell
CreatorWillReflectionSpell
CreatorWillReflection02Spell
CreatorWillReflection03Spell
```

Nie wpisuj `01000800` jako runtime FormID. Prefiks zmienia się zależnie od load order; użyj wartości pokazanej przez `help`.

## Źródło pluginu

`Source/build_plugin.py` odtwarza ESP z `Skyrim.esm` zainstalowanego razem z grą, a następnie dopisuje wyższe rangi. Użyj `--plugin-only`, aby zaktualizować istniejący ESP bez mastera. Do instalacji użyj gotowego archiwum.
