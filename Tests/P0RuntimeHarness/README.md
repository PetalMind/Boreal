# Boreal P0 Runtime Harness

This directory is an independent, black-box validation suite for Boreal Runtime. It does not import or modify the Boreal application, its UI, or its runtime/environment/store services.

The production session contract and formal P0.6 acceptance criteria are documented in `Documentation/P0.6-Session-Recovery.md`.

## What it validates

`BorealRuntimeTest.exe` is a small Win32 program that creates a visible window, writes `BOREAL_STDOUT_OK` and `BOREAL_STDERR_OK`, accepts `--sleep N` and `--exit-code N`, and exits deterministically. Its internal `--spawn-child N` mode starts a second copy with `--child --sleep N`, then immediately exits the parent.

The harness reports these cases independently:

- process start and launcher PID;
- stdout and stderr capture;
- requested Windows exit code;
- normal timed exit;
- Stop (`SIGTERM` of the Wine launcher, matching Boreal's current process-executor contract);
- Force Quit (`wineserver -k` for the prefix, followed by launcher `SIGKILL` if required);
- two concurrent `WINEPREFIX` environments, proving that `wineserver -k` for prefix A does not stop prefix B.
- recovery of an active prefix after the process-owning harness exits without cleanup;
- prefix-scoped Force Quit without the old launcher handle or PID;
- successful relaunch in the recovered prefix after cleanup;
- child-process semantics: launcher exit does not imply environment inactivity;
- a bounded `wineserver -w` probe that terminates only its observer and leaves the active Wine session untouched.

## Build the Windows executable

Install an x86-64 MinGW-w64 cross-compiler, then run:

```sh
cd Tests/P0RuntimeHarness
./build.sh
```

To use a compiler with a nonstandard name:

```sh
CC_WINDOWS=/absolute/path/to/x86_64-w64-mingw32-gcc ./build.sh
```

The output is `bin/BorealRuntimeTest.exe`. The executable uses the console subsystem so redirected standard handles remain testable, and it explicitly creates a normal visible Win32 window.

## Run against a Boreal Runtime

Point the harness at the exact `wine` executable installed/selected by Boreal. `wineserver` is expected beside it unless supplied explicitly.

```sh
cd Tests/P0RuntimeHarness
./run.sh \
  --wine "$HOME/Library/Application Support/Boreal/Runtimes/<runtime-id>/path/to/wine/bin/wine"
```

Explicit paths and retained test prefixes/logs:

```sh
./run.sh \
  --wine /absolute/runtime/wine/bin/wine \
  --wineserver /absolute/runtime/wine/bin/wineserver \
  --work-dir /tmp/boreal-p0-runtime-run
```

Each test uses a separate prefix, while the isolation case deliberately starts two prefixes concurrently. Temporary prefixes are deleted after the run unless `--work-dir` is supplied.

## Reports and exit status

Every run prints a PASS/FAIL table and writes:

- `Reports/latest.md` — human-readable report;
- `Reports/latest.json` — machine-readable report.

Exit status is `0` only if every case passes, `1` if at least one test fails, and `2` if preflight fails (for example, missing Wine or missing `BorealRuntimeTest.exe`). Use `--json-report` and `--markdown-report` to select other output paths.

The default per-operation timeout is 30 seconds. Override it with `--timeout N`. First-time Wine prefix initialization can require a larger value on slower machines.
