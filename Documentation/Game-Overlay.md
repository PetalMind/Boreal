# Nakładka wydajności gry

## Cel

Nakładka jest osobnym, click-through panelem macOS zarządzanym przez `GameOverlayController`. Pokazuje aktualny stan gry i hosta bez przejmowania fokusu oraz działa nad grą, także w trybie pełnoekranowym. Panel zachowuje dotychczasową strukturę `Minimal`, `Standard` i `Diagnostic`; zmiana obejmuje model danych, źródła pomiarów, częstotliwość próbkowania, wybór gry i zapis sesji.

## Co jest wyświetlane

Zawartość zależy od poziomu szczegółowości i wybranych metryk:

- informacje o sesji: nazwa gry i czas od jej uruchomienia;
- wydajność: FPS, frametime, 1% Low, 0,1% Low, P95 i P99 frametime;
- proces gry: CPU procesu/procesów oraz pamięć rezydentna procesu;
- host: systemowe CPU, GPU, pamięć, swap i pamięć mapowana przez sterownik;
- zdrowie systemu: presja pamięci i stan termiczny;
- temperatury, jeżeli konkretne API sterownika je udostępnia;
- wykres FPS oraz wykres systemowego CPU/GPU w trybie Diagnostic;
- informacje o konfiguracji: Game API, translator, Host API, runtime, ekran, procesor i źródło FPS.

Metryka jest pokazywana tylko wtedy, gdy jest zaznaczona w ustawieniach i jej capability nie jest `unsupported`. Brak bieżącej próbki jest prezentowany jako `—`; nie jest zamieniany na zero ani na wiarygodnie wyglądającą wartość zastępczą.

## Poziomy widoku

### Minimal

Pokazuje sesję, podstawowe metryki wydajności, ostrzeżenie o presji pamięci oraz skrót `⌘⌥O`. Zestaw metryk jest filtrowany ustawieniami.

### Standard

Dodaje jawne sekcje `GAME` i `SYSTEM`. Dzięki temu `GAME CPU`/`GAME MEMORY` nie są mylone z `SYSTEM CPU`/`SYSTEM MEMORY`. Pokazuje także swap, driver-mapped memory, presję pamięci oraz podstawowe informacje o API i translatorze.

### Diagnostic

Jest kompaktowym panelem o rozmiarze bazowym 420 × 700 punktów i przewijalnej zawartości. Zawiera podział na proces gry, host, pamięć i termikę, wykresy, źródło FPS oraz dynamiczne szczegóły grafiki:

```text
Game API    DirectX 9 / DirectX 10 / DirectX 11 / DirectX 12 / Automatic
Translator  D3DMetal / DXMT / DXVK / VKD3D-Proton / Wine (WineD3D)
Host API    Metal / Vulkan / OpenGL
Runtime     nazwa runtime'u Boreal
```

CPU Temperature nie pojawia się, gdy system nie ma rzeczywistego providera tej wartości. Aktualna implementacja deklaruje ten brak jako `unsupported` zamiast wyświetlać pusty albo zmyślony odczyt.

## Architektura i przepływ danych

```text
BorealStore
  ├─ WindowsApplication + LaunchPlan + WindowsProcessSession
  ├─ URL logu stderr
  ├─ PID-y procesu gry (odświeżane niezależnie od UI)
  └─ OverlayGraphicsDescriptor
          │
          ▼
ContentView.runningOverlayGames
          │
          ▼
GameOverlayController / GamePerformanceMonitor
  ├─ wybór gry z frontmost window, fallback: najnowsza aktywna sesja
  ├─ sampling loop: 20 Hz
  ├─ UI refresh loop: ustawiane 2–4 Hz
  └─ PerformanceSessionRecorder, jeśli nagrywanie jest włączone
          │
          ▼
GameMetricsSampler
  ├─ WineFPSMetricsProvider
  ├─ MetalHUDMetricsProvider
  ├─ ProcessMetricsProvider
  └─ HostMetricsProvider
          │
          ▼
GamePerformanceSnapshot
          ├─ wartości
          ├─ capabilities: available / unavailable / unsupported / warmingUp
          └─ źródło FPS i informacja, czy frametime jest zmierzony
```

Rozdzielenie pętli jest istotne: odczyt metryk nie jest już wykonywany tylko przy odświeżeniu widoku. Sampler pracuje z częstotliwością 20 Hz, natomiast providery kosztowniejszych danych mają własny cache: CPU/GPU hosta i proces są odczytywane maksymalnie około 2 razy na sekundę, a pamięć/termika są odświeżane w tym samym ograniczonym rytmie. UI może odświeżać się co 0,25, 0,5 albo 1 sekundę.

## Źródła danych

| Metryka | Źródło | Znaczenie i ograniczenia |
|---|---|---|
| Nazwa gry | `WindowsApplication.name` albo sesja natywna zgłoszona przez `expectNativeGame` | Nazwa z biblioteki Boreal lub nazwa oczekiwanej aplikacji. |
| Czas sesji | `lastOpened`/`launchedAt` | Lokalny czas od uruchomienia sesji. |
| FPS Windows/Wine | Aktywny `launch-*.stderr.log`, kanał `WINEDEBUG=+fps` | Odczytywany jest ograniczony ogon pliku, a wpis musi być świeży. To fallback logowy, nie pomiar z silnika. |
| FPS D3DMetal | `/usr/bin/log stream` z predykatem `com.apple.metal.hud` | Metal HUD jest preferowany przed kanałem Wine. Dane zawierają interwały prezentacji. |
| FPS natywnego macOS | Brak wspólnego źródła w tej ścieżce | Capability pozostaje `unsupported`, więc UI pokazuje `—`. |
| Frametime | Interwały z Metal HUD albo `1000 / FPS` dla Wine | Metal HUD daje wartość zmierzoną (`measured`). Wine ma wartość estymowaną (`estimated`). Obie ścieżki są oznaczone w snapshotcie. |
| Średni FPS | Suma zebranych interwałów klatek | Nie jest średnią z samych odświeżeń UI. |
| 1% Low | Najwolniejsze 1% z historii interwałów | Wartość pojawia się po rozgrzaniu historii; dla Wine jakość zależy od częstotliwości wpisów `+fps`. |
| 0,1% Low | Najwolniejsze 0,1% z historii interwałów | Ta sama zasada, z większą liczbą wymaganych próbek. |
| P95/P99 frametime | Kwantyle historii interwałów | Oparte na rzeczywistych interwałach Metal HUD albo estymowanych interwałach Wine. |
| GAME CPU | `proc_pidinfo(..., PROC_PIDTASKINFO, ...)` dla PID-ów gry | Suma czasu user/system rzeczywistych procesów gry; może obejmować kilka procesów. Nie jest to CPU launchera Wine ani CPU całego hosta. |
| GAME MEMORY | `proc_taskinfo.pti_resident_size` dla PID-ów gry | Pamięć rezydentna procesu/procesów gry. PID-y są wykrywane po nazwie/ścieżce executable. |
| SYSTEM CPU | `host_processor_info(..., PROCESSOR_CPU_LOAD_INFO, ...)` | Użycie całego Maca z różnicy kolejnych ticków. |
| SYSTEM GPU | `IOAccelerator` → `PerformanceStatistics` | Pierwsza dostępna wartość z kluczy wykorzystania GPU; ograniczana do 0–100%. To odczyt systemowy, nie wykorzystanie wyłącznie gry. |
| SYSTEM MEMORY | `host_statistics64(..., HOST_VM_INFO64, ...)` | Active + inactive + wired + compressor, z odjęciem reclaimable/external i ograniczeniem do pamięci fizycznej. |
| System total memory | `ProcessInfo.processInfo.physicalMemory` | Całkowita fizyczna pamięć hosta. |
| Swap | `sysctlbyname("vm.swapusage")` | Systemowy użyty swap. |
| Driver-mapped memory | `IOAccelerator` → `Alloc system memory` | Suma alokacji sterownika mapowanych w RAM. To nie jest dedykowany VRAM ani pamięć samej gry; nie jest dodawana ponownie do SYSTEM MEMORY. |
| GPU temperature | `IOAccelerator` / `PerformanceStatistics` | Tylko jeśli sterownik udostępnia rozpoznawalny klucz i wartość. |
| CPU temperature | Brak obecnego providera | Capability `unsupported`; wiersz jest pomijany. |
| Memory pressure | `kern.memorystatus_vm_pressure_level` | Mapowane na `Normal`, `Warning`, `Critical`. |
| Thermal state | `ProcessInfo.processInfo.thermalState` | Ogólny stan termiczny systemu: Normal, Elevated, Serious, Critical lub Unknown. |
| Ekran | Największe widoczne okno procesu + `NSScreen` | Rozdzielczość jest liczona jako frame × backing scale factor. |
| Game API | `LaunchPlan.directXAPI` | Dynamiczne DirectX/Automatic z planu uruchomienia, nie literalne `Metal`. |
| Translator | `LaunchPlan.graphicsStack.backend` | Wybrany backend grafiki, z fallbackiem do `graphicsBackend`/rekordu aplikacji. |
| Host API | `LaunchPlan.graphicsStack.hostAPI` | Metal, Vulkan albo OpenGL, jeżeli plan ma stack. |
| Runtime | `WindowsEnvironment.runtime` | Human-readable nazwa runtime'u użytego przez środowisko. |
| Processor | `machdep.cpu.brand_string`, potem `hw.model` | Nazwa hosta, nie procesora procesu Windows. |

## Priorytet źródeł FPS

Kolejność jest następująca:

1. telemetryka renderer-native, jeśli w przyszłości provider ją udostępni;
2. Metal HUD dla sesji D3DMetal;
3. kanał `WINEDEBUG=+fps`/stderr jako fallback dla Wine;
4. brak danych z jawnym stanem capability, bez udawania pomiaru.

`WINEDEBUG=+fps` pozostaje mechanizmem fallbackowym. `WindowsProcessRunner` włącza ten kanał w logu sesji, a dla runtime'ów z capability Metal HUD dodaje także `MTL_HUD_ENABLED`, `MTL_HUD_LOG_ENABLED`, `MTL_HUD_ELEMENTS=fps,frameinterval` oraz wyłączoną widoczność HUD. Strumień Metal HUD jest uruchamiany raz na sesję, zamykany w `reset()` i nie pozostaje jako osierocony proces po zakończeniu gry.

## Dostępność danych

Każda rodzina metryk ma stan `MetricAvailability`:

- `available` — wartość jest dostępna;
- `warmingUp` — źródło istnieje, ale nie zebrano jeszcze wystarczającej historii albo poprzedniej próbki;
- `unavailable` — provider istnieje, ale bieżący system/sterownik nie oddał danych;
- `unsupported` — dana ścieżka nie ma obsługi, np. CPU Temperature lub FPS natywnej aplikacji w tym modelu.

To rozróżnia brak chwilowej próbki od braku capability. Warstwa UI nadal używa `—` jako czytelnego przedstawienia wartości, ale diagnostyka ma w snapshotcie informację, dlaczego wartość nie jest dostępna.

## Wybór aktywnej gry

Przy wielu uruchomionych grach kontroler najpierw szuka gry, której znany PID jest procesem frontmost application. Dodatkowo ekran panelu jest ustalany na podstawie największego widocznego okna tej aplikacji. Jeżeli procesy nie zostały jeszcze wykryte podczas startu, stosowany jest fallback do najnowszej aktywnej sesji. PID-y są aktualizowane przez `BorealStore` co około 500 ms, niezależnie od odświeżania panelu.

## Nagrywanie sesji

Ustawienie `Record while a game is running` uruchamia `PerformanceSessionRecorder`. Sesja jest zapisywana po zakończeniu gry lub wyłączeniu nagrywania w:

```text
~/Library/Application Support/Boreal/Performance Sessions/
```

Dokument JSON zawiera:

- identyfikator gry i sesji;
- nazwę oraz dynamiczny opis grafiki;
- czas rozpoczęcia i zakończenia;
- próbki snapshotów;
- podsumowanie: duration, average FPS, 1% Low, 0,1% Low, P95/P99 frametime, peak game memory, czas `Serious`/`Critical`, liczba klatek i próbek.

W ustawieniach można wyeksportować ostatnią sesję jako JSON albo CSV. CSV zawiera wiersz nagłówkowy i płaskie próbki z timestampem, FPS, frametime, CPU/RAM gry, CPU/GPU/RAM hosta, swapem i termiką. Model `PerformanceSessionComparison` stanowi podstawę do porównywania dwóch zapisanych sesji.

## Ustawienia i skróty

| Klucz | Wartość domyślna | Działanie |
|---|---|---|
| `gameOverlayEnabled` | `true` | Automatyczne pokazywanie panelu. |
| `gameOverlayDetailLevel` | `standard` | `minimal`, `standard`, `diagnostic`. |
| `gameOverlayPosition` | `topRight` | Jeden z czterech narożników. |
| `gameOverlayRefreshInterval` | `0.25` | Odświeżanie UI: 0,25 / 0,5 / 1 sekundy. Nie zmienia częstotliwości samplera. |
| `gameOverlayMetrics` | zestaw podstawowy | Zserializowany zestaw `OverlayMetric`. |
| `gameOverlayRecordingEnabled` | `false` | Trwałe nagrywanie sesji. |

Polecenia menu:

- `⌘⌥O` — pokaż/ukryj nakładkę;
- `⌘⌥I` — przełącz Minimal → Standard → Diagnostic → Minimal;
- `⌘⌥1`, `⌘⌥2`, `⌘⌥3` — wybierz poziom bezpośrednio.

## Pliki implementacji

| Zakres | Plik |
|---|---|
| Modele capability, źródła, metryki i podsumowania | [`GameMetricsModels.swift`](../Boreal/GameMetricsModels.swift) |
| Providery i agregacja pomiarów | [`GameMetricsSampler.swift`](../Boreal/GameMetricsSampler.swift) |
| Panel, lifecycle, wybór gry i rendering | [`GameOverlay.swift`](../Boreal/GameOverlay.swift) |
| PID-y procesu gry oraz dynamiczny opis launch planu | [`BorealStore.swift`](../Boreal/BorealStore.swift), [`WindowsProcessRunner.swift`](../Boreal/WindowsProcessRunner.swift) |
| Trwałe sesje i eksport | [`PerformanceSessionRecorder.swift`](../Boreal/PerformanceSessionRecorder.swift) |
| Ustawienia | [`GameOverlaySettingsView.swift`](../Boreal/GameOverlaySettingsView.swift) |
| Budowanie listy aktywnych gier | [`ContentView.swift`](../Boreal/ContentView.swift) |

## Granice pomiaru

Nakładka nie zastępuje narzędzi rendererów ani profilera silnika gry. Systemowy GPU, systemowa pamięć i systemowy thermal state opisują hosta. Dla Wine frametime oraz statystyki percentile są oparte na estymowanych interwałach wynikających z `+fps`, dopóki runtime nie udostępni prawdziwych interwałów. Jeżeli provider nie ma capability albo sterownik nie zwraca wartości, prawidłowym wynikiem jest jawna niedostępność.
