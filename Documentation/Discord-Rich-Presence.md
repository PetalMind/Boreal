# Discord Rich Presence

Boreal publikuje tytuł uruchomionej gry, opis „Uruchomiono przez Boreal” i czas sesji w desktopowym Discordzie. Wykorzystuje lokalne RPC przez gniazdo IPC macOS, bez logowania do konta Discord i bez tokenu użytkownika.

## Konfiguracja

1. Utwórz aplikację Boreal w [Discord Developer Portal](https://discord.com/developers/applications).
2. Skopiuj jej **Application ID** z sekcji General Information.
3. W Boreal otwórz **Ustawienia → Integracje → Discord Rich Presence**, wklej Application ID i włącz **Pokazuj uruchomioną grę w Discordzie**.
4. Uruchom desktopową aplikację Discord. Ustawienia prywatności aktywności Discorda muszą pozwalać na jej wyświetlanie.

Integracja jest domyślnie wyłączona. Application ID jest publicznym identyfikatorem aplikacji; nie należy wpisywać tokenu bota ani Client Secret.

## Zachowanie

- Status jest publikowany po wykryciu procesu gry, zarówno dla Wine/GPTK, jak i natywnych gier macOS uruchamianych z Boreal.
- Instalatory oraz host Windows Steam są pomijane.
- Po zakończeniu gry aktywność jest usuwana. Przy kilku grach publikowana jest ostatnio uruchomiona gra z wykrytym procesem.
- Wyłączenie integracji oraz zamknięcie Boreal usuwa aktywność i zamyka lokalne połączenie.
- Po zamknięciu lub restarcie Discorda Boreal ponawia połączenie co 15 sekund. Nie wpływa to na uruchomioną grę.
- Wyłączenie overlayu nie wyłącza integracji Discorda.
- Okładka jest wysyłana, jeśli metadane gry zawierają publiczny adres HTTPS. Lokalne, własne okładki nie są przesyłane. Wyświetlenie grafiki zależy też od obsługi adresu przez Discorda.
- Przycisk Boreal prowadzi do repozytorium projektu. Przycisk strony gry jest dodawany dla Steam, którego identyfikator pozwala utworzyć publiczny adres produktu.
- Pole stanu w ustawieniach pokazuje potwierdzenie przyjęcia aktywności przez Discorda albo brak połączenia/błąd konfiguracji.

Transport i format aktywności opisuje [dokumentacja Discord RPC](https://docs.discord.com/developers/topics/rpc). Ten moduł obejmuje Rich Presence. Znajomi, czat, głos i zaproszenia z Social SDK wymagają osobnej integracji.
