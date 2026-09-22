# Dragon Age: Origins — Cooldown Numbers

Mod QoL dla pecetowego **Dragon Age: Origins**. Dodaje liczbowy, rzeczywisty
czas odnowienia bezpośrednio na środku każdej aktywnej ikony quickbara:

- `>= 10 s`: sekundy całkowite (`24`, `18`, `10`);
- `< 10 s`: jedna cyfra po przecinku (`8.4`, `3.2`, `0.7`);
- po wygaśnięciu cooldownu tekst znika;
- istniejący vanilla radialny efekt oraz krótki flash pozostają bez zmian;
- mod działa na aktualnie wybranej postaci, więc przełączenie bohatera od razu
  pokazuje jego własne cooldowny;
- nie zmienia żadnej wartości w `ABI_*.GDA` ani żadnego gameplayu.

## Instalacja gotowej paczki

Skopiuj `CooldownNumbersDAO.zip` do Boreal albo wypakuj jego zawartość do:

```text
Documents/BioWare/Dragon Age/packages/core/override/
```

Jeżeli instalujesz przez Boreal, archiwum jest zwykłym pakietem override DAO.
Przed podmianą `quickbar.gfx` zachowaj kopię poprzedniej wersji, jeżeli używasz
innego moda zmieniającego quickbar. Mody zastępujące ten sam plik GUI mogą się
wzajemnie nadpisać.

## Budowanie z lokalnej instalacji DAO

Repozytorium nie zawiera skopiowanego z gry `quickbar.gfx` ani narzędzia
Scaleform. `build.sh` bierze oryginalny plik z lokalnej instalacji, wyciąga z
`guiexport.erf` tylko `quickbar.gfx`, dekompiluje jego skrypty AS2, nakłada
wąski patch i ponownie pakuje plik jako CFX/GFX.

Wymagane:

- JPEXS Free Flash Decompiler 26.x; ustaw `FFDEC` na `ffdec.sh` lub katalog
  `FFDec.app/Contents/Resources/ffdec.sh`;
- Python 3;
- lokalna instalacja DAO z `packages/core/data/guiexport.erf`.

Przykład:

```sh
FFDEC="/ścieżka/do/FFDec.app/Contents/Resources/ffdec.sh" \
  ./build.sh "/ścieżka/do/Dragon Age Origins"
```

Wynikiem są `override/quickbar.gfx` oraz `CooldownNumbersDAO.zip`.

## Granica techniczna

Vanilla GUI wystawia dla slotu `CooldownPercentage`, a obok pełny czas z
`AbilityTemplate.Cooldown`; istniejący `PieCooldown` używa właśnie tego tokenu
do radialnego zaciemnienia. Mod wylicza z tych danych pozostałe sekundy i
odświeża tekst co 100 ms. To jest odczyt stanu silnika, nie osobny timer, który
mógłby rozjechać się z cooldownem gry.

DAO nie udostępnia zwykłemu plikowi override mechanizmu ładowania dowolnego
INI jako ustawień GFx. Dlatego pierwsza wersja ma celowo bezpieczne, stałe
ustawienia opisane wyżej; nie dodaje menu, które wyglądałoby na działające, ale
nie miałoby źródła danych w grze. `Ready` nie jest osobnym napisem — vanilla
flash po `OnCooldownEnd` pozostaje sygnałem gotowości.

## Odinstalowanie

Usuń `quickbar.gfx` z katalogu DAO override albo wyłącz pakiet w Boreal. Przy
instalacji przez Boreal poprzedni plik jest objęty jego mechanizmem kopii
zapasowych.
