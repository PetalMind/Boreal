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
IS_CHAR_SITTING_IN_ANY_CAR = true  -> kotwicą jest pojazd
IS_CHAR_SITTING_IN_ANY_CAR = false -> kotwicą jest postać
```

Mod rozdziela dwa rodzaje informacji:

| Native | Znaczenie |
| --- | --- |
| `IS_CHAR_SITTING_IN_ANY_CAR` | Faktyczne siedzenie w pojeździe i możliwość użycia pojazdu jako kotwicy. |
| `IS_CHAR_IN_ANY_CAR` oraz odpowiedniki łodzi, helikoptera i samolotu | Trwająca interakcja z pojazdem, np. otwieranie albo zamykanie drzwi. |

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
velocity = (positionNow - positionPrevious) / deltaTime
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
wyłączony poniżej minimalnej prędkości, domyślnie 18 km/h, a następnie rośnie
funkcją `smoothstep` od około 5 do 30 stopni. Maksymalny wpływ kontroluje:

```ini
drift_velocity_influence_percent=60
drift_min_speed_kmh=18
velocity_direction_threshold_cms=35
```

### 5.2. Przyspieszenie i look-ahead

Surowe przyspieszenie jest ograniczane i filtrowane, aby krawężnik, kolizja lub
chwilowy skok fizyki nie powodował nagłego kopnięcia kamery:

```text
rawAcceleration = clamp((speedNow - speedPrevious) / deltaTime, -20, 20)
filteredAcceleration = lerp(previousFiltered, rawAcceleration, alpha)
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
airborne_vertical_tracking_percent=28
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
| Idle | 3,5 m | 1,5 m | górna część sylwetki |
| Walk | 3,5 m | 1,5 m | 1,28 m |
| Jog | 4,0 m | 1,5 m | 1,28 m |
| Sprint | 4,6 m | 1,4 m | 1,20 m |
| Aim | 2,7 m | 1,45 m | 1,25 m |
| Car slow | 6,2 m | 2,2 m | profil pojazdu |
| Car normal | 7,2 m | 2,25 m | profil pojazdu |
| Car fast | 8,8 m | 2,4 m | profil pojazdu |
| Motorbike | 5,6 m -> 5,0 m | 1,9 m -> 1,7 m | zależny od prędkości |
| Aircraft | 15 m | 5 m | profil powietrzny |

Subtelny shoulder bias pieszo wynosi około:

```text
idle   0,18 m
walk   0,20 m
jog    0,18 m
sprint 0,12 m
aim    0,55 m
```

Podczas celowania mod może zmienić ramię, jeżeli aktualny punkt kamery jest
zasłonięty. Alternatywne ramię musi mieć clearance większy od bieżącego o
domyślne 60 cm, a cooldown dodatkowo zapobiega oscylacji między stronami:

```ini
shoulder_swap_cooldown_ms=450
shoulder_swap_clearance_advantage_cm=60
```

## 9. Ręczne sterowanie i delayed recenter

Mod odczytuje ruch myszy oraz prawego analoga. Po przekroczeniu:

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
manual_free_ms=1200
manual_blend_ms=800
recenter_low_speed_ms=2000
recenter_normal_speed_ms=1300
recenter_high_speed_ms=800
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
promień jest zablokowany, kandydaci są sprawdzani pięcioma punktami:

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

Kamera szuka najdalszego kandydata, dla którego wszystkie probe'y mają czysty
LOS. W aktualnej wersji nie ma binarnego warunku `all clear`: promień centralny
ma wagę 3, a lewy, prawy, górny i dolny po 1. Kandydat jest wystarczająco
bezpieczny od wyniku 4/7, a kamera wybiera najdalszego takiego kandydata.

Przy korekcie do geometrii odejmowany jest margines bezpieczeństwa, domyślnie
20 cm. Gdy żaden kandydat nie osiąga minimalnego wyniku, używany jest osobny
profil awaryjny: dystans około 1,45 m, wysokość obniżona, shoulder i look-ahead
wyzerowane. Dzięki temu kamera nie wciska się w target ani nie przenosi
niebezpiecznego offsetu do ciasnego interioru.

```ini
collision_safety_margin_cm=20
collision_min_score_x10=40
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
Z target  = lerp(current Z, target Z, verticalTracking)
```

Delta time jest ograniczany do 1–50 ms. Po dłuższym hitchu prędkości sprężyn
są miękko wygaszane, żeby menu, alt-tab albo doczytywanie nie powodowały
numerycznej eksplozji.

Domyślnie:

```ini
vertical_tracking_percent=72
airborne_vertical_tracking_percent=28
```

Kamera reaguje więc na pion, ale stabilniej niż sam pojazd.

## 12. FOV i ograniczenia API

Profile posiadają wartości FOV oraz wewnętrzny spring diagnostyczny. Skrypt
może odczytać bieżący FOV przez `GET_CAMERA_FOV`, ale oficjalna definicja
`sa_unreal` nie udostępnia potwierdzonego `SET_CAMERA_FOV`.

Dlatego:

- FOV target jest przechowywany w profilu,
- FOV spring jest liczony i logowany,
- rzeczywisty FOV gry nie jest zmieniany,
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
walk_distance_cm=350
walk_height_cm=150
```

oznacza to 3,5 m i 1,5 m.

Najważniejsze grupy konfiguracji:

| Sekcja | Zakres |
| --- | --- |
| `[camera]` | handoff, manual override, recenter, sprężyny i kolizja |
| `[vehicle]` | drift, reverse, filtr przyspieszenia i airborne |
| `[on_foot]` | dystans, wysokość i target FOV pieszo |
| `[aim]` | kamera celowania i shoulder swap |
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
| `resolveCameraCollision` | cache, clearance score, safety margin i emergency profile |
| `springStep` | stabilna sprężyna analityczna XY/Z |
| `beginManualOverride` | przekazanie kontroli graczowi |
| `updateReverseState` | hysteresis cofania |
| `deriveAirState` | airborne i landing |
| `releaseCamera` | pełny fallback do kamery gry |

## 17. Ograniczenia

- Repozytorium nie zawiera uruchomionej instancji GTA SA:DE, więc dokumentacja
  nie deklaruje testu wizualnego w grze.
- Rzeczywisty FOV gry nie jest zmieniany z powodu braku publicznego
  `SET_CAMERA_FOV` dla `sa_unreal`.
- `safeNative` izoluje pojedyncze wywołania opcjonalnych native'ów. Jeżeli
  środowisko nie udostępni opcjonalnego native'a, skrypt używa wartości
  awaryjnej. Dwa natywy renderujące kamerę mają osobną ścieżkę wymaganych
  błędów i wyłączają bieżącą sesję.
- Mod korzysta z publicznej kamery skryptowalnej i nie używa klasycznych,
  niezweryfikowanych adresów pamięci GTA SA.
