Adaptive Driving Camera DE — v40, tylko pojazdy
Build: ATC-DE-20260920-40-pedestrian-behind-player-guard

Gotowa paczka: AdaptiveThirdPersonCameraDE.zip
Nowy preset: AdaptiveThirdPersonCamera.ini, config_version=2.

Usunięto zmiany kamery pieszej, FOV chodzenia i celowania oraz ich ustawienia.
Po wyjściu z auta mod jawnie oddaje kamerę za pieszym, aby przejście z kamery
pojazdu nie interpolowało przez nieprawidłową pozycję pod mapą.
Nowa kamera jazdy ma spójny kierunek skrętu, ograniczone preview, płynniejsze
czucie przyspieszenia, stabilniejszy pion i powrót za auto po rozglądaniu.

F5 / V / Select-Back: dystans. F9: włącz/wyłącz. F11: wczytaj INI.
manual_auto_recenter=0 wyłącza automatyczny powrót podczas jazdy.

Instalator install.sh kopiuje NOWY INI, zachowując kopię starego.
Wyłącza również starszy adaptive_third_person_camera.js bez [fs].
Nie uruchamiaj jednocześnie starego i nowego skryptu kamery.

Opis parametrów, instalacji i ograniczeń: README.md.
Analiza, źródła i granica walidacji: DOCUMENTATION.md.
Preset inspirowany WD2; nie zmienia fizyki GTA i nie jest kopią WD2 1:1.
Nie przeprowadzono jazdy w działającej grze.
