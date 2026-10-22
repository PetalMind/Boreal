# Auto Potion SE

Automatycznie używa mikstur przy niskim poziomie zdrowia, magicki lub kondycji.
Domyślnie działa w walce: kontroluje stan co 0,5 s, a poza walką sprawdza
wyłącznie, czy walka się rozpoczęła. Ekwipunek przegląda tylko wtedy, gdy
aktywny próg został osiągnięty. Po użyciu mikstury odczekuje ustawiony cooldown.

Jeśli w ekwipunku jest mikstura, która uzupełni brakującą wartość, wybierana jest
najsłabsza wystarczająca. Gdy żadna mikstura nie wystarczy, wybierana jest
najsilniejsza dostępna dla danego zasobu. Zdrowie ma pierwszeństwo przed magicką
i kondycją.

## Wymagania

- Skyrim Special Edition lub Anniversary Edition;
- SKSE64 zgodny z wersją gry;
- Papyrus Extender;
- SkyUI z MCM.

## Ustawienia

W MCM można włączyć osobno automatyczne mikstury zdrowia, magicki i kondycji,
ustawić próg każdego zasobu, cooldown, działanie tylko podczas walki oraz wybór
najsłabszej wystarczającej mikstury.

Domyślnie: zdrowie 30%, magicka 20%, kondycja wyłączona, cooldown 5 s,
tylko podczas walki i najsłabsza wystarczająca mikstura.

## Instalacja i budowanie

Zaimportuj AutoPotionSE.zip w Boreal, włącz AutoPotionSE.esp i uruchom grę
przez SKSE. Ustawienia MCM są przechowywane w zapisie gry.

build.sh kompiluje skrypty kompilatorem Caprica i buduje paczkę instalacyjną.
Można ustawić CAPRICA_EXE przed uruchomieniem skryptu.
