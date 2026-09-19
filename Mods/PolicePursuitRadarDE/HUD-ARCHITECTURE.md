# HUD Police Pursuit Radar DE — wdrożona architektura

Dokument opisuje aktualny sposób przygotowania i prezentowania HUD-u w
`PolicePursuitRadar.js` po przebudowie zgodnej z analizą stabilności. Kluczowa
zmiana polega na rozdzieleniu odczytów GTA, modelu prezentacyjnego i samego
renderera.

## Stan bezpieczeństwa

W dostarczonej konfiguracji własny HUD pozostaje wyłączony:

```ini
[hud]
enabled=0
draw_budget=24
```

To jest świadoma konfiguracja bezpieczna. Wcześniejszy renderer wykonywał
setki logicznych fragmentów przez `DRAW_RECT`; log CLEO potwierdził dojście do
96 wywołań nawet przy `units=0`, po czym gra zatrzymywała się lub crashowała.
Sam licznik wywołań nie był więc wystarczającą ochroną.

W kodzie pozostał nowy prostokątny renderer jako etap architektoniczny, ale jest
teraz twardo zablokowany: `CUSTOM_HUD_RENDERER_AVAILABLE = false`. Powodem jest
potwierdzenie, że także ograniczony renderer `DRAW_RECT` powoduje `Fatal error`
w tej konkretnej instalacji. Native blipy są jedynym aktywnym trybem
prezentacji do czasu wdrożenia i potwierdzenia ścieżki sprite-only.

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
rectangular renderer: stała liczba DRAW_RECT
        │
        └── błąd/przekroczenie czasu → degradacja → native blipy / OFF
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

Fallback jest obecnie wymuszony do `NATIVE_ONLY`, ponieważ nie ma
potwierdzonej ścieżki sprite’owej, a `DRAW_RECT` powoduje `Fatal error`.
Wyjątek renderera nadal powoduje pauzę na 5 sekund; `NATIVE_ONLY` nie wykonuje
żadnych własnych wywołań rysujących.

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
- konfiguracja dostarczana z modem ma `hud.enabled=0` i `draw_budget=24`;
- kod ignoruje wymuszenie `hud.enabled=1`, dopóki renderer nie otrzyma
  potwierdzonej ścieżki sprite-only.

Nie deklaruję testu runtime z włączonym HUD-em jako zaliczonego, ponieważ
poprzedni crash występował w konkretnej instalacji GTA, a automatyczny test
nie może wiarygodnie potwierdzić bezpieczeństwa natywu `DRAW_RECT`. Właśnie
dlatego aktywna instalacja pozostaje w trybie native-only, a renderer
`DRAW_RECT` jest zablokowany również w kodzie, niezależnie od INI.
