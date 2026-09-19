# Police Pursuit Radar DE v1.10 — Native Minimap Only

Ta wersja usuwa pomysł drugiego radaru/HUD-u. **Nie pojawia się żaden dodatkowy panel UI.** Cała prezentacja moda korzysta wyłącznie z oryginalnej minimapy GTA SA:DE.

## Jak wygląda radar

- niebieski — wykryta jednostka policji bez aktualnego kontaktu z graczem;
- czerwony — jednostka ma aktualny kontakt;
- żółty — świeżo utracony kontakt / ostatnia znana pozycja;
- aktywna jednostka bardzo blisko gracza dostaje nieco większy natywny blip;
- mały punkt przed policjantem/radiowozem pokazuje kierunek, ale tylko dla kontaktów aktywnych lub świeżo utraconych, żeby nie zaśmiecać mapy.

## Strefa poszukiwań

Po utracie kontaktu mod przechodzi w `SEARCHING` i na **tej samej natywnej minimapie** pokazuje:

- większy punkt ostatniej znanej pozycji gracza;
- pierścień 6–10 żółtych punktów opisujący przybliżony obszar poszukiwań;
- jeden większy punkt przesuwający się po obwodzie jako subtelny efekt „skanowania”.

Promień nadal zależy od liczby gwiazdek (`radius_base_m + stars * radius_per_star_m`).

## Ważne

Mod nadal nie tworzy `ADD_BLIP_FOR_CHAR` ani `ADD_BLIP_FOR_CAR` dla policji. Wszystkie markery są blipami współrzędnych, dzięki czemu radar nie utrzymuje encji pościgu i nie powinien wpływać na streaming ani system wanted.

Custom HUD z v1.9 jest w v1.10 **twardo wyłączony w kodzie**, więc nawet stary plik INI z `hud.enabled=1` nie przywróci dodatkowego prostokątnego radaru.

F6 — przeładowanie ustawień INI.

## Ograniczenie CLEO

Ta wersja modyfikuje zachowanie i markery istniejącej minimapy. Zmiana samego wyglądu bazowej mapy — np. koloru ulic, tła, maski radaru czy własnych ikon teksturowych — wymaga osobnej warstwy assetów / hooka renderera, nie zwykłych natywnych blipów CLEO.
