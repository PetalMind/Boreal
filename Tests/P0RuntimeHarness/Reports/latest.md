# Boreal P0 Runtime Harness Report

- Generated: `2026-08-24T11:32:33.552548+00:00`
- Wine: `/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine`
- Test executable: `/Users/dominik/Github/Boreal/Tests/P0RuntimeHarness/bin/BorealRuntimeTest.exe`

| Case | Result | Duration | Detail |
| --- | --- | ---: | --- |
| start procesu | **PASS** | 19.455s | launcher PID 49082; process alive=True |
| PID | **PASS** | 19.455s | PID=49082; positive and running=True |
| stdout | **PASS** | 19.456s | BOREAL_STDOUT_OK present=True; log=/private/tmp/boreal-p06-runtime-validation/logs/startup.stdout.log |
| stderr | **PASS** | 19.456s | BOREAL_STDERR_OK present=True; log=/private/tmp/boreal-p06-runtime-validation/logs/startup.stderr.log |
| exit code | **PASS** | 8.314s | expected=37; actual=37 |
| normalne zamknięcie | **PASS** | 9.226s | exit=0; both markers present=True |
| Stop | **PASS** | 12.203s | ready=True; launcher exit=-15; wineserver -w completed=True |
| Force Quit | **PASS** | 10.215s | ready=True; wineserver -k exit=0; launcher exit=0; fallback SIGKILL=False |
| dwa środowiska i izolacja wineserver -k | **PASS** | 20.341s | both ready=True; prefix A stopped=True; prefix B alive=True; wineserver exit=0 |
| Boreal restart recovers active environment | **PASS** | 9.775s | owner exited; forgotten launcher PID=49755; prefix state=active |
| recovered environment force quit without old PID | **PASS** | 9.954s | wineserver -k exit=0; orphan stopped=True; inactive=True |
| same prefix relaunches after recovery cleanup | **PASS** | 13.070s | relaunch successful=True |
| launcher exit does not imply environment inactivity | **PASS** | 9.954s | child ready=True; launcher exit=0; prefix state=active |
| child process keeps environment active | **PASS** | 9.954s | BOREAL_CHILD_OK present=True; prefix state=active |
| environmentSessionState probe does not alter active session | **PASS** | 10.460s | first probe=active; second probe=active |
| environment inactive only after wineserver session ends | **PASS** | 10.635s | wineserver -k exit=0; inactive after kill=True |

Overall: **PASS**
