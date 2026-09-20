# World GPS Navigation DE

Nawigacja świata dla **GTA San Andreas: The Definitive Edition** działająca jako skrypt CLEO Redux x64. Zamiast prowadzić wzrok po minimapie, pokazuje krótką ścieżkę markerów 3D na drodze przed pojazdem.

## Co zawiera

- odczyt zwykłego waypointu przez opcjonalny adapter `IS_WAYPOINT_ACTIVE` / `GET_WAYPOINT_COORDS`;
- dynamiczny zasięg prowadzenia: około 62 m przy małej prędkości i do około 128 m przy szybkiej jeździe;
- lokalną ścieżkę z najbliższych węzłów samochodowych GTA (`GET_NTH_CLOSEST_CAR_NODE`), odświeżaną podczas jazdy;
- niebieskie markery trasy oraz żółty marker celu, gdy cel znajduje się w aktywnym zasięgu;
- tekst `GPS`, dystans do celu i najbliższy wykryty zakręt;
- wygaszanie prowadzenia poza pojazdem, przeładowanie ustawień przez F11 i opcjonalny tryb ręcznego celu do diagnostyki.

## Instalacja

Wymagane są:

- CLEO Redux x64 dla SA:DE;
- Ultimate ASI Loader x64 jako `version.dll`;
- plugin `IniFiles64.cleo`.

Uruchom:

```sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

Skrypt zostanie skopiowany do `Gameface/Binaries/Win64/CLEO/WorldGPSNavigation[fs].js`, a konfiguracja do tego samego katalogu jako `WorldGPSNavigationDE.ini`.

## Sterowanie

- ustaw waypoint normalnie na mapie GTA;
- jedź pojazdem — markery pojawią się przed samochodem;
- **F11** przeładowuje plik INI;
- **F7** ma znaczenie tylko po włączeniu `[manual_target] enabled=1`: zapisuje punkt 60 m przed pojazdem jako cel w pamięci skryptu.

## Ważne ograniczenie SA:DE

Publiczna definicja `sa_unreal` CLEO Redux udostępnia markery 3D, węzły dróg i poziom gruntu, ale nie dokumentuje natywu odczytującego waypoint z minimapy. Dlatego skrypt nie czyta pamięci UE4 i nie wpisuje wersjozależnych adresów. Jeżeli zainstalowany runtime nie udostępnia `IS_WAYPOINT_ACTIVE` i `GET_WAYPOINT_COORDS` (albo kompatybilnego bridge'a blipów), w `cleo_redux.log` pojawi się komunikat o braku gettera, a trasa pozostanie ukryta.

W takim środowisku można chwilowo użyć ręcznego celu w INI:

```ini
[manual_target]
enabled=1
x=1234
y=-567
z=20
```

To tryb diagnostyczny, nie zamiennik normalnego waypointu. Sama ścieżka nie jest pełnym solverem grafu GPS: jest krótkim prowadzeniem z lokalnych węzłów drogowych, więc nie obiecuje poprawnej trasy przez każde skrzyżowanie. Dzięki temu mod nie udaje możliwości, których publiczne API SA:DE nie gwarantuje.

## Źródła techniczne

- CLEO Redux obsługuje JavaScript i udostępnia natywy aktualnego hosta: <https://re.cleo.li/docs/en/api.html>
- Definicja SA:DE to `sa_unreal`, a CLEO generuje plik `sa.d.ts` w katalogu `.config`: <https://re.cleo.li/docs/en/the-definitive-edition-faq.html>
- Wykorzystane natywy w publicznej definicji: `CREATE_USER_3D_MARKER`, `REMOVE_USER_3D_MARKER`, `GET_NTH_CLOSEST_CAR_NODE`, `GET_GROUND_Z_FOR_3D_COORD`.
