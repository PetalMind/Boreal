# Boreal P0 Runtime Harness Report

- Generated: `2026-08-24T11:16:30.736703+00:00`
- Wine: `/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine`
- Test executable: `/Users/dominik/Github/Boreal/Tests/P0RuntimeHarness/bin/BorealRuntimeTest.exe`

| Case | Result | Duration | Detail |
| --- | --- | ---: | --- |
| start procesu | **PASS** | 8.851s | launcher PID 46159; process alive=True |
| PID | **PASS** | 8.851s | PID=46159; positive and running=True |
| stdout | **PASS** | 8.853s | BOREAL_STDOUT_OK present=True; log=/private/tmp/boreal-p0-runtime-validation-3/logs/startup.stdout.log |
| stderr | **PASS** | 8.853s | BOREAL_STDERR_OK present=True; log=/private/tmp/boreal-p0-runtime-validation-3/logs/startup.stderr.log |
| exit code | **PASS** | 6.872s | expected=37; actual=37 |
| normalne zamknięcie | **PASS** | 7.130s | exit=0; both markers present=True |
| Stop | **PASS** | 10.240s | ready=True; launcher exit=-15; wineserver -w completed=True |
| Force Quit | **PASS** | 7.425s | ready=True; wineserver -k exit=0; launcher exit=0; fallback SIGKILL=False |
| dwa środowiska i izolacja wineserver -k | **PASS** | 9.729s | both ready=True; prefix A stopped=True; prefix B alive=True; wineserver exit=0 |

Overall: **PASS**
