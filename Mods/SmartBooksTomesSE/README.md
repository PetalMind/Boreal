# Smart Books & Tomes SE

Łączy status zwykłych książek, książek umiejętności i tomów zaklęć w jednym
rejestrze MCM. Zachowuje oryginalne nazwy przedmiotów.

## Statusy i filtry

- Książki: przeczytana albo nieprzeczytana.
- Książki umiejętności: osobny status z ikoną gwiazdy, jeśli są nieprzeczytane.
- Tomy zaklęć: nowe zaklęcie albo zaklęcie już znane.
- Filtry: wszystkie, nieprzeczytane, przeczytane, książki umiejętności, tomy,
  nowe zaklęcia i znane zaklęcia.

Lista MCM pokazuje książki znajdujące się w ekwipunku gracza i odświeża ją przy
otwarciu strony. Status nie zmienia nazw książek. Wersja 0.1.0 nie dodaje ikon
bezpośrednio do wierszy ekwipunku ani do menu handlu; takie wskaźniki wymagają
osobnej integracji Scaleform ze SkyUI.

## Wymagania i instalacja

- Skyrim Special Edition lub Anniversary Edition;
- SKSE64 zgodny z wersją gry;
- Papyrus Extender;
- SkyUI z MCM.

Zaimportuj SmartBooksTomesSE.zip w Boreal, włącz SmartBooksTomesSE.esp i
uruchom grę przez SKSE.

build.sh kompiluje skrypt Papyrus kompilatorem Caprica i buduje paczkę
instalacyjną. Można ustawić CAPRICA_EXE przed uruchomieniem skryptu.

## Aktualizacja menu MCM

Podmień poprzednią paczkę tego moda w menedżerze, zachowując jedną aktywną
kopię, i włącz jego ESP. Archiwum zawiera plik SEQ uruchamiający quest
konfiguracji oraz alias gracza odnawiający rejestrację MCM po wczytaniu zapisu.
