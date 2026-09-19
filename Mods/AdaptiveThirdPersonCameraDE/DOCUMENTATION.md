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
- `IniFiles64.cleo` w `CLEO/CLEO_PLUGINS`,
- runtime CLEO Redux z działającym `Pad.IsKeyPressed` albo natywem
  `IS_KEY_PRESSED` dla hotkeyów.

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

Na końcu klatki używane są `Camera.SetFixedPosition` oraz
`Camera.PointAtPoint(..., 2)`. Jest to jedyne miejsce zapisujące transformację
kamery. `Camera.PersistPos` i `Camera.PersistTrack` pozostają wyłączone, dzięki
czemu kamera natywna oraz skryptowa nie nadpisują sobie wzajemnie pozycji w
tej samej klatce. Jeżeli dany build CLEO Redux nie udostępnia metod klasy
`Camera`, skrypt używa publicznych native'ów jako jawnego fallbacku.

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
| `IS_CHAR_IN_ANY_CAR` oraz odpowiedniki łodzi, helikoptera i samolotu | Trwająca interakcja z pojazdem, np. otwieranie albo zamykanie drzwi; fallback kotwicy, gdy postać nie jest na piechotę. |

`IS_CHAR_IN_ANY_CAR` nie jest samodzielnie używany do utrzymywania kotwicy:
musi wystąpić razem z `IS_CHAR_ON_FOOT = false`. W części wersji CLEO Redux
wynik `IS_CHAR_SITTING_IN_ANY_CAR` nie jest wiarygodny, dlatego broad vehicle
state pozostaje fallbackiem podczas wsiadania i jazdy, a `IS_CHAR_ON_FOOT` ma
pierwszeństwo i odcina uchwyt pojazdu natychmiast po faktycznym rozpoczęciu
wysiadania.

Stany logiczne:

| Stan | Warunek | Kotwica |
| --- | --- | --- |
| `driving` | Gracz siedzi w pojeździe albo działa fallback interakcji przy `IS_CHAR_ON_FOOT = false` | pojazd |
| `entering` | Interakcja rozpoczęta z pozycji pieszej | postać, następnie pojazd po utracie `IS_CHAR_ON_FOOT` |
| `exiting` | Interakcja rozpoczęta podczas jazdy i `IS_CHAR_ON_FOOT = true` | postać z pamięcią pojazdu w handoffie |
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
`drift_distance_cm`. Mod obserwuje `Camera.GetPlayerInCarMode()` wyłącznie
diagnostycznie. Jego build-zależnej wartości liczbowej nie mapuje automatycznie
na lokalne układy `Close`, `Standard` i `Wide`, bo mogłoby to zgubić zmianę
wykonaną przez fixed camera albo przełączyć niewłaściwy układ. Fizyczne `V`
oraz fizyczny przycisk kontrolera `Select/Back` (button ID 13) są jawnie
obsługiwanymi fallbackami i przełączają lokalny layout przez jeden kontroler.

Podczas celowania pieszo mod zwalnia `Camera.SetFixedPosition` i pozostawia
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
Modifiers:   Drift + Reverse + Airborne/Landing + Manual
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
| Car fast | 6,1 m | 2,05 m | 0,82 m |
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

## 9. Ręczne sterowanie i trwały vehicle free-look

Mod wybiera jedno źródło przez `Game.IsPcUsingJoypad()`: ruch myszy albo prawy
analog, nigdy oba naraz. Dla myszy respektuje też
`Mouse.IsUsingVerticalInversion()`. Po przekroczeniu:

```ini
manual_override_threshold=24
```

przejmowane są ruchy pionowe i ogólny ruch prawego analoga. Podczas jazdy
poziomy i pionowy ruch myszy oraz prawego analoga ma osobne progi neutralne.
Aktywacja pojazdu wymaga jednej próbki rzeczywistego ruchu ponad deadzone.
Vehicle free-look nie wygasa po puszczeniu sterowania: mod nie uruchamia
opóźnionego recenteringu i nie odbiera graczowi możliwości kolejnego obrotu.
Pieszo nadal obowiązuje pełny skonfigurowany próg. W pojeździe mod utrzymuje
osobny kontroler orbity ze stanami `AUTO` i `MANUAL`, przy czym `MANUAL` pozostaje aktywny
aż do zmiany kotwicy albo zwolnienia kamery.
Przy wejściu w `MANUAL` yaw i pitch są wyliczane z aktualnej pozycji oraz punktu
widoku aktywnej kamery, więc nie ma zerowania kierunku ani snapu za samochód.
W `MANUAL` heading pojazdu nie zapisuje yaw i nie uruchamia wymuszonego powrotu.
Pitch orbity jest ograniczony do `-0.20..0.65` radiana. Mod nie wykonuje
`RESTORE_CAMERA` przy zwykłym obrocie. Pozycja orbity jest dopiero przekazywana
do `SetFixedPosition`, a `PointAtPoint` celuje w środek pojazdu.

Cykl wygląda tak:

```text
AUTO FOLLOW
    |
rzeczywisty ruch myszy/pada
    |
MANUAL             trwały yaw/pitch orbity
    |
zmiana kotwicy / releaseCamera()
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

Kierunek kamery w chwili ręcznego sterowania jest zapamiętywany z aktywnej
pozycji i punktu widoku. Ruch poziomy jest akumulowany jako yaw orbity, a
pionowy jako pitch pozycji kamery, nie tylko pitch targetu. Kamera nadal jest
renderowana przez `SetFixedPosition` i `PointAtPoint`, ale pozycja nie jest już
co klatkę resetowana za samochód. `Mouse.GetMovement()` jest preferowanym
jedynym źródłem ruchu myszy/prawego analoga; natywne odczyty są fallbackiem
kompatybilności. Pełny `RESTORE_CAMERA` pozostaje tylko mechanizmem
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
20 cm. Gdy żaden kandydat nie osiąga minimalnego wyniku, resolver wyznacza
punkt awaryjny w odległości około 1,45 m, ale nie zastępuje nim całego profilu
jazdy ani nie zmienia wysokości, shoulder lub look-ahead. Pojedynczy alarm ma
220 ms tolerancji, jeśli dotychczasowa ścieżka kamery nadal jest wolna. Dopiero
utrzymująca się albo faktycznie blokująca bieżącą pozycję przeszkoda może
przesunąć kamerę do bezpieczniejszego punktu.

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
`Camera.SetFixedPosition` oraz `Camera.PointAtPoint` (albo ich publiczny
fallback natywny) są wymagane dla sesji moda. Jeżeli którykolwiek z nich zgłosi błąd, skrypt zapisuje to w logu,
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

`F5` podczas jazdy przełącza bezpośrednio układy dystansu `Standard -> Wide ->
Close -> Standard` i zapisuje wybrany profil w logu. Fizyczny `V` oraz
przycisk Select/Back kontrolera używają tego samego lokalnego przełącznika.
Skrypt nie wywołuje przy tej zmianie `SetPlayerInCarMode`, ponieważ natywne
wartości GTA (`Top-Down`, `GTA Classic`, `Behind Car`) nie są profilami
`Close/Standard/Wide` i nie mogą równocześnie sterować kamerą ze skryptem.
`F5`, `F9` i `F11` używają
narastającego wykrywania (`down && !lastDown`); gdy API klawiatury nie jest
dostępne, są wyłączane z jednoznacznym wpisem w logu.

`F11` buduje najpierw kompletny kandydat konfiguracji, waliduje wszystkie
odległości, wysokości, FOV i zależności progów, a dopiero potem podmienia
aktywny obiekt `config`. Błąd odczytu albo wersji INI nie może więc pozostawić
częściowo załadowanych ustawień; poprzednia konfiguracja pozostaje aktywna.

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
| `[input]` | F5, F9, F11 i diagnostyka dostępności API klawiatury |

## 15. Logi diagnostyczne

Przykładowe komunikaty:

```text
Adaptive Third-Person Camera configuration loaded.
Adaptive Third-Person Camera loaded. build=ATC-DE-20260919-13; F5 cycles vehicle layouts; F9 toggles the camera; F11 reloads the INI.
Adaptive Third-Person Camera applied pose camera=(123.45,456.78,18.20) target=(127.00,460.00,17.10) distance=4.92
Adaptive Third-Person Camera observed native vehicle camera mode=2 (previous=1; local layout unchanged).
Adaptive Third-Person Camera vehicle layout=Wide (F5; script profile only)
Adaptive Third-Person Camera layout geometry revision=1 layout=Wide anchor=(...) desired=(...) resolved=(...) spring=(...) target=(...)
Adaptive Third-Person Camera: keyboard input API unavailable; F5/F9/F11 are disabled.
Adaptive Third-Person Camera anchor changed car -> onFoot; starting smooth handoff.
Adaptive Third-Person Camera state=Car+Drift ...
Adaptive Third-Person Camera state=Car+Airborne ...
Adaptive Third-Person Camera safety reset after a large anchor displacement.
```

Pozycja, kierunek i prędkość aktora są odczytywane przede wszystkim przez
metody instancji `Char`/`Car` dostarczane przez definicje SA:DE. Surowe native'y
są wyłącznie fallbackiem. Zmiana layoutu interpoluje parametry `distance`,
`height` i `targetHeight`, po czym w każdej klatce ponownie buduje współrzędne
świata względem kotwicy. Każda wyliczona pozycja jest sprawdzana względem
aktualnej pozycji aktora, a wynik kolizji jest ograniczany do co najmniej
`anchor.z + 0.40`. Pozycja niefinitywna albo zbyt odległa powoduje zwolnienie
kamery zamiast renderowania świata od spodu.

Log stanu pokazuje profil, dystans, wysokość, target FOV, wartość diagnostyczną
FOV spring, wynik kolizji i stan interakcji z pojazdem.

Po zatrzymaniu postaci używany jest najpierw stabilny profil `OnFootStand`.
Timer bezczynności wymaga 60 sekund ciągłego pozostawania w miejscu, zanim
zostanie aktywowany stan `OnFootIdle`, ale bez jakiegokolwiek ruchu kamery —
geometria tego stanu jest identyczna z `OnFootStand`. Ruch postaci oraz
ręczne poruszenie kamerą resetują pełny minutowy timer. Zmiana kotwicy między
pojazdem i postacią czyści też ręczny obrót należący do poprzedniej kotwicy,
więc `OnFootStand` nie dziedziczy stanu `Car+Manual`. Poziomy ruch myszy lub
prawego analoga przejmuje yaw/pitch bez starego progu 24 jednostek w pojeździe.
W pojeździe składowa pionowa wejścia nie zmienia celu kamery,
więc grunt pod samochodem nie jest błędnie rozpoznawany jako przeszkoda. Po
świadomym ruchu kamera utrzymuje ręczny kąt bez limitu czasu, więc auto-follow
nie odbiera możliwości dalszego obracania. W czasie free-look test kolizji
jest odświeżany w każdej klatce. Chwilowy alarm ma 220 ms tolerancji, dopóki
bieżąca pozycja kamery jest bezpieczna; natychmiastowe przeniesienie następuje
tylko wtedy, gdy zablokowana jest faktyczna bieżąca ścieżka kamery.

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
