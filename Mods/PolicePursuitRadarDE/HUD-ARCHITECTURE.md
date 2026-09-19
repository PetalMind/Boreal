# HUD Police Pursuit Radar DE — wdrożona architektura

> **Status: wycofana.** Ta architektura tworzyła dodatkową warstwę HUD i nie
> modyfikowała oficjalnej minimapy. W SA:DE 1.0.113.21181 pierwszy skan świata
> po pięciosekundowym opóźnieniu kończy proces gry bez obsłużonego błędu CLEO.
> `LEGACY_CLEO_IMPLEMENTATION_ENABLED=false` zatrzymuje skrypt przed wejściem
> w pętlę. Docelowa prostokątna minimapa musi nadpisywać Unrealowy
> `BP_Radar_Base` w paczce `.pak` dopasowanej do tego builda gry.

Dokument opisuje aktualny sposób przygotowania i prezentowania HUD-u w
`PolicePursuitRadar.js` po przebudowie zgodnej z analizą stabilności. Kluczowa
zmiana polega na rozdzieleniu odczytów GTA, modelu prezentacyjnego i samego
renderera.

## Stan bezpieczeństwa

W dostarczonej konfiguracji własny HUD jest włączony:

```ini
[hud]
enabled=1
draw_budget=24
```

Wcześniejszy renderer wykonywał setki fragmentów i przekazywał znormalizowane
współrzędne `0…1` bezpośrednio do `DRAW_RECT`. CLEO/SCM oczekuje tu wirtualnej
przestrzeni `640×448`, stosowanej też przez działające mody HUD i menu dla
SA:DE. Renderer zachowuje model znormalizowany, ale na granicy API przelicza
pozycję i rozmiar, po czym wywołuje statyczne `Hud.DrawRect`.

## Przepływ danych

```text
native queries / tracking
        │
        ▼
UnitRegistry: jednostki z wrapperami GTA
        │  skan co 450 ms, discovery co 1200 ms
        ▼
RadarModel: tylko skończone dane prezentacyjne
        │  pozycje normalized screen-space + interpolacja
        ▼
rectangular renderer: stała liczba Hud.DrawRect w przestrzeni 640×448
        │
        └── błąd lub przekroczenie budżetu → degradacja do native blipów
```

Pętla nadal używa `wait(0)`, ale nie wykonuje już odczytu pozycji gracza dla
HUD-u w każdej iteracji. Pozycja i heading gracza są pobierane razem z cyklem
trackingu. Dzięki temu renderer nie zna `actor`, `char`, `car` ani żadnego
wrappera GTA i otrzymuje gotowy model.

Po wykryciu gameplayu skrypt odczekuje `GAMEPLAY_SETTLE_MS = 5000`. W tym
czasie nie wykonuje skanowania świata, tworzenia blipów ani własnego
renderowania.

## Tracking i rejestr jednostek

Warstwa trackera zachowuje poprzednie ograniczenia:

- znane jednostki są odświeżane co `450 ms`;
- wyszukiwanie nowych jednostek jest wykonywane co `1200 ms`;
- discovery używa 17 punktów: centrum oraz dwa pierścienie po 8 punktów;
- układ próbek obraca się przez `scanPhase`;
- maksymalnie 16 jednostek trafia do rejestru;
- pojedynczy nieudany odczyt nie usuwa od razu znanej jednostki;
- natywne blipy są ograniczone do 12, a blipy kierunku do 4.

Wrappery `char` i `car` pozostają wyłącznie w trackerze, ponieważ są potrzebne
do kolejnych zapytań i obsługi natywnych blipów. Nie są kopiowane do modelu
HUD-u.

### Lifecycle jednostki i read-only discovery

Discovery używa `GET_RANDOM_CHAR_IN_AREA_OFFSET_NO_SAVE`, a pojazd policjanta
jest pobierany przez `STORE_CAR_CHAR_IS_IN_NO_SAVE`. Radar obserwuje świat, ale
nie powinien przejmować ownershipu nad ambient pedami i pojazdami.

Każdy rekord ma rozdzielone pojęcia:

```text
tracked  — rekord istnieje w UnitRegistry
seenNow  — ten tick potwierdził kontakt wzrokowy
lastSeenAt — ostatni tick z potwierdzonym kontaktem
lifecycle — visible / memory / lost
```

Kontakt jest zerowany przy każdym odczycie i wymaga jednocześnie odległości,
FOV, LOS oraz bieżącego wyniku `HAS_CHAR_SPOTTED_CHAR`. Utrata odczytu może
zachować rekord tylko przez jeden skan, ale nie zachowuje kontaktu jako
aktywnego.

Przejścia lifecycle wyglądają tak:

```text
VISIBLE
  │ utrata kontaktu
  ▼
MEMORY 350 ms
  │
  ▼
LOST
  │ brak poprawnego rekordu / TTL
  ▼
EVICT + cleanup
```

Blip encji jest tworzony wyłącznie dla `visible` albo krótkiego `memory`.
Po przejściu do `lost` exact blip i blip kierunku są usuwane; podczas
`SEARCH` pozostaje tylko `lastKnown` i obszar poszukiwań.

## RadarModel

`updateRadarModel()` jest wywoływane przy aktualizacji trackingu. Dla każdej
jednostki tworzy skończony rekord prezentacyjny:

```text
{
  x, y,              // normalized screen-space
  rotation,          // kierunek jednostki względem mapy HUD-u
  icon,              // foot/car/bike/boat/helicopter
  state,             // TRACKED albo CONTACT
  alpha,
  offRadar,
  coneRotation,
  coneScale
}
```

Model zawiera również dane gracza, obszaru `SEARCH` i `lastKnown`. Renderer
nie wykonuje własnych zapytań o świat ani nie oblicza położenia jednostki z
handle’a.

### Transformacja świata

`radarPoint()` stosuje własną, publiczną aproksymację w normalized screen-space:

1. liczy wektor między graczem a jednostką;
2. opcjonalnie obraca go względem headingu gracza;
3. skaluje odległość przez `range_m`;
4. odwraca oś Y ekranu;
5. ogranicza punkt do prostokątnego obszaru HUD-u;
6. opcjonalnie umieszcza jednostkę na krawędzi jako `offRadar`.

Nie jest to prywatna transformacja minimapy UE4. CLEO Redux nie udostępnia
skryptowi layoutu wewnętrznego radaru, dlatego HUD korzysta z własnej,
konfigurowalnej przestrzeni ekranu.

### Interpolacja

Każdy klucz jednostki ma przejście `previous → target` trwające co najmniej
czas cyklu trackingu. `buildRadarModel()` może być wywoływane co klatkę bez
odczytu świata i interpoluje:

- `x`, `y`;
- alpha;
- heading jednostki i kierunek stożka po najkrótszym łuku;
- skalę stożka.

Tracking pozostaje częstotliwością logiczną 450 ms, a prezentacja nie musi już
działać z tym samym krokiem ani być sztucznie ograniczona do około 15 FPS.

## Aktualny renderer prostokątny

Zastąpiono kosztowne funkcje `drawFilledEllipse`, `drawCircle`, `drawLine`,
rasteryzowane elipsy i rasteryzowane trójkąty. Nowy renderer nie tworzy
geometrii z wielu pasów.

W trybie `REDUCED` kolejność prezentacji jest następująca:

1. jedno tło prostokątne;
2. cztery krótkie prostokąty obramowania;
3. jeden prostokąt obszaru `SEARCH`, jeżeli jest aktywny;
4. jeden marker `lastKnown`, jeżeli jest dostępny;
5. maksymalnie 6 markerów jednostek;
6. jeden marker gracza.

Maksymalny koszt to 14 logicznych wywołań `DRAW_RECT`, a więc mieści się w
docelowym przedziale 10–25 operacji i nie zależy od liczby segmentów krzywej.
Tryb `MINIMAL` usuwa obramowanie i elementy pomocnicze, pozostawiając tło,
gracza i najwyżej 3 jednostki.

Markery są pojedynczymi prostokątami. Kolor nadal rozróżnia kontakt, pieszego,
pojazd, łódź, motocykl i helikopter. Kierunek oraz dane stożka są zachowane w
`RadarModel`, ale nie są udawane przez kosztowne, nierotowane linie. Pełne
stożki i obrotowe ikony wymagają stabilnego sprite’a.

## Sprite’y — dlaczego nie są jeszcze domyślne

Lokalne definicje `sa.d.ts` potwierdzają API:

```text
Txd.LoadDictionary(name)
Txd.LoadSprite(slot, textureName)
Hud.DrawSprite(...)
Hud.DrawSpriteWithRotation(...)
```

W aktywnej instalacji nie ma jednak lokalnego zasobu TXD/PNG, który można
bezpiecznie załadować jako własny atlas radarowy. Nie zakładam nazwy słownika
ani tekstury z klasycznej wersji GTA SA, ponieważ byłaby to niezweryfikowana
zależność od innego runtime’u. Model jest już przygotowany pod sprite’y, ale
renderer sprite’owy wymaga najpierw konkretnego, poprawnie ładowanego atlasu.

## Budżet i degradacja

`drawHudRect()` ma dwa zabezpieczenia:

- licznik `hudFrameDrawCalls` z konfigurowalnym limitem 8–24;
- pomiar czasu całej klatki przez `performance.now()`, z fallbackiem do
  `Date.now()`.

W pamięci utrzymywane są średnia, P95 i maksimum z ostatnich 30 klatek.
Twardy próg pojedynczej klatki wynosi obecnie 4 ms. Nie jest to obietnica
limitu silnika UE4, tylko bezpiecznik aplikacyjny — rzeczywisty koszt nadal
zależy od wersji gry i obciążenia renderera.

Degradacja przebiega następująco:

```text
FULL → REDUCED → MINIMAL → NATIVE_ONLY → OFF
```

Wyjątek renderera powoduje pauzę na 5 sekund i stopniową degradację.
`NATIVE_ONLY` nie wykonuje żadnych własnych wywołań rysujących.

## Co zostało usunięte z poprzedniej implementacji

- eliptyczne tło rasteryzowane 37 pasami;
- koła po 24 segmenty;
- linie dzielone na wiele prostokątów;
- obszar `SEARCH` rasteryzowany 25 pasami;
- obrys `SEARCH` z 32 segmentów;
- stożki wypełniane 18 pasami i bokami z kolejnych prostokątów;
- odczyt headingu gracza wykonywany bezpośrednio w rendererze;
- ograniczenie HUD-u do stałych około 15 FPS jako substytut optymalizacji.

## Weryfikacja i granice

Sprawdzenia lokalne dla wdrożonej zmiany:

- składnia JavaScript przechodzi `node --check`;
- repozytorium nie zawiera już wywołań starych funkcji rasteryzujących;
- `git diff --check` nie zgłasza błędów białych znaków;
- konfiguracja dostarczana z modem ma `hud.enabled=1` i `draw_budget=24`;
- renderer wywołuje `Hud.DrawRect` z wartościami w przestrzeni `640×448`;
- encje znalezione przez `*_NO_SAVE` nie są zwalniane przez `MARK_*`, ponieważ
  skrypt nie przejmuje ich ownershipu.

Repozytorium nie zawiera uruchomionej instancji gry, więc lokalna weryfikacja
nie potwierdza zachowania renderera wewnątrz UE4.
