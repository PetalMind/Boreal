# Analiza kamery jazdy — v40

## Model jazdy a odbiór przez kamerę

Opis WD2 opublikowany przez Xbox Wire przedstawia samochody jako responsywne,
szybko skręcające i ograniczające niekontrolowane poślizgi:
[How Watch Dogs 2 Improves on the Original](https://news.xbox.com/en-us/2016/10/24/watch-dogs-2-preview/).
Nie publikuje algorytmu kamery, geometrii, FOV ani współczynników handlingu.
Wartości tego moda są autorską interpretacją, nie parametrami wydobytymi z WD2.

Przyczepność, moment obrotowy, rozkład masy i reakcja kierownicy należą do
symulacji pojazdu. Kamera może poprawić widoczność wyjścia z zakrętu, poczucie
prędkości i ocenę poślizgu, ale nie zmieni tych właściwości fizycznych. W ramach
modyfikacji kamery zachowano handling GTA. Pełna reprodukcja modelu WD2
wymagałaby osobnej modyfikacji fizyki i pomiarów obu gier.

## Problemy poprzedniej implementacji

1. Pieszy backend pozostawiał GTA obrót, ale nadal zmieniał FOV chodzenia i
   celowania. Zachowany opcjonalny backend pozwalał ponownie włączyć kamerę pieszą.
2. `turnAmount` wynikał z iloczynu wektorowego kierunków świata, a `steering`
   z różnicy skalarnego headingu GTA. Mieszanie konwencji mogło odwracać jeden
   składnik; dodatni obrót świata był też dodawany wzdłuż wektora prawej strony.
3. Preview dochodziło do 36° i horyzontu 820 ms przy dużej prędkości.
   Kilka efektów bocznych sumowało się bez wspólnego limitu.
4. Przekroczenie progu przyspieszenia dodawało natychmiast 8 cm dystansu.
5. Ręczny obrót miał jednocześnie hold, dodatkowy pełny delay i blend;
   dokumentacja błędnie opisywała go jako zawsze trwały.
6. Paczka robocza zawierała też stary skrypt bez `[fs]` z wcześniejszym modelem
   kamery. Wspólne uruchomienie obu wersji oznaczałoby dwóch właścicieli kamery.

## Nowy układ

`readActorSample` kończy działanie przed odczytem ruchu i wejścia kamery, jeśli
nie ma dopuszczonego pojazdu. Animacja wsiadania i sygnał wyjścia pozostawiają
kamerę GTA. Piesze profile/FOV i ich czytniki INI zostały usunięte. Każda zmiana
pojazdu resetuje stan ręcznego obrotu, cofania i lotu.

Prędkość pochodzi przede wszystkim z różnicy pozycji w czasie gry. Szybki filtr
100 ms służy stanom jazdy, wolniejszy 280 ms kompozycji obrazu. Przyspieszenie
pochodzi z różnicy filtrowanej prędkości. Iloczyn wektorowy kolejnych kierunków
nadwozia wyznacza podpisaną prędkość obrotu; ten sam sygnał zasila podążanie
kamery i preview. Nie jest to odczyt kąta skrętu kół ani prognozowanie drogi
z nawigacji — kamera ekstrapoluje rozpoczęty skręt.

Korpus kamery podąża za kierunkiem nadwozia, z niewielkim udziałem rzeczywistego
kierunku ruchu podczas poślizgu. Zadana zwłoka yaw wynosi 150 ms, siła 85%,
a dodatkowy bias obrotu maksymalnie 3°. Odpowiedź jest zależna od czasu klatki.
Pozycja i punkt patrzenia korzystają z osobnych tłumionych sprężyn 4,4/6,5 Hz.
Pion ma tracking 50%, w powietrzu 22%; kolizje zachowują priorytet bezpieczeństwa.

Preview używa horyzontu 480 ms, skracanego przy prędkości do 312 ms. Kąt jest
ograniczony do 18°, a suma przesunięć bocznych celu do 1,2 m. Ograniczenie jest
wspólne dla preview, prędkości i pozostałych składników. W powietrzu i przy
niestabilnej orientacji słabnie prognozowany obrót. Cofanie zachowuje tylną
stronę kamery, zmniejsza look-ahead do 25 cm i usuwa daleki lead.

Prędkość podnosi bazowy FOV 74 → 78 → 84°, przy dystansie 5,25 → 5,65 → 5,95 m.
Kamera zachowuje względnie duże auto w kadrze. Korekta dystansu od przyspieszenia
narasta od zera. Nie dodano sztucznego shake, roll ani wymuszonego motion blur.

Manual ma pierwszeństwo przed podążaniem i domyślnie wyłącza preview celu.
Powrót rozpoczyna się po maksimum z `manual_free_ms` i opóźnienia właściwego
prędkości; czasy nie sumują się. Blend 900 ms korzysta z najkrótszego łuku yaw.
Nowy ruch myszy/analoga przerywa powrót. Poniżej 5 km/h kąt pozostaje ręczny;
`manual_auto_recenter=0` utrzymuje go także podczas jazdy.

## CLEO Redux i zgodność

[Oficjalne wsparcie DE](https://re.cleo.li/docs/en/the-definitive-edition-faq.html)
zaleca JavaScript/TypeScript zamiast przestarzałego wsparcia skryptów CS w DE.
Dostępne API należy odnosić do wygenerowanego `CLEO/.config/sa.d.ts` właściwego
runtime. Mod zachowuje JS, kontrolę `HOST === "sa_unreal"`, `wait(0)`, publiczne
natywy kamery i wykrywanie brakujących wiązań; nie stosuje offsetów klasycznego SA.

[Cykl życia i ładowanie skryptów](https://re.cleo.li/docs/en/script-lifecycle.html)
wyjaśnia potrzebę `wait` oraz ładowanie plików JS z katalogu CLEO. Dlatego paczka
ma jeden aktywny skrypt; instalator wyłącza starszą nazwę przed wdrożeniem.

FOV jest ograniczony do 50–90°. Próba zmiany o 1,5° wymaga odczytu w oczekiwanym
kierunku i w odległości mniejszej niż 0,8° od celu. Niepowodzenie przywraca
wartość sprzed próby i wyłącza efekt w sesji. Oddanie kamery po wyjściu z auta,
wyłączeniu moda lub utracie kontroli przywraca jednorazowo zapamiętany FOV.
Dalsze klatki pieszo nie wywołują zapisu kamery.

INI v2 ma wyłącznie sekcje jazdy. Wszystkie nowe opcje są czytane przez skrypt,
ograniczane do dopuszczalnych zakresów i mają zgodne wartości domyślne.
Starszy schemat zostaje odrzucony z komunikatem; obowiązują wtedy domyślne
wartości v40. F11 zastępuje konfigurację dopiero po zbudowaniu całego kandydata.

Przy wyjściu z auta poprzednia sesja kamery jest rozpoznawana niezależnie od
chwilowego zaniku uchwytu pojazdu. Skrypt odrzuca również przejściowy wektor
gracza `(0,0,0)`, a po utracie kamery pojazdu wykonuje `RESTORE_CAMERA_JUMPCUT`
oraz `SET_CAMERA_BEHIND_PLAYER`. Dzięki temu natywna kamera pieszego nie
dziedziczy stałej pozycji kamery samochodu podczas animacji drzwi.

## Granica walidacji

Wykonano statyczne sprawdzenie składni JavaScript i zsh oraz kontrolę zgodności
plików w paczce ZIP. Nie uruchomiono gry ani sesji CLEO, nie mierzono latencji,
FOV, kolizji czy feelingu na nagraniach z GTA/WD2. Obsługa myszy na Wine,
rzeczywiste działanie natywów i sytuacje misyjne pozostają niezweryfikowane.
To skonfigurowana implementacja, nie udokumentowane porównanie obu silników.
