# Adaptive Driving Camera DE — v37

Kamera jazdy do **GTA San Andreas: The Definitive Edition**, inspirowana
czytelnością prowadzenia z Watch Dogs 2. Build: `ATC-DE-20260920-37-driving-only`.

Mod działa wyłącznie w pojeździe. Kamera chodzenia, biegania, stania i celowania
pieszo pozostaje pod kontrolą GTA. Usunięto jej presety, ustawienia INI i efekty
FOV; stary INI nie może ponownie włączyć tych zmian.

## Jazda

- Kamera podąża za nadwoziem z tłumieniem, a cel patrzenia wyprzedza zakręt.
  Kierunek obu efektów pochodzi z tych samych wektorów świata.
- Przewidywanie skrętu: 480 ms, skracane przy dużej prędkości do 312 ms;
  maksymalnie 18°, z limitem całego bocznego przesunięcia celu 1,2 m.
- Wrażenie prędkości tworzą przede wszystkim płynny FOV i widok drogi przed autem.
  Dystans rośnie umiarkowanie, więc samochód pozostaje czytelny w kadrze.
- Przyspieszenie dodaje do 1,8° FOV i do 18 cm dystansu; hamowanie odejmuje
  do 0,8° FOV i do 6 cm dystansu. Reakcja na gaz nie ma skoku na progu aktywacji.
- Oddzielne tłumienie pionu ogranicza podskakiwanie kadru na nierównościach.
  Zachowano wykrywanie lotu/lądowania i kolizję kamery ze światem.
- Cofanie nie obraca kamery o 180°; wygasza wyprzedzanie zakrętów i daleki cel.
- Mysz i prawy analog mają pierwszeństwo. Domyślnie ręczny widok nie dostaje
  przesunięć celu od zakrętu. Po puszczeniu sterowania i przy prędkości co najmniej
  5 km/h kamera wraca za pojazd: przerwa 1,1–2,2 s, następnie blend 0,9 s.
  `manual_auto_recenter=0` zachowuje wybrany ręcznie kąt.

| Profil samochodu Standard | Dystans | Wysokość nad kotwicą | Bazowy FOV |
| --- | ---: | ---: | ---: |
| Wolno, do 20 km/h | 5,25 m | 1,85 m | 74° |
| Normalnie, 75 km/h | 5,65 m | 1,90 m | 78° |
| Szybko, od 145 km/h | 5,95 m | 1,95 m | 84° |

Między punktami działa płynna interpolacja. Poślizg i przyspieszenie dodają
ograniczone korekty. Motocykle, rowery, łodzie i pojazdy latające mają osobne
presety. To autorski preset startowy, nie odczyt parametrów kamery WD2.

## Instalacja

Wymagane: obsługiwana wersja PC SA:DE, **CLEO Redux x64 1.5.0+**, Ultimate ASI
Loader x64 oraz `IniFiles64.cleo` w `CLEO/CLEO_PLUGINS`.

Gotowa paczka: `AdaptiveThirdPersonCameraDE.zip`. Zawiera dokładnie jeden
uruchamiany skrypt `adaptive_third_person_camera[fs].js` i nowy
`AdaptiveThirdPersonCamera.ini` (wersja schematu 2). Można ją importować w Boreal.
Nowy INI musi zastąpić stary; nie należy łączyć starych sekcji `[on_foot]`/`[aim]`.
INI v1 jest odrzucany, a skrypt uruchamiany z nowymi wartościami domyślnymi.

Instalator lokalny:

```sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

Instalator zapisuje kopie zastępowanego skryptu i INI, instaluje nowy preset,
wyłącza stary plik `adaptive_third_person_camera.js` przez zmianę rozszerzenia
na kopię zapasową i sprawdza zgodność wdrożonych plików. Przy ręcznym kopiowaniu
usuń z aktywnego CLEO wcześniejszą wersję bez `[fs]`, aby dwa skrypty nie
sterowały jednocześnie kamerą.

Docelowy katalog: `Gameface/Binaries/Win64/CLEO/`.

## Sterowanie i ograniczenia

- **F5 / V / Select–Back:** Close → Standard → Wide (cykl od bieżącego profilu).
- **F9:** włącz/wyłącz; **F11:** wczytaj INI ponownie.
- `native_camera_backend=1`: awaryjny backend kamery GTA z ograniczonymi
  efektami profilu; nie odwzorowuje całej geometrii backendu skryptowego.
- FOV działa wyłącznie po potwierdzeniu publicznego API odczytem zwrotnym.
  Przy oddaniu kamery mod jednorazowo przywraca zapamiętaną wartość.
- CLEO/Wine może zwracać syntetyczny ruch myszy. Zachowano filtr tego sygnału
  i dostępne źródła ruchu kursora; skuteczność zależy od runtime.
- Kolizja omija pojazdy, ponieważ używane LOS nie pozwala wyłączyć z obliczeń
  tylko własnego auta. Przenikanie kamery przez inne samochody pozostaje możliwe.
- Nie zmienia fizyki, przyczepności, mocy silnika, misji ani zapisów gry.

Sprawdzono składnię JS i instalatora oraz spójność paczki. Nie przeprowadzono
jazdy w działającym SA:DE, więc odczucie w grze i zachowanie API wymagają
potwierdzenia w runtime; nie jest to gwarancja odwzorowania WD2 1:1.

Analiza założeń, źródła i granice implementacji: [DOCUMENTATION.md](DOCUMENTATION.md).
