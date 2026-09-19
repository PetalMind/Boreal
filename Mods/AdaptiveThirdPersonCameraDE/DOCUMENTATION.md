# Dokumentacja techniczna — Adaptive Third-Person Camera DE

## 1. Cel modyfikacji

`Adaptive Third-Person Camera DE` jest skryptem CLEO Redux dla pecetowej wersji
`Grand Theft Auto: San Andreas — The Definitive Edition`. Dobiera pozycję i
punkt patrzenia kamery zależnie od stanu gracza, prędkości pojazdu, kierunku
ruchu, ręcznego sterowania oraz kolizji ze światem.

Mod nie zmienia fizyki, sterowania pojazdem, broni, misji, zapisów gry ani
parametrów ruchu gracza. Steruje wyłącznie publiczną kamerą skryptowalną.

## 2. Wymagania i instalacja

Wymagane są:

- GTA San Andreas: The Definitive Edition na PC,
- CLEO Redux x64,
- Ultimate ASI Loader jako `version.dll`,
- `IniFiles64.cleo` w `CLEO/CLEO_PLUGINS`.

W Boreal należy zaimportować `AdaptiveThirdPersonCameraDE.zip`. Pliki są
wdrażane do:

```text
Gameface/Binaries/Win64/CLEO/adaptive_third_person_camera[fs].js
Gameface/Binaries/Win64/CLEO/AdaptiveThirdPersonCamera.ini
```

Przy instalacji ręcznej można użyć `install.sh`. Skrypt sprawdza obecność
`SanAndreas.exe`, CLEO Redux oraz IniFiles64, tworzy kopię poprzedniego pliku
JS i nie nadpisuje istniejącego INI użytkownika.

## 3. Przepływ jednej klatki

Skrypt działa w pętli `wait(0)`, korzystając z częstotliwości odświeżania gry.

```text
walidacja gry i gracza
        |
AnchorResolver: pojazd siedzący albo postać
        |
MotionAnalyzer: speed, acceleration, drift, reverse, airborne
        |
Interaction State Machine + Manual Camera Override
        |
Camera Director: base profile + modifiers + handoff
        |
Collision System: cache 30 Hz i probe'y kamery
        |
Spring System i renderer kamery
```

Na końcu klatki używane są `SET_FIXED_CAMERA_POSITION` oraz
`POINT_CAMERA_AT_POINT`. Jeżeli kamera nie powinna być sterowana przez mod,
wykonywany jest bezpieczny powrót do kamery gry.

## 4. Kotwica kamery i stany pojazdu

Kotwica określa obiekt, względem którego wyliczana jest pozycja kamery:

```text
IS_CHAR_ON_FOOT = true             -> kotwicą jest postać
IS_CHAR_ON_FOOT = false oraz
sygnał siedzenia/interakcji         -> kotwicą jest pojazd
```

Mod rozdziela dwa rodzaje informacji:

| Native | Znaczenie |
| --- | --- |
| `IS_CHAR_ON_FOOT` | Autorytatywny sygnał, że postać zakończyła wysiadanie i kamera musi przejść na postać. |
| `IS_CHAR_SITTING_IN_ANY_CAR` | Faktyczne siedzenie w pojeździe i możliwość użycia pojazdu jako kotwicy. |
| `IS_CHAR_IN_ANY_CAR` oraz odpowiedniki łodzi, helikoptera i samolotu | Trwająca interakcja z pojazdem, np. otwieranie albo zamykanie drzwi. |

`IS_CHAR_IN_ANY_CAR` nie jest samodzielnie używany do utrzymywania kotwicy.
W części wersji CLEO Redux także wynik `IS_CHAR_SITTING_IN_ANY_CAR` nie jest
wiarygodny, dlatego `IS_CHAR_ON_FOOT` ma pierwszeństwo i odcina uchwyt pojazdu
natychmiast po faktycznym zakończeniu wysiadania.

Stany logiczne:

| Stan | Warunek | Kotwica |
| --- | --- | --- |
| `driving` | Gracz siedzi w pojeździe | pojazd |
| `entering` | Nie siedzi, ale trwa interakcja rozpoczęta z pozycji pieszej | postać |
| `exiting` | Nie siedzi, ale trwa interakcja rozpoczęta podczas jazdy | postać w logice, z pamięcią pojazdu w handoffie |
| `onFoot` | Brak interakcji z pojazdem | postać |

Stan `entering` albo `exiting` jest zatrzaskiwany na początku interakcji.
Nie jest wyliczany ponownie z `previouslySitting` w każdej klatce, więc kilka
klatek trwającej animacji wysiadania nie może zmienić `exiting` w błędne
`entering`. `IS_CHAR_IN_ANY_CAR` nie jest dowodem siedzenia; pozostaje sygnałem
trwającej interakcji, także podczas otwierania i zamykania drzwi.

### 4.1. Płynny handoff

Przy zmianie kotwicy, np. `car -> onFoot`, mod nie wykonuje pełnego resetu.
Podczas `exiting` zachowuje poprzednią pozycję i kierunek pojazdu, a następnie
przez domyślne 320 ms miesza je z pozycją i kierunkiem postaci:

```text
vehicle anchor ----smoothstep----> ped anchor
             320 ms
```

W tym samym czasie interpolowany jest pełny snapshot profilu: dystans,
wysokość, target height, look-ahead, velocity lead, shoulder offset, wpływ
sterowania oraz tracking osi pionowej. Docelowa pozycja trafia potem do jednej
sprężyny. Nie ma osobnej sprężyny starej kamery, osobnej nowej kamery i
dodatkowego lerpa pozycji.

Prędkości sprężyn są redukowane zamiast zerowania:

```text
position velocity x 0.15
target velocity   x 0.25
```

Dzięki temu kamera opuszcza pojazd już w trakcie animacji wysiadania, zachowuje
ciągłość ruchu i nie przenosi pełnej energii poprzedniego pojazdu do kamery
pieszej.

## 5. Analiza ruchu

Każda próbka aktora zawiera pozycję, heading i wektor ruchu. Prędkość jest
liczona z różnicy pozycji, a przy zbyt małej różnicy może korzystać z
`GET_CAR_SPEED` albo `GET_CHAR_SPEED`.

```text
vehicle velocity = Car.GetSpeedVector()
on-foot velocity = Char.GetVelocity()
fallback velocity = (positionNow - positionPrevious) / deltaTime
signedSpeed = dot(horizontalVelocity, vehicleForward)
```

Dodatnia prędkość podpisana oznacza jazdę do przodu, a ujemna cofanie.

### 5.1. Slip angle i drift

Kąt poślizgu jest wyliczany pomiędzy headingiem pojazdu i kierunkiem faktycznej
prędkości:

```text
slipAngle = atan2(abs(cross(forward, stableVelocityDirection)),
                  dot(forward, stableVelocityDirection))
```

Kierunek prędkości jest zapamiętywany przy małej wartości velocity, aby
normalizacja zera nie powodowała losowego obrotu kamery. Wpływ poślizgu jest
wyłączony poniżej minimalnej prędkości, domyślnie 22 km/h, a następnie rośnie
funkcją `smoothstep` od około 5 do 30 stopni. Maksymalny wpływ kontroluje:

```ini
drift_velocity_influence_percent=42
drift_min_speed_kmh=22
drift_distance_cm=65
velocity_direction_threshold_cms=35
yaw_follow_delay_ms=120
yaw_follow_strength_percent=70
max_steering_yaw_bias_deg=7
```

Siła driftu zwiększa też dystans kamery, maksymalnie o wartość
`drift_distance_cm`. Mod obserwuje `Camera.GetPlayerInCarMode()`, więc zmiana
natywnego trybu kamery przełącza układy `Close`, `Standard` i `Wide` niezależnie
od przypisania klawiatury lub pada. Fizyczne `V` jest wyłącznie fallbackiem,
gdy fixed camera blokuje zmianę natywnego trybu. Fizyczny przycisk kontrolera
`Select/Back` (button ID 13) jest dodatkowym fallbackiem; nie jest traktowany
jako semantyczna akcja z remapem.

Podczas celowania pieszo mod zwalnia `SET_FIXED_CAMERA_POSITION` i pozostawia
grze pełną kontrolę nad pozycją, pitch i natywną kamerą celowania. Nie wywołuje
`Camera.SetPositionUnfixed`, ponieważ weryfikacja w SA:DE wykazała, że cykliczne
wywołanie tej komendy może wymusić celowanie w górę i zablokować sterowanie
pionowe. Po zakończeniu celowania handoff do kamery moda trwa 230 ms.

Profil aim żąda FOV 59°, czyli około 8–16° mniej od profili pieszych. Mod
stosuje go dopiero po runtime probe: odczyt FOV, zmiana o 5° przez
`Camera.SetLerpFov`, a po 220 ms ponowny odczyt. Brak potwierdzonej zmiany
wyłącza FOV na całą sesję.

### 5.2. Przyspieszenie i look-ahead

Surowe przyspieszenie jest ograniczane i filtrowane, aby krawężnik, kolizja lub
chwilowy skok fizyki nie powodował nagłego kopnięcia kamery:

```text
rawAcceleration = clamp((speedNow - speedPrevious) / deltaTime, -20, 20)
alphaDt = 1 - (1 - alpha60) ^ (deltaTime * 60)
filteredAcceleration = lerp(previousFiltered, rawAcceleration, alphaDt)
```

Target jest sumą pozycji bazowej, wysokości targetu, kierunku kamery, faktycznej
prędkości, skrętu i przyspieszenia:

```text
target = basePosition + targetHeight
       + cameraDirection x lookAhead
       + stableVelocityDirection x velocityLead
       + right x steeringLookAhead x steering x speedFactor
       + vehicleForward x accelerationLead
```

Przyspieszenie jest dodatkowo ograniczone filtrem low-pass, więc pojedynczy
frame hitch, krawężnik albo kolizja nie powinny wygenerować dużego offsetu.

## 6. Reverse hysteresis

Kamera nie przełącza się na reverse po pojedynczej próbce z ujemną prędkością.

```ini
reverse_min_speed_kmh=3
reverse_enter_hold_ms=280
reverse_exit_hold_ms=420
reverse_exit_speed_kmh=4
```

Wejście w reverse wymaga utrzymania prędkości wstecznej przez 280 ms. Wyjście
wymaga jazdy do przodu przez 420 ms. Zapobiega to przełączaniu `front -> back`
podczas parkowania i manewrowania.

## 7. Airborne i landing

Dla samochodów, motocykli i rowerów głównym detektorem jest prędkość pionowa
z pamięcią czasu przebywania w powietrzu. `GET_CAR_UPRIGHT_VALUE` nie decyduje
o tym, czy pojazd jest airborne; służy wyłącznie do ograniczenia wpływu
niestabilnego przechyłu na pionowy tracking kamery.

| Stan | Znaczenie |
| --- | --- |
| `grounded` | Zwykły ruch po podłożu. |
| `airborne` | Prędkość pionowa przekroczyła próg wejścia i stan jest utrzymany. |
| `landing` | Po minimalnym czasie lotu opadanie wyhamowało, więc rozpoczęto krótką kompresję. |

Podczas `airborne` zmniejszane jest śledzenie osi Z i look-ahead. Kamera nie
kopiuje bezpośrednio każdego obrotu i przechyłu pojazdu. Podczas `landing`
otrzymuje minimalne obniżenie profilu i wraca do normalnej sprężyny.

Parametry:

```ini
airborne_enter_vertical_kmh=9
airborne_exit_vertical_kmh=4
landing_min_airborne_ms=180
airborne_vertical_tracking_percent=23
landing_duration_ms=220
```

Próg wejścia jest wyższy niż próg wyjścia, czyli działa jako hysteresis.
Landing wymaga wcześniejszego opadania oraz minimalnego czasu `airborne`; samo
przejście do stanu grounded po małym uskoku nie uruchamia animacji lądowania.

## 8. Profile kamery i modyfikatory

Director nie wybiera jednego wykluczającego się stanu typu
`CarFastDriftAirborne`. Najpierw buduje profil bazowy, a następnie nakłada
niezależne modyfikatory:

```text
BaseProfile: CarSlow <-> CarNormal <-> CarFast
Modifiers:   Drift + Reverse + Airborne/Landing + Manual + CollisionEmergency
```

Profil określa dystans, wysokość, wysokość targetu, look-ahead, shoulder bias,
docelowy FOV oraz wpływ ruchu. Profile samochodu są mieszane funkcją
`smoothstep`, więc przekroczenie prędkości nie powoduje nagłego przełączenia.

| Profil | Dystans | Wysokość | Target |
| --- | ---: | ---: | --- |
| Idle | 3,65 m | 1,65 m | 1,25 m |
| Walk | 3,8 m | 1,62 m | 1,24 m |
| Jog | 4,15 m | 1,58 m | 1,22 m |
| Sprint | 4,55 m | 1,52 m | 1,18 m |
| Aim | kamera natywna | natywna | celowanie gry |
| Car slow | 5,25 m | 1,85 m | 0,75 m |
| Car normal | 5,65 m | 1,95 m | 0,78 m |
| Car fast | 6,1 -> 6,45 m | 2,05 -> 2,12 m | 0,82 -> 0,85 m |
| Motorbike | 5,6 m -> 5,0 m | 1,9 m -> 1,7 m | zależny od prędkości |
| Aircraft | 15 m | 5 m | profil powietrzny |

Subtelny shoulder bias pieszo wynosi około:

```text
idle   0,08 m
walk   0,10 m
jog    0,10 m
sprint 0,06 m
```

Aim nie korzysta z shoulder bias profilu ani nie modyfikuje pozycji natywnej
kamery celowania.

## 9. Ręczne sterowanie i delayed recenter

Mod wybiera jedno źródło przez `Game.IsPcUsingJoypad()`: ruch myszy albo prawy
analog, nigdy oba naraz. Dla myszy respektuje też
`Mouse.IsUsingVerticalInversion()`. Po przekroczeniu:

```ini
manual_override_threshold=24
```

mod nie wykonuje `RESTORE_CAMERA`. Odczytuje bieżący kierunek aktywnej kamery,
przejmuje ruch myszy/prawego analoga do własnego yaw/pitch i wyłącza tylko
automatyczne śledzenie pojazdu. Dzięki temu nie ma pierwszego snapu do kamery
standardowej ani drugiego snapu przy powrocie.

Cykl wygląda tak:

```text
AUTO FOLLOW
    |
silny ruch myszy/pada
    |
USER CONTROL       manual_free_ms
    |
RECENTER DELAY     zależny od prędkości
    |
BLEND BACK         manual_blend_ms
    |
AUTO FOLLOW
```

Domyślne wartości:

```ini
manual_free_ms=1100
manual_blend_ms=650
recenter_low_speed_ms=1800
recenter_normal_speed_ms=1100
recenter_high_speed_ms=650
```

Kierunek kamery w chwili ręcznego sterowania jest zapamiętywany. Powrót
automatu zaczyna się więc od aktualnego widoku gracza, a nie od natychmiastowego
obrotu za pojazd. Ruch poziomy jest akumulowany jako yaw, pionowy jako
ograniczony pitch targetu. Pełny `RESTORE_CAMERA` pozostaje tylko mechanizmem
bezpieczeństwa dla cutscenek, śmierci, teleportu i wyłączenia moda.

## 10. Kolizja kamery

Kolizja jest rozdzielona od renderowania. Collision system odświeża wynik co
domyślne 33 ms, a renderer sprężyn działa nadal co klatkę:

```ini
collision_update_ms=33
```

Gdy centralny LOS jest wolny, używany jest desired position. Gdy centralny
promień jest zablokowany, sześć iteracji wyszukiwania znajduje najdalszy
dystans z wolnym środkiem. Dopiero ten kandydat jest sprawdzany pięcioma
punktami:

```text
             góra
              o
              |
lewo o ----- kamera ----- o prawo
              |
              o
             dół
```

Rozmiar obwiedni:

```ini
collision_probe_radius_cm=22
```

Środek, góra i dół są warunkami twardymi. Lewy i prawy probe są miękkie i nie
powodują niepotrzebnego skracania dystansu. Jeśli obwiednia pionowa jest
zablokowana, dystans jest jeszcze maksymalnie trzy razy redukowany.

Dla pojazdu LOS sprawdza statyczny świat z `cars=false`. SA:DE nie pozwala
wykluczyć tylko samochodu gracza, a próba rozpoczęcia drugiego promienia poza
przybliżoną obwiednią nadal trafiała we własne auto i sprowadzała wszystkie
układy do identycznego dystansu awaryjnego. Priorytetem jest poprawny dystans
Close/Standard/Wide; inne pojazdy nie są więc przeszkodami dla tego LOS.

Przy korekcie do geometrii odejmowany jest margines bezpieczeństwa, domyślnie
20 cm. Gdy żaden kandydat nie osiąga minimalnego wyniku, używany jest osobny
profil awaryjny: dystans około 1,45 m, wysokość obniżona, shoulder i look-ahead
wyzerowane. Dzięki temu kamera nie wciska się w target ani nie przenosi
niebezpiecznego offsetu do ciasnego interioru.

```ini
collision_safety_margin_cm=20
collision_emergency_distance_cm=145
```

Wpadnięcie w przeszkodę korzysta z szybszej sprężyny. Powrót po zaniku kolizji
korzysta z wolniejszej sprężyny profilu pozycji:

```ini
position_frequency_hz_x100=450
position_damping_ratio_percent=100
collision_frequency_hz_x100=700
collision_damping_ratio_percent=100
```

## 11. System sprężyn

Pozycja kamery i punkt patrzenia mają niezależne, analitycznie integrowane
sprężyny drugiego rzędu. Obliczenie używa częstotliwości i współczynnika
tłumienia, a nie prostego Eulera zależnego od FPS:

```text
position_frequency_hz_x100=450  -> 4,50 Hz
position_damping_ratio_percent=100 -> critically damped
target_frequency_hz_x100=520
target_damping_ratio_percent=100
```

Oś X/Y używa pełnego celu. Oś Z jest ograniczana przez
`vertical_tracking_percent`:

```text
XY target = target XY
alphaZ = 1 - (1 - verticalTracking60) ^ (deltaTime * 60)
Z target = lerp(current Z, target Z, alphaZ)
```

Delta time jest ograniczany do 1–50 ms. Po dłuższym hitchu prędkości sprężyn
są miękko wygaszane, żeby menu, alt-tab albo doczytywanie nie powodowały
numerycznej eksplozji.

Domyślnie:

```ini
vertical_tracking_percent=58
airborne_vertical_tracking_percent=23
```

Kamera reaguje więc na pion, ale stabilniej niż sam pojazd.

## 12. FOV i ograniczenia API

Profile posiadają wartości FOV oraz wewnętrzny spring. Oficjalna definicja
`sa_unreal` udostępnia `Camera.GetFov` i `Camera.SetLerpFov`.

Dlatego:

- przy pierwszym żądaniu mod zapisuje FOV i zleca zmianę o 5° w 150 ms,
- po 220 ms odczytuje FOV ponownie,
- dopiero potwierdzony readback włącza FOV profili na resztę sesji,
- brak zmiany lub brak bindingu wyłącza kolejne próby w tej sesji,
- skrypt nie korzysta z niezweryfikowanego adresu pamięci z klasycznej wersji
  GTA SA.

## 13. Mechanizmy bezpieczeństwa

Pełny powrót do kamery gry jest wykonywany, gdy:

- mod jest wyłączony,
- gracz nie jest w grze,
- trwa cutscenka albo fade,
- postać jest martwa,
- brakuje prawidłowej próbki pozycji,
- siedzenie jest potwierdzone, ale nie można uzyskać uchwytu pojazdu,
- nastąpiło przesunięcie kotwicy większe niż `24 m + przewidywany ruch z dt`,
  traktowane jako teleport.

Sekwencja awaryjna:

```text
CAMERA_RESET_NEW_SCRIPTABLES
RESTORE_CAMERA
wyzerowanie stanu sprężyn
```

Ta sekwencja nie jest używana przy zwykłym `car -> onFoot`; tam działa płynny
handoff.

Natywy odczytowe są opcjonalne i mają wartości awaryjne. Natomiast
`SET_FIXED_CAMERA_POSITION` oraz `POINT_CAMERA_AT_POINT` są wymagane dla sesji
moda. Jeżeli którykolwiek z nich zgłosi błąd, skrypt zapisuje to w logu,
zwalnia kamerę i wyłącza bieżącą sesję zamiast kontynuować przez setki klatek
z pozornym fallbackiem.

## 14. Hotkeye i konfiguracja

```text
F9  — włączenie/wyłączenie moda
F11 — ponowne wczytanie AdaptiveThirdPersonCamera.ini
```

Odległości i wysokości są przechowywane w centymetrach, np.:

```ini
walk_distance_cm=380
walk_height_cm=162
```

oznacza to 3,8 m i 1,62 m.

Najważniejsze grupy konfiguracji:

| Sekcja | Zakres |
| --- | --- |
| `[camera]` | handoff, manual override, recenter, sprężyny i kolizja |
| `[vehicle]` | drift, reverse, filtr przyspieszenia i airborne |
| `[on_foot]` | dystans, wysokość i target FOV pieszo |
| `[aim]` | natywna kamera celowania i FOV |
| `[car]` | slow, normal i fast car |
| `[motorbike]`, `[bicycle]` | profile jednośladów |
| `[boat]`, `[helicopter]`, `[aircraft]` | profile pojazdów wodnych i powietrznych |
| `[input]` | F9 i F11 |

## 15. Logi diagnostyczne

Przykładowe komunikaty:

```text
Adaptive Third-Person Camera configuration loaded.
Adaptive Third-Person Camera anchor changed car -> onFoot; starting smooth handoff.
Adaptive Third-Person Camera state=Car+Drift ...
Adaptive Third-Person Camera state=Car+Airborne ...
Adaptive Third-Person Camera safety reset after a large anchor displacement.
```

Log stanu pokazuje profil, dystans, wysokość, target FOV, wartość diagnostyczną
FOV spring, wynik kolizji i stan interakcji z pojazdem.

## 16. Mapa kodu

| Funkcja | Odpowiedzialność |
| --- | --- |
| główna pętla `while (true)` | kolejność operacji w każdej klatce |
| `readActorSample` | pobranie kotwicy i danych ruchu |
| `getPlayerVehicle` | rozpoznanie faktycznego siedzenia |
| `resolveInteractionState` | zatrzaskiwane `driving`, `entering`, `exiting`, `onFoot` |
| `beginAnchorTransition` | rozpoczęcie płynnego handoffu |
| `getAnchorTransitionState` | progres handoffu i snapshot starej kotwicy/profilu |
| `applyCameraDirector` | główne sterowanie kamerą |
| `buildProfile` | profil bazowy i modyfikatory ruchu |
| `buildCameraGeometry` | target, look-ahead i desired position |
| `resolveCameraCollision` | cache, wyszukiwanie centralnego dystansu, obwiednia i emergency profile |
| `springStep` | stabilna sprężyna analityczna XY/Z |
| `beginManualOverride` | przekazanie kontroli graczowi |
| `updateReverseState` | hysteresis cofania |
| `deriveAirState` | airborne i landing |
| `releaseCamera` | pełny fallback do kamery gry |

## 17. Ograniczenia

- Repozytorium nie zawiera uruchomionej instancji GTA SA:DE, więc dokumentacja
  nie deklaruje testu wizualnego w grze.
- FOV jest zmieniany wyłącznie po udanym runtime probe z readbackiem; bez niego
  pozostaje wyłączony przez resztę sesji.
- `safeNative` przechwytuje błędy bindingu JavaScript, ale nie jest traktowany
  jako ochrona przed crashem kodu natywnego. Fallbacki `native()` ograniczają
  się do komend potwierdzonych w oficjalnym `sa_unreal`.
- Mod korzysta z publicznej kamery skryptowalnej i nie używa klasycznych,
  niezweryfikowanych adresów pamięci GTA SA.
