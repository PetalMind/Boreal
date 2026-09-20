# Damage Blood & Regeneration DE

Mod CLEO Redux x64 dla **GTA San Andreas: The Definitive Edition**. Dodaje
dwa efekty:

- po otrzymaniu obrażeń ekran dostaje czerwony impuls, winietę i nieregularne
  plamy/smugi krwi;
- po domyślnych 5 sekundach bez kolejnego ubytku zdrowia życie zaczyna
  regenerować się z szybkością 8 HP/s, aż do zaobserwowanego maksimum postaci.

Nasilenie krwi jest oparte na prawdziwym odczycie HP. Duże obrażenia zostawiają
silniejszy efekt, a obrażenia zatrzymane przez kamizelkę również wywołują
krótki impuls, jeżeli runtime udostępnia `GET_CHAR_ARMOUR`. Efekt wygasa
stopniowo, ale pozostaje silniejszy przy niskim zdrowiu.

## Instalacja

Wymagane są:

- GTA SA:DE na PC;
- Ultimate ASI Loader x64 jako `version.dll`;
- CLEO Redux x64;
- `IniFiles64.cleo` w `Gameface/Binaries/Win64/CLEO/CLEO_PLUGINS`.

Najprościej zaimportować `DamageBloodRegenDE.zip` w Boreal. Przy instalacji
ręcznej uruchom:

```sh
./install.sh "/ścieżka/do/GTA San Andreas - The Definitive Edition"
```

Instalator kopiuje skrypt do:

```text
Gameface/Binaries/Win64/CLEO/DamageBloodRegenDE[fs].js
```

oraz konfigurację do `DamageBloodRegenDE.ini` obok skryptu. Istniejący skrypt
i INI są zachowywane jako kopie z datą, jeśli różnią się od nowej wersji.

## Konfiguracja

Edytuj `DamageBloodRegenDE.ini`; **F11** przeładowuje konfigurację podczas gry.

- `blood.enabled=0` wyłącza tylko efekt krwi;
- `blood.fade_delay_ms` i `blood.fade_ms` kontrolują wygaszanie plam;
- `regeneration.delay_ms` ustawia czas bez obrażeń przed rozpoczęciem leczenia;
- `regeneration.health_per_second_x10=80` oznacza 8 HP/s;
- `regeneration.enabled=0` wyłącza automatyczne leczenie;
- `regeneration.fallback_health_ceiling=100` jest używane, gdy zestaw definicji
  CLEO nie udostępnia `GET_CHAR_MAX_HEALTH`.

## Zakres i ograniczenia

Mod działa wyłącznie na aktualnej postaci gracza. Nie regeneruje pancerza,
nie zmienia obrażeń broni, nie daje nieśmiertelności i nie ingeruje w zapisy
gry. Efekt krwi jest rysowany przez publiczny HUD CLEO, dlatego nie wymaga
podmiany tekstur ani patchowania adresów pamięci UE4.

Maksymalne zdrowie jest pobierane z `GET_CHAR_MAX_HEALTH`, jeśli ta funkcja
jest dostępna w zainstalowanym runtime. W przeciwnym razie skrypt używa
`fallback_health_ceiling` i podnosi zaobserwowany limit, gdy gra pokaże wartość
wyższą. Dzięki temu mod pozostaje użyteczny również przy starszym pliku
`sa_unreal.d.ts`.

CLEO Redux musi być skonfigurowany dla hosta `sa_unreal`. Jeżeli natywne
`GET_CHAR_HEALTH` albo `SET_CHAR_HEALTH` nie są dostępne, skrypt zapisze
informację w `cleo_redux.log` przy włączonym `debug.enabled=1`, ale nie będzie
udawał działającej regeneracji.

Źródła API: [CLEO Redux JavaScript API](https://re.cleo.li/docs/en/api.html),
[definicje hosta SA:DE](https://re.cleo.li/docs/en/definitions.html).
