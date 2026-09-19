Adaptive Third-Person Camera DE — v28 Native Mouse Bridge
=========================================================

Dlaczego v27 nadal nie działało poprawnie
------------------------------------------
Log z SA:DE 1.0.113.21181 pokazał, że przy kamerze skryptowej
Mouse.GetMovement()/GET_PC_MOUSE_MOVEMENT nie zwraca prawidłowego ruchu 2D.
W spoczynku i podczas wielu ruchów pojawiały się niemal identyczne wartości X/Y
(np. 1.4/1.4 albo 3.0/3.0), przez co kamera fałszywie przechodziła w Manual.
Input64/GetCursorPos tylko sporadycznie ujawnił rzeczywisty kierunek kursora.

Rozwiązanie v28
---------------
v28 nie próbuje już rekonstruować obrotu kamery z uszkodzonego delta-inputu.
Zastosowany jest Native Mouse Bridge:

1. Dynamiczna kamera Watch-Dogs-style działa jako kamera skryptowa.
2. Pewny początek ruchu myszy jest wykrywany z wariacji sygnału / kursora.
3. Mod natychmiast oddaje kamerę GTA.
4. GTA obsługuje wtedy natywne, płynne obracanie myszą w dowolnym kierunku.
5. Po ~620 ms bez nowego ruchu mod odczytuje aktualną pozycję i kierunek
   natywnej kamery.
6. Kamera skryptowa wraca z tego samego kąta i dopiero później korzysta z
   filmowego recenteringu.

Dzięki temu nie ma już integracji błędnego +X/+Y jako yaw/pitch.

Dodatkowe poprawki
------------------
- odfiltrowanie nierealnych pików prędkości postaci (w logu pojawiało się
  ~100–117 km/h podczas zwykłego sprintu);
- prawy analog nadal jest obsługiwany bezpośrednio, ponieważ jego dane są
  niezależne i stabilniejsze;
- przy przejęciu kamery po native free-look spring startuje z aktualnej pozycji
  natywnej kamery, więc nie powinno być snapu;
- w samochodzie podczas native free-look nadal działa contextual native tweak;
- po zatrzymaniu postaci manualny kąt pozostaje bez wymuszonego natychmiastowego
  centrowania;
- F5: Close / Standard / Wide; F9: toggle; F11: reload INI.

Ustawienia zalecane
-------------------
[on_foot]
native_camera_backend=0

[vehicle]
native_camera_backend=0

Backend=1 pozostaje tylko awaryjnym trybem całkowicie natywnym.

Co sprawdzić w grze
-------------------
1. Stań nieruchomo i obracaj myszą lewo/prawo/góra/dół.
2. Zrób pełny obrót kamery podczas biegu.
3. Obracaj kamerę w samochodzie podczas jazdy.
4. Puść mysz i obserwuj, czy przejście z native do scripted jest płynne.

Nowe wpisy diagnostyczne w logu:
- scripted -> native mouse bridge
- native mouse bridge active
- native mouse bridge -> scripted handoff
- input diagnostic bridgeGesture=...

Jeśli zachowanie nadal będzie złe, te wpisy pokażą już nie tylko wartości
myszy, ale również moment faktycznego przełączania właściciela kamery.
