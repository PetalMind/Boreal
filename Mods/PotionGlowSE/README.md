# Potion Glow SE

Mikstury leżące w świecie Skyrim SE/AE otrzymują tę samą zieloną poświatę,
której Unread Books Glow 2.2.1 używa dla tomów zaklęć (wariant Medium).
Efekt jest pobierany z aktywnego UnreadBooksGlow.esp; nie kopiujemy jego zasobów.
Autorem Unread Books Glow jest duggelz, konwersję SE opisuje dołączony do niego README.

## Wymagania i instalacja

- SKSE64 zgodny z wersją gry, SkyUI i powerofthree's Papyrus Extender;
- Unread Books Glow SE 2.2.1 z aktywnym UnreadBooksGlow.esp i jego BSA.

Zaimportuj PotionGlowSE.zip w Boreal, aktywuj PotionGlowSE.esp i uruchom przez SKSE.
W MCM otwórz **Potion Glow SE → Podświetlanie**. Ustawienia zapisują się w zapisie gry:

- włączenie poświaty;
- uwzględnianie trucizn (domyślnie wyłączone);
- ograniczenie do widocznych przedmiotów (domyślnie włączone);
- zasięg 256–2400 jednostek gry (domyślnie 1200);
- odstęp odświeżania 0,5–3 s (domyślnie 1 s).

Podświetlane jest maksymalnie 128 załadowanych przedmiotów w zasięgu, także z DLC
oraz innych modów. Żywność, ekwipunek, pojemniki i towary handlarzy są pomijane.
Zebranie mikstury, wyjście poza zasięg lub wyłączenie moda usuwa efekt przy
kolejnym odświeżeniu. Mod nie podnosi ani nie zużywa przedmiotów. MCM pokazuje
komunikat, jeżeli wymagany efekt jest niedostępny.

Przed odinstalowaniem wyłącz podświetlanie w MCM, zamknij menu, odczekaj
jedno odświeżenie i zapisz grę. Nie wyłączaj Unread Books Glow, gdy Potion Glow
nadal jest aktywny.

## Budowanie

`./build.sh` wymaga Wine, Caprica i Python 3. Ścisła kompilacja Papyrusa
sprawdza typy i traktuje ostrzeżenia jako błędy. Importy w Source/CompilerImports
służą wyłącznie kompilacji i nie trafiają do paczki; nie zastępują skryptów gry.
Źródłem wersji tego moda jest VERSION. Archiwum zawiera ESP, trzy skrypty PEX,
SEQ uruchamiający MCM i dokumentację.

Sygnatury EffectShader.Play/Stop odpowiadają skryptowi gry, dostępnemu również
w [źródłach Enderal SE](https://git.eddoursul.win/enderal/enderalse/src/commit/5547c24dd35d590c7efe393b6047f429a01c5ee9/source/scripts/effectshader.psc).
