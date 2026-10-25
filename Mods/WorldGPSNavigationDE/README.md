# World GPS Navigation DE

Proste prowadzenie do waypointu na mapie w **GTA San Andreas: The Definitive Edition**, działające jako skrypt CLEO Redux x64. Pokazuje linię markerów 3D bezpośrednio w kierunku celu, dystans oraz żółty marker celu, gdy ten znajdzie się w zasięgu. To wskazówka kierunku do punktu, nie solver dróg ani instrukcje skrętów.

## Co zawiera

- odczyt waypointu z tablicy blipów SA:DE dla rozpoznanego buildu gry;
- dynamiczny zasięg prowadzenia: około 62 m przy małej prędkości i do około 128 m przy szybkiej jeździe;
- bezpośrednią linię markerów do waypointu, odświeżaną podczas jazdy;
- niebieskie markery trasy oraz żółty marker celu, gdy cel znajduje się w aktywnym zasięgu;
- tekst `GPS` z dystansem do celu;
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

Skrypt zostanie skopiowany do `Gameface/Binaries/Win64/CLEO/WorldGPSNavigation[fs][mem].js`, a konfiguracja do tego samego katalogu jako `WorldGPSNavigationDE.ini`.

## Sterowanie

- ustaw waypoint normalnie na mapie GTA;
- jedź pojazdem — markery pojawią się przed samochodem;
- **F11** przeładowuje plik INI;
- **F7** ma znaczenie tylko po włączeniu `[manual_target] enabled=1`: zapisuje punkt 60 m przed pojazdem jako cel w pamięci skryptu.

## Obsługa waypointu i zgodność buildu

SA:DE nie udostępnia waypointu przez publiczne natywy CLEO. Skrypt odczytuje go z tablicy blipów pamięci gry i włącza ten odczyt wyłącznie dla buildu `1.0.113.21181` oraz po sprawdzeniu sygnatury skryptu gry. Do dostępu do pamięci wymaga CLEO Redux z uprawnieniem `mem`; nazwa instalowanego pliku zawiera `[mem]`. Na innych buildach lub przy niezgodnej sygnaturze odczyt zostaje wyłączony, a markery nie są wyświetlane. CLEO Redux opisuje API pamięci dla hostów x64, w tym gier z trylogii DE, a wersja hosta jest dostępna do sprawdzania w skryptach.

W trybie diagnostycznym można zamiast waypointu użyć ręcznego celu w INI:

```ini
[manual_target]
enabled=1
x=1234
y=-567
z=20
```

F7 zapisuje punkt 60 m przed pojazdem tylko do bieżącego uruchomienia skryptu. Ten tryb nie zastępuje waypointu mapy.

## Źródła techniczne

- CLEO Redux obsługuje JavaScript, sprawdzanie wersji hosta i dostęp do pamięci x64: <https://re.cleo.li/docs/en/api.html> oraz <https://re.cleo.li/docs/en/using-memory-64.html>
- Uprawnienie `mem` można zadeklarować w nazwie skryptu: <https://re.cleo.li/docs/en/permissions.html>
- Definicja SA:DE to `sa_unreal`, a CLEO generuje plik `sa.d.ts` w katalogu `.config`: <https://re.cleo.li/docs/en/the-definitive-edition-faq.html>
- Układ tablicy blipów i kontrola buildu bazują na opisanym odczycie waypointu dla SA DE Steam `1.0.113.21181`: <https://www.nexusmods.com/grandtheftautothetrilogy/mods/817?tab=logs>
- Pozostałe natywy używane przez skrypt obejmują `CREATE_USER_3D_MARKER`, `REMOVE_USER_3D_MARKER` i `GET_GROUND_Z_FOR_3D_COORD`.
