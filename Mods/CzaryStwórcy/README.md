# Czary Stwórcy

Paczka 23 zaklęć do **The Elder Scrolls V: Skyrim Special Edition**: po trzy osobne rangi Pochłonięcia, Bariery, Impulsu, Przejęcia Jaźni, Osłabienia Rzeczywistości, Zaniku i Odbicia Woli oraz Spopielenie i Wewnętrzna eksplozja. Rangi są oddzielnymi zaklęciami; ich siła nie rośnie automatycznie wraz z umiejętnością. Źródłem wersji paczki jest `manifest.json`.

## Efekty

- **Spopielenie** — podczas podtrzymywania zadaje 25 pkt obrażeń ogniem na sekundę fioletowo-pomarańczowym strumieniem; zasięg około 30 m; koszt bazowy 30 Magicki na sekundę. Po zabiciu nakłada na ciało ciemny efekt osmalenia, zachowując jego geometrię i łup. Przechwytuje duszę do odpowiedniego pustego kamienia; gdy takiego nie ma, dodaje czarny kamień i usuwa go, jeśli przechwycenie się nie uda. Nie tworzy kamieni dla istot bez duszy ani dodatkowych dusz z już przechwyconej ofiary.
- **Wewnętrzna eksplozja** — kula energii wywołuje ucieczkę w strachu przez 5 s; następnie zabija cel i odtwarza krwawy rozbryzg z dźwiękiem; koszt bazowy 100 Magicki. Ponowne trafienie podczas odliczania nie kumuluje eksplozji. Czar nie wyłącza ochrony postaci niezbędnych dla fabuły. Cel zabity wcześniej nie eksploduje ponownie. Skrypty Papyrus mogą opóźnić detonację przy dużym obciążeniu gry. Wybuch dotyczy trafionego celu; nie zadaje obrażeń obszarowych.
- **Pochłonięcie Stwórcy I** — wysysa 8 pkt zdrowia na sekundę i przywraca je rzucającemu; zasięg 30 m; koszt bazowy 12 Magicki na sekundę.
- **Pochłonięcie Stwórcy II** — wysysa i przywraca 12 pkt zdrowia na sekundę; zasięg 30 m; koszt bazowy 18 Magicki na sekundę.
- **Pochłonięcie Stwórcy III** — wysysa i przywraca 16 pkt zdrowia na sekundę; zasięg 30 m; koszt bazowy 24 Magicki na sekundę.
- **Bariera Stwórcy I** — przez 10 s dodaje 167 pkt pancerza i 20% odporności na magię; koszt bazowy 35 Magicki.
- **Bariera Stwórcy II** — przez 12 s dodaje 250 pkt pancerza i 30% odporności na magię; koszt bazowy 50 Magicki.
- **Bariera Stwórcy III** — przez 15 s dodaje 333 pkt pancerza i 40% odporności na magię; koszt bazowy 65 Magicki.
- **Impuls Stwórcy I** — zadaje 15 pkt obrażeń i zachwiewa cele w promieniu 16 stóp; koszt bazowy 45 Magicki.
- **Impuls Stwórcy II** — zadaje 25 pkt obrażeń i zachwiewa cele w promieniu 16 stóp; koszt bazowy 75 Magicki.
- **Impuls Stwórcy III** — zadaje 40 pkt obrażeń i zachwiewa cele w promieniu 16 stóp; koszt bazowy 120 Magicki.
- **Przejęcie Jaźni I** — istota do poziomu 50 atakuje pobliskie cele aż do śmierci; koszt bazowy 45 Magicki.
- **Przejęcie Jaźni II** — istota do poziomu 75 atakuje pobliskie cele aż do śmierci; koszt bazowy 80 Magicki.
- **Przejęcie Jaźni III** — istota do poziomu 100 atakuje pobliskie cele aż do śmierci; koszt bazowy 120 Magicki.
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

Przejęcie Jaźni nie obejmuje straży, a jego efekty nie są oznaczone jako wrogi atak. Szał utrzymuje się do śmierci celu.

Wtyczka używa istniejących efektów Skyrim oraz osobnej siatki i palety ognia Spopielenia. Rangi danego czaru korzystają z tych samych efektów magicznych, a każda ranga ma osobny koszt i parametry. Pozostałe zaklęcia gry zachowują oryginalne brzmienie. Dźwięki pochodzą z `Skyrim.esm`; paczka nie dodaje plików audio. Bariera daje aurę flesh zamiast kulistej bańki, Impuls korzysta z efektu fali Unrelenting Force, a Pochłonięcie z czerwonego promienia wampirycznego. Część kolorów i wyglądu starszych zaklęć odbiega więc od docelowych fioletowych, czarno-czerwonych efektów. Nowe zaklęcia korzystają z dwóch dołączonych skryptów Papyrus, obsługiwanych przez samą grę. Dawnguard i SKSE nie są wymagane.

## Instalacja

Zaimportuj `CzaryStwórcy.zip` w Boreal i włącz `CreatorSpells.esp`, albo skopiuj **całą zawartość `Data`** paczki do katalogu `Data` gry i aktywuj plugin w menedżerze modów. Wymagany jest `Skyrim.esm`. Sam plik ESP nie wystarcza dla nowych zaklęć: wymagają dołączonych katalogów `Scripts`, `Meshes` i `Textures`.

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
CreatorIncinerationSpell
CreatorInternalExplosionSpell
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

`Source/build_package.py` odtwarza ESP z `Skyrim.esm`, buduje zasoby ognia z lokalnych archiwów gry, kompiluje skrypty z kontrolą typów i ostrzeżeń oraz tworzy ZIP. Potrzebne są Python 3.9+, pakiet `lz4` oraz Caprica (na macOS także Wine):

```sh
python3 Source/build_package.py --skyrim-data '/ścieżka/do/Skyrim/Data' --compiler '/ścieżka/do/Caprica.exe'
```

`Source/build_plugin.py` buduje wyłącznie ESP. Opcja `--plugin-only` aktualizuje tylko dotychczasowe rangi i nie dodaje nowych czarów, skryptów ani zasobów. Do instalacji użyj kompletnego archiwum.

Budowa, lint źródeł Python i kontrola typów nie potwierdzają wyglądu ani zachowania w silniku gry. Wersja 1.4.0 nie została sprawdzona w uruchomionej rozgrywce Skyrim SE.
