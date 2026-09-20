# Police Pursuit Radar DE v1.12 — Smart Pursuit Radar

Wersja 1.11 zachowuje zoptymalizowane, pasywne śledzenie policji z poprzednich wersji, ale usuwa całą wizualizację obszaru poszukiwań.

## Minimap

Mod używa wyłącznie oryginalnej minimapy GTA San Andreas: Definitive Edition. Nie tworzy dodatkowego radaru ani osobnego panelu HUD.

Na minimapie pozostają tylko kontakty policyjne:

- czerwony — jednostka ma aktualny kontakt z graczem;
- żółty — świeżo utracony kontakt;
- niebieski — śledzona pobliska jednostka bez aktualnego kontaktu;
- opcjonalny mały znacznik przed wybranymi jednostkami pokazuje kierunek ruchu/patrzenia.

## Usunięte w v1.11

Całkowicie usunięto z warstwy prezentacji:

- pierścień obszaru poszukiwań;
- punkty wypełniające / obwód strefy;
- marker ostatniej znanej pozycji;
- animowany punkt skanowania po obwodzie;
- związane z nimi opcje INI i blipy.

Stan `SEARCHING` nadal istnieje wewnętrznie jako część logiki pościgu, ale nie rysuje niczego na minimapie.

## Bezpieczeństwo AI

Mod pozostaje obserwatorem. Nie ustawia tasków policji, driving style, prędkości, wanted level ani nie oznacza jednostek gry jako `NO_LONGER_NEEDED`. Główne markery są blipami współrzędnych, a nie blipami bezpośrednio przypiętymi do policjantów lub radiowozów.

## Sterowanie

F6 — przeładowanie `PolicePursuitRadar.ini` podczas gry.

## Pliki

- `PolicePursuitRadar.js`
- `PolicePursuitRadar.ini`
- `README.md`

## v1.12 — Smart Pursuit Radar

Wersja 1.12 nie dodaje żadnego nowego HUD-u. Cała prezentacja nadal korzysta wyłącznie z oryginalnej minimapy GTA.

Dodane mechanizmy:

- **Closing speed** — dla każdej śledzonej jednostki radar mierzy zmianę odległości policja↔gracz w czasie i wygładza wynik filtrem EMA. Dodatnia wartość oznacza, że jednostka się zbliża, ujemna — że się oddala.
- **Threat Score** — wewnętrzny wynik 0–100 uwzględniający aktualny kontakt, świeżość kontaktu, dystans, szybkość zbliżania oraz typ jednostki. Wynik służy wyłącznie do priorytetyzacji radaru i nie zmienia AI gry.
- **Inteligentny wybór blipów** — limit minimapy jest przydzielany jednostkom o najwyższym zagrożeniu. Kontakty skupione praktycznie w jednym miejscu są częściowo odszumiane, żeby kilka radiowozów w jednym punkcie nie wypierało ważniejszych kontaktów. Aktywne/krytyczne zagrożenia nie są przez ten filtr ukrywane.
- **Rzeczywisty kierunek ruchu** — marker kierunku używa wektora wyliczonego z kolejnych pozycji jednostki. Heading pojazdu/policjanta jest używany tylko jako fallback przy bardzo małej prędkości.
- Cztery dostępne markery kierunku trafiają automatycznie do najwyżej sklasyfikowanych kontaktów.

Implementacja jest obserwacyjna: nie ustawia tasków, prędkości, stylu jazdy, wanted level ani ownershipu jednostek policji.
