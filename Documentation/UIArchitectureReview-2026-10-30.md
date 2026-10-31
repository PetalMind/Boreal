# Przegląd widoków Boreal — 2026-10-30

Zakres: aplikacja macOS Boreal; przegląd źródeł wszystkich typów `View` i `NSViewRepresentable`, ich kompozycji, stanu, akcji, układu i wspólnych komponentów. Zastosowano `swiftui-patterns`, `axiom-swiftui` (architektura i układ) oraz `macos-app-design`. Zachowano istniejące funkcje i minimalny system macOS 27.

## Decyzje i zmiany

| Obszar | Wynik przeglądu i wykonana zmiana |
| --- | --- |
| Okno główne i nawigacja | Oddzielono komponenty paska bocznego i stan przejścia do szczegółów od routingu. Uproszczono ikony oraz zaznaczenie; usunięto animowaną kolorową belkę zaznaczenia. |
| Biblioteka i ulubione | Reguły filtrowania, sortowania i projekcji przeniesiono do `LibraryPresentation.swift`, pamięć projekcji do `LibraryProjectionCache.swift`. Wyróżniona gra jest przyciskiem dostępnym z klawiatury zamiast gestem kliknięcia. |
| Odkrywanie gier i zapisane gry | Oddzielono widoki od katalogu i usług. Obliczanie projekcji znajduje się w `DiscoveryProjection.swift`, pobieranie i cache obrazów w `DiscoveryImagePipeline.swift`. Zachowano stany ładowania, błędu i pustych wyników. |
| Szczegóły gry sklepowej | Formularz instalacji, galeria, modele wyboru mediów i style akcji wydzielone z głównego widoku. Drobne etykiety podniesiono do minimum 11 pt. Zachowano wszystkie zakładki i dane. |
| Galeria i odtwarzacz | Osobny plik `StoreMediaViews.swift`; zachowane sterowanie mediami, klawiatura i przyciemnione tło potrzebne do oglądania obrazów. |
| Konta | Karty korzystają ze wspólnej powierzchni o kolorach semantycznych i reagującej na zwiększony kontrast. Zachowano logowanie, rozłączenie i stan synchronizacji każdego dostawcy. |
| Pobieranie | Karty operacji i paneli korzystają ze wspólnej powierzchni. Zachowano bieżące pomiary, wykresy, kolejkę, pauzę i wznowienie. |
| Ustawienia — kontener | Natywna przewijalna lista kategorii w `NavigationSplitView`, nawigacja klawiaturą, tytuł aktualnej kategorii i mniejsze wymagane okno (760 × 560). Bez dodawania kategorii i opcji. |
| Ustawienia — sekcje | Ogólne, pobieranie, runtime, tryb konsolowy i zaawansowane mają osobne pliki. `SettingsCategory.swift` zawiera opis nawigacji; `SettingsComponents.swift` współdzielony układ. |
| Ustawienia — karty i wiersze | Układ poziomy przechodzi w pionowy, gdy treść się nie mieści. Kontrolki z ukrytymi etykietami otrzymują etykietę dostępności wiersza. Zastosowano semantyczną powierzchnię zamiast warstw szkła i Popebiałych obramowań. |
| Miejsce na dysku | Korzysta z adaptacyjnych kart ustawień. Zachowano skanowanie, błędy, stan pusty, potwierdzenia i zasady operacji na danych. |
| Runtime i komponenty graficzne | Osobny widok ustawień; istniejące importowanie, edycja, usuwanie i statusy pozostają pod kontrolą magazynu. Lista komponentów nadal pokazuje wyłącznie przekazane dane. |
| Kontrolery | W węższym oknie wybór kategorii zmienia się w Picker; podgląd przechodzi pod kontrolki. Podglądy 2D i 3D respektują ograniczenie ruchu. Konstrukcja sceny 3D znajduje się w osobnym pliku; wyłączono nieprzerwane renderowanie bez zmian wejścia. |
| Tryb konsolowy | Przewijanie do fokusa i powiększanie karty respektują ograniczenie ruchu. Zachowano istniejącą prezentację do obsługi kontrolerem. |
| Nakładka i jej ustawienia | Najdrobniejsze etykiety wykresów i skrótów mają minimum 11 pt. Ustawienia korzystają z adaptacyjnych kart. |
| Instalator pliku Windows | Podąża za motywem systemowym; usunięto wymuszony ciemny gradient, dekoracje mają kolory semantyczne. Przepływ instalacji i blokada zamknięcia podczas operacji zachowane. |
| Zapisy w chmurze | Wspólna powierzchnia karty; zachowano stany dostawcy, błędy, konfigurację i potwierdzenie zastąpienia zapisów. |
| Mody i podgląd instalacji moda | Panele listy, inspektora i profili korzystają z semantycznych powierzchni. Reguły wdrażania, zależności i potwierdzenia niezmienione. |
| Automatyczne wykrywanie instalacji | Baner korzysta ze wspólnej powierzchni; istniejące stany skanowania, kandydaci i zatwierdzanie importu zachowane. |
| Wspólne grafiki i animacje | Pobieranie oraz lokalny cache obrazów wydzielono do `ArtworkImagePipeline.swift`, parametry ruchu do `BorealMotion.swift`. Wskaźnik ładowania jest natywnym `ProgressView`; przycisk ulubionych ma obszar 44 × 44 pt. |
| Szczegóły aplikacji lokalnej, środowiska | Zachowano istniejące układy, akcje i stany. Bez zmian w regułach uruchamiania gier oraz obsługi środowisk. |
| Inspektor środowiska, zapisy lokalne, zaawansowana konfiguracja | Zachowano istniejące karty, ładowanie danych, komunikaty błędów oraz potwierdzenia operacji. Bez zmian w usługach danych. |
| Konfigurator kompatybilności i poprawka Wiedźmina 3 | Zachowano istniejący adaptacyjny układ i rzeczywiste reguły dostępności opcji. Bez zmian w konfiguracji runtime i instalowaniu poprawek. |
| Kreator Wine MSync | Zachowano skupiony formularz, wybór katalogu oraz systemowe akcje anulowania i zatwierdzenia. |
| Stan generowania klatek | Zachowano prezentację opartą na stanie i dowodach runtime. Brak nowych wskaźników sugerujących pomiar bez danych. |
| Discord | Widok ustawień korzysta z adaptacyjnych kart. Regułę publicznego URL gry przeniesiono z ekranu do rozszerzenia modelu. |

## Granice weryfikacji

Przegląd źródeł i kompilacja nie potwierdzają działania wszystkich ekranów na żywych kontach, instalacjach i kontrolerach. Nie wykonywano operacji logowania, instalacji, modyfikowania zapisów, przenoszenia danych ani uruchamiania gier. Nie dodano testów. Przegląd nie stanowi deklaracji usunięcia całego długu architektonicznego aplikacji.

## Wyniki weryfikacji

- Build aplikacji Debug arm64 i sprawdzenie typów: **PASS**, `xcodebuild` przez `/Users/dominik/.codex/bin/codex-build`, macOS 27 SDK, bez podpisywania. Kompilator nadal zgłasza ostrzeżenia istniejących usług, m.in. dotyczące izolacji i przyszłego trybu Swift 6; pliki tych usług nie były zmieniane.
- Swift Format: **PASS** dla 22 nowych plików Swift w trybie `--strict`, wcięcie 4 spacje i limit 160 znaków. Konfiguracja była tymczasowa, bez narzucania nowego formatowania całemu repozytorium.
- Lint 18 edytowanych istniejących plików: kod wyjścia 0; 1567 ostrzeżeń stylu, wobec 1823 w tych samych plikach z HEAD sprzed zmian. To nie jest deklaracja czystego lint całego projektu.
- `git diff --check`: **PASS**. Porównanie inwentarza przed/po: nie usunięto żadnego typu UI.
- Zbudowano tymczasowy podgląd rzeczywistych `SettingsCard`, `SettingsRow` i `BorealSurface` z natywnymi kontrolkami przez `NSHostingView`. Wygenerowano 16 wariantów: 360/768/1024/1440 pt, jasny/ciemny motyw i standardowa/powiększona do 26 pt treść. Sprawdzono zmianę układu oraz zawijanie treści w najwęższym wariancie. Przykładowa karta przy 360 pt rośnie z 259 do 341 pt wysokości, bez wymuszania większej szerokości. To podgląd komponentów z danymi kontrolnymi, a nie uruchomienie wszystkich ekranów aplikacji.
- Pełna obsługa VoiceOver, rzeczywiste ustawienie największego tekstu i zwiększonego kontrastu w systemie, a także przepływy ze sprzętem i kontami: **niezweryfikowane w runtime**.
- Wersja aplikacji: **1.0.19**, build **20**. Źródło konfiguracji wersji: `Boreal.xcodeproj/project.pbxproj` (konfiguracje Debug i Release); wpis w `CHANGELOG.md`.

## Inwentarz typów UI

Poniższy spis obejmuje również prywatne widoki pomocnicze i widoki osadzone w plikach usług. Każda grupa została uwzględniona w przeglądzie kompozycji oraz wyszukiwaniu problemów stanu, stałych wymiarów, kolorów, małej typografii, gestów i animacji. Wspólne poprawki dotyczą również ekranów, których pliki nie wymagały bezpośredniej edycji.

| Plik | Typy UI |
| --- | --- |
| `Boreal/AccountsView.swift` | `AccountsView`, `AccountSyncToggle` |
| `Boreal/AdvancedSettingsView.swift` | `AdvancedSettingsView` |
| `Boreal/AppDetailView.swift` | `AppDetailView` |
| `Boreal/BorealSurface.swift` | `BorealGlassBackdrop` |
| `Boreal/CloudSaveViews.swift` | `CloudSaveCard` |
| `Boreal/Components.swift` | `FavoriteButton`, `ControllerConsoleModeDialog`, `AppIconView`, `GameArtworkView`, `BorealArtworkLoadingIndicator`, `StorePlatformBadge`, `NativeMacOSBadge`, `StoreRatingBadge`, `CompatibilityLabel`, `MacCompatibilityBadge`, `ApplicationStatusLabel`, `BorealErrorSheet`, `DetailRow`, `BorealEmptyState` |
| `Boreal/ConsoleModeSettingsView.swift` | `ConsoleModeSettingsView` |
| `Boreal/ConsoleModeView.swift` | `ConsoleModeView`, `ConsoleControlHint`, `ConsoleGameDetailView`, `ConsoleHomeHero`, `ConsoleGameCard` |
| `Boreal/ContentView.swift` | `ContentView` |
| `Boreal/Controller2DView.swift` | `Controller2DView` |
| `Boreal/Controller3DView.swift` | `Controller3DView` |
| `Boreal/ControllerSettingsView.swift` | `ControllerSettingsView`, `ControllerPreview` |
| `Boreal/DiscordSettingsView.swift` | `DiscordSettingsView` |
| `Boreal/DiscoveryViews.swift` | `DiscoveryView`, `DiscoveryGameTile`, `SavedDiscoveryGamesView`, `DiscoveryArtwork`, `DiscoveryRatingLabel`, `DiscoveryGameDetailView` |
| `Boreal/DownloadSettingsView.swift` | `DownloadSettingsView` |
| `Boreal/DownloadsView.swift` | `DownloadsView`, `DownloadOperationCard`, `DownloadMetric`, `DownloadQueueRow`, `DownloadInspectorCard`, `InspectorRow`, `D3D11SelfTestCard`, `InspectorAction` |
| `Boreal/EnvironmentsView.swift` | `EnvironmentsView` |
| `Boreal/FrameGeneration/FrameGenerationStatusView.swift` | `FrameGenerationStatusView` |
| `Boreal/GameActionStyles.swift` | `GamePrimaryActionButton` |
| `Boreal/GameDiscoveryView.swift` | `GameDiscoveryBanner`, `GameDiscoverySheet`, `GameDiscoveryCandidateRow`, `GameDiscoverySettingsCard` |
| `Boreal/GameOverlay.swift` | `GameOverlayView` |
| `Boreal/GameOverlaySettingsView.swift` | `GameOverlaySettingsView` |
| `Boreal/GeneralSettingsView.swift` | `GeneralSettingsView` |
| `Boreal/InstallationSheet.swift` | `InstallationSheet` |
| `Boreal/LibraryView.swift` | `LibraryToolbarControls`, `LibraryView`, `LibraryCardOutline`, `CustomCoverEditorView`, `LibraryGridHoverContainer` |
| `Boreal/ModsView.swift` | `ModsView`, `PluginRow`, `ModInstallPreviewSheet` |
| `Boreal/ReliabilityViews.swift` | `EnvironmentInspectorView`, `GameSavesView`, `GameAdvancedConfigurationView`, `InspectorCard`, `InspectorValueGrid` |
| `Boreal/RuntimeGraphicsComponentsView.swift` | `RuntimeGraphicsComponentsView` |
| `Boreal/RuntimeSettingsView.swift` | `RuntimeSettingsView`, `RuntimeEditorSheet` |
| `Boreal/SettingsComponents.swift` | `SettingsCard`, `SettingsRow` |
| `Boreal/SettingsView.swift` | `BorealSettingsView` |
| `Boreal/SidebarComponents.swift` | `BorealSidebarSectionHeader`, `BorealSidebarRow`, `BorealStoreSidebarRow`, `BorealStoreMark` |
| `Boreal/StorageSettingsView.swift` | `StorageSettingsView`, `StorageUsageBar`, `StorageItemRow`, `StorageRiskRow` |
| `Boreal/StoreGameDetailView.swift` | `StoreGameDetailView` |
| `Boreal/StoreGameInstallationSheet.swift` | `StoreGameInstallationSheet` |
| `Boreal/StoreMediaViews.swift` | `GalleryScreenshotView`, `StoreMediaThumbnail`, `StoreMediaViewer` |
| `Boreal/WineCompatibilityConfigurator.swift` | `WineCompatibilityConfigurator`, `CompatibilityHeader`, `CompatibilityPresetSelector`, `CompatibilitySettingsSection`, `CompatibilityPickerRow`, `CompatibilityToggleRow`, `CompatibilityUpscalingRow`, `InspectorValueRow`, `CompatibilityTextFieldRow`, `CompatibilityCallout`, `LegacyWrapperDecisionCard`, `CompatibilityLaunchPlanCard`, `CompatibilitySettingsFooter`, `ComponentsAndPatchesView` |
| `Boreal/WineMSyncBuildSheet.swift` | `WineMSyncBuildSheet` |
| `Boreal/Witcher3GraphicsFix.swift` | `Witcher3GraphicsFixSection` |

Łącznie: 106 typów UI.
