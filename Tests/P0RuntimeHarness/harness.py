#!/usr/bin/env python3
"""Black-box P0 validation for a Boreal Wine runtime."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import IO, Callable, Sequence


STDOUT_MARKER = "BOREAL_STDOUT_OK"
STDERR_MARKER = "BOREAL_STDERR_OK"
CHILD_MARKER = "BOREAL_CHILD_OK"
DEFAULT_TIMEOUT = 30.0


@dataclass
class Result:
    case: str
    status: str
    detail: str
    duration_seconds: float


@dataclass
class RunningProcess:
    process: subprocess.Popen[bytes]
    stdout_path: Path
    stderr_path: Path
    stdout_file: IO[bytes]
    stderr_file: IO[bytes]
    prefix: Path

    def close_files(self) -> None:
        self.stdout_file.close()
        self.stderr_file.close()


class Harness:
    def __init__(self, wine: Path, wineserver: Path, executable: Path, work_dir: Path, timeout: float):
        self.wine = wine
        self.wineserver = wineserver
        self.executable = executable
        self.work_dir = work_dir
        self.timeout = timeout
        self.results: list[Result] = []

    def environment(self, prefix: Path) -> dict[str, str]:
        values = os.environ.copy()
        values["WINEPREFIX"] = str(prefix)
        values["WINEARCH"] = "win64"
        values.setdefault("WINEDEBUG", "warn+all,err+all")
        values["PATH"] = f"{self.wine.parent}:{values.get('PATH', '/usr/bin:/bin')}"
        return values

    def launch(self, name: str, prefix: Path, arguments: Sequence[str]) -> RunningProcess:
        prefix.mkdir(parents=True, exist_ok=True)
        log_dir = self.work_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        stdout_path = log_dir / f"{name}.stdout.log"
        stderr_path = log_dir / f"{name}.stderr.log"
        stdout_file = stdout_path.open("wb")
        stderr_file = stderr_path.open("wb")
        try:
            process = subprocess.Popen(
                [str(self.wine), str(self.executable), *arguments],
                cwd=self.executable.parent,
                env=self.environment(prefix),
                stdout=stdout_file,
                stderr=stderr_file,
                start_new_session=True,
            )
        except BaseException:
            stdout_file.close()
            stderr_file.close()
            raise
        return RunningProcess(process, stdout_path, stderr_path, stdout_file, stderr_file, prefix)

    def wineserver_command(self, prefix: Path, *arguments: str, timeout: float | None = None) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [str(self.wineserver), *arguments],
            env=self.environment(prefix),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout or self.timeout,
            check=False,
        )

    @staticmethod
    def contains(path: Path, marker: str) -> bool:
        try:
            return marker in path.read_text(encoding="utf-8", errors="replace")
        except FileNotFoundError:
            return False

    def wait_for_markers(self, running: RunningProcess) -> bool:
        return self.wait_for_file_markers(running.stdout_path, running.stderr_path, running.process)

    def wait_for_file_markers(
        self,
        stdout_path: Path,
        stderr_path: Path,
        process: subprocess.Popen[bytes] | None = None,
        stdout_marker: str = STDOUT_MARKER,
    ) -> bool:
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            if self.contains(stdout_path, stdout_marker) and self.contains(stderr_path, STDERR_MARKER):
                return True
            if process is not None and process.poll() is not None:
                return False
            time.sleep(0.05)
        return False

    def probe_environment_session(self, prefix: Path, observation_window: float = 0.5) -> str:
        observer = subprocess.Popen(
            [str(self.wineserver), "-w"],
            env=self.environment(prefix),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            result = observer.wait(timeout=observation_window)
            return "inactive" if result == 0 else "unknown"
        except subprocess.TimeoutExpired:
            observer.terminate()
            try:
                observer.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                os.killpg(observer.pid, signal.SIGKILL)
                observer.wait(timeout=5.0)
            return "active"

    @staticmethod
    def process_exists(pid: int) -> bool:
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def wait_for_pid_exit(self, pid: int, timeout: float = 10.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not self.process_exists(pid):
                return True
            time.sleep(0.05)
        return not self.process_exists(pid)

    def record(self, case: str, started: float, passed: bool, detail: str) -> None:
        self.results.append(Result(case, "PASS" if passed else "FAIL", detail, round(time.monotonic() - started, 3)))

    def cleanup(self, running: RunningProcess) -> None:
        if running.process.poll() is None:
            try:
                self.wineserver_command(running.prefix, "-k", timeout=5.0)
            except (OSError, subprocess.TimeoutExpired):
                pass
        if running.process.poll() is None:
            try:
                os.killpg(running.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            running.process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            pass
        running.close_files()

    def startup_probe(self) -> None:
        started = time.monotonic()
        running = self.launch("startup", self.work_dir / "prefix-startup", ["--sleep", "5"])
        try:
            markers = self.wait_for_markers(running)
            alive = running.process.poll() is None
            self.record("start procesu", started, markers and alive, f"launcher PID {running.process.pid}; process alive={alive}")
            self.record("PID", started, running.process.pid > 0 and alive, f"PID={running.process.pid}; positive and running={alive}")
            stdout_ok = self.contains(running.stdout_path, STDOUT_MARKER)
            stderr_ok = self.contains(running.stderr_path, STDERR_MARKER)
            self.record("stdout", started, stdout_ok, f"{STDOUT_MARKER} present={stdout_ok}; log={running.stdout_path}")
            self.record("stderr", started, stderr_ok, f"{STDERR_MARKER} present={stderr_ok}; log={running.stderr_path}")
        finally:
            self.cleanup(running)

    def exit_code(self) -> None:
        started = time.monotonic()
        running = self.launch("exit-code", self.work_dir / "prefix-exit-code", ["--sleep", "0", "--exit-code", "37"])
        try:
            actual = running.process.wait(timeout=self.timeout)
            self.record("exit code", started, actual == 37, f"expected=37; actual={actual}")
        finally:
            self.cleanup(running)

    def normal_exit(self) -> None:
        started = time.monotonic()
        running = self.launch("normal-exit", self.work_dir / "prefix-normal-exit", ["--sleep", "1"])
        try:
            actual = running.process.wait(timeout=self.timeout)
            markers = self.contains(running.stdout_path, STDOUT_MARKER) and self.contains(running.stderr_path, STDERR_MARKER)
            self.record("normalne zamknięcie", started, actual == 0 and markers, f"exit={actual}; both markers present={markers}")
        finally:
            self.cleanup(running)

    def stop(self) -> None:
        started = time.monotonic()
        running = self.launch("stop", self.work_dir / "prefix-stop", ["--sleep", "60"])
        try:
            ready = self.wait_for_markers(running)
            running.process.terminate()
            actual = running.process.wait(timeout=self.timeout)
            try:
                server_wait = self.wineserver_command(running.prefix, "-w", timeout=5.0)
                no_windows_processes = server_wait.returncode == 0
            except subprocess.TimeoutExpired:
                no_windows_processes = False
            self.record("Stop", started, ready and actual != 0 and no_windows_processes, f"ready={ready}; launcher exit={actual}; wineserver -w completed={no_windows_processes}")
        finally:
            self.cleanup(running)

    def force_quit(self) -> None:
        started = time.monotonic()
        running = self.launch("force-quit", self.work_dir / "prefix-force-quit", ["--sleep", "60"])
        try:
            ready = self.wait_for_markers(running)
            server = self.wineserver_command(running.prefix, "-k")
            launcher_sigkill_required = False
            if running.process.poll() is None:
                launcher_sigkill_required = True
                os.killpg(running.process.pid, signal.SIGKILL)
            actual = running.process.wait(timeout=self.timeout)
            self.record(
                "Force Quit",
                started,
                ready and server.returncode == 0 and running.process.poll() is not None,
                f"ready={ready}; wineserver -k exit={server.returncode}; launcher exit={actual}; fallback SIGKILL={launcher_sigkill_required}",
            )
        finally:
            self.cleanup(running)

    def isolation(self) -> None:
        started = time.monotonic()
        first = self.launch("isolation-a", self.work_dir / "prefix-isolation-a", ["--sleep", "60"])
        second = self.launch("isolation-b", self.work_dir / "prefix-isolation-b", ["--sleep", "60"])
        try:
            both_ready = self.wait_for_markers(first) and self.wait_for_markers(second)
            server = self.wineserver_command(first.prefix, "-k")
            try:
                first.process.wait(timeout=5.0)
                first_stopped = True
            except subprocess.TimeoutExpired:
                first_stopped = False
            time.sleep(1.0)
            second_alive = second.process.poll() is None
            isolated = both_ready and server.returncode == 0 and first_stopped and second_alive
            self.record(
                "dwa środowiska i izolacja wineserver -k",
                started,
                isolated,
                f"both ready={both_ready}; prefix A stopped={first_stopped}; prefix B alive={second_alive}; wineserver exit={server.returncode}",
            )
        finally:
            self.cleanup(first)
            self.cleanup(second)

    def session_recovery(self) -> None:
        started = time.monotonic()
        prefix = self.work_dir / "prefix-session-recovery"
        log_dir = self.work_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        stdout_path = log_dir / "session-recovery.stdout.log"
        stderr_path = log_dir / "session-recovery.stderr.log"
        receipt_path = self.work_dir / "session-recovery-receipt.json"
        helper = Path(__file__).resolve().parent / "orphan_launcher.py"
        recovered_state = "unknown"
        kill_result = -1
        orphan_stopped = False
        relaunch_ok = False
        orphan_pid = -1
        try:
            owner = subprocess.run(
                [
                    sys.executable,
                    str(helper),
                    "--wine", str(self.wine),
                    "--exe", str(self.executable),
                    "--prefix", str(prefix),
                    "--stdout", str(stdout_path),
                    "--stderr", str(stderr_path),
                    "--receipt", str(receipt_path),
                ],
                env=self.environment(prefix),
                timeout=10.0,
                check=False,
            )
            if owner.returncode != 0 or not receipt_path.is_file():
                raise RuntimeError(f"orphan owner exit={owner.returncode}; receipt present={receipt_path.is_file()}")
            orphan_pid = int(json.loads(receipt_path.read_text(encoding="utf-8"))["launcherPID"])
            markers = self.wait_for_file_markers(stdout_path, stderr_path)
            recovered_state = self.probe_environment_session(prefix)
            self.record(
                "Boreal restart recovers active environment",
                started,
                markers and recovered_state == "active",
                f"owner exited; forgotten launcher PID={orphan_pid}; prefix state={recovered_state}",
            )

            server = self.wineserver_command(prefix, "-k")
            kill_result = server.returncode
            orphan_stopped = self.wait_for_pid_exit(orphan_pid)
            inactive_after_kill = self.probe_environment_session(prefix) == "inactive"
            self.record(
                "recovered environment force quit without old PID",
                started,
                kill_result == 0 and orphan_stopped and inactive_after_kill,
                f"wineserver -k exit={kill_result}; orphan stopped={orphan_stopped}; inactive={inactive_after_kill}",
            )

            relaunched = self.launch("session-recovery-relaunch", prefix, ["--sleep", "0"])
            try:
                relaunch_exit = relaunched.process.wait(timeout=self.timeout)
                relaunch_ok = relaunch_exit == 0 and self.contains(relaunched.stdout_path, STDOUT_MARKER)
            finally:
                self.cleanup(relaunched)
            self.record(
                "same prefix relaunches after recovery cleanup",
                started,
                relaunch_ok,
                f"relaunch successful={relaunch_ok}",
            )
        finally:
            try:
                self.wineserver_command(prefix, "-k", timeout=5.0)
            except (OSError, subprocess.TimeoutExpired):
                pass
            if orphan_pid > 0 and self.process_exists(orphan_pid):
                try:
                    os.killpg(orphan_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def child_process_semantics(self) -> None:
        started = time.monotonic()
        prefix = self.work_dir / "prefix-child-process"
        running = self.launch("child-process", prefix, ["--spawn-child", "30"])
        try:
            child_ready = self.wait_for_file_markers(
                running.stdout_path,
                running.stderr_path,
                stdout_marker=CHILD_MARKER,
            )
            try:
                launcher_exit = running.process.wait(timeout=10.0)
                launcher_gone = True
            except subprocess.TimeoutExpired:
                launcher_exit = None
                launcher_gone = False
            state_after_launcher = self.probe_environment_session(prefix)
            self.record(
                "launcher exit does not imply environment inactivity",
                started,
                child_ready and launcher_gone and state_after_launcher == "active",
                f"child ready={child_ready}; launcher exit={launcher_exit}; prefix state={state_after_launcher}",
            )
            self.record(
                "child process keeps environment active",
                started,
                child_ready and state_after_launcher == "active",
                f"{CHILD_MARKER} present={child_ready}; prefix state={state_after_launcher}",
            )

            state_after_probe = self.probe_environment_session(prefix)
            child_still_alive = state_after_probe == "active"
            self.record(
                "environmentSessionState probe does not alter active session",
                started,
                state_after_launcher == "active" and child_still_alive,
                f"first probe={state_after_launcher}; second probe={state_after_probe}",
            )

            server = self.wineserver_command(prefix, "-k")
            inactive = self.probe_environment_session(prefix) == "inactive"
            self.record(
                "environment inactive only after wineserver session ends",
                started,
                server.returncode == 0 and inactive,
                f"wineserver -k exit={server.returncode}; inactive after kill={inactive}",
            )
        finally:
            self.cleanup(running)

    def run(self) -> list[Result]:
        tests: Sequence[Callable[[], None]] = (
            self.startup_probe,
            self.exit_code,
            self.normal_exit,
            self.stop,
            self.force_quit,
            self.isolation,
            self.session_recovery,
            self.child_process_semantics,
        )
        for test in tests:
            try:
                test()
            except BaseException as error:
                started = time.monotonic()
                self.record(test.__name__, started, False, f"{type(error).__name__}: {error}")
        return self.results


def executable_path(value: str, label: str) -> Path:
    expanded = Path(value).expanduser().resolve()
    if not expanded.is_file() or not os.access(expanded, os.X_OK):
        raise argparse.ArgumentTypeError(f"{label} is not executable: {expanded}")
    return expanded


def markdown_report(started_at: str, wine: Path, executable: Path, results: Sequence[Result]) -> str:
    lines = [
        "# Boreal P0 Runtime Harness Report",
        "",
        f"- Generated: `{started_at}`",
        f"- Wine: `{wine}`",
        f"- Test executable: `{executable}`",
        "",
        "| Case | Result | Duration | Detail |",
        "| --- | --- | ---: | --- |",
    ]
    for result in results:
        detail = result.detail.replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {result.case} | **{result.status}** | {result.duration_seconds:.3f}s | {detail} |")
    lines.append("")
    lines.append(f"Overall: **{'PASS' if results and all(item.status == 'PASS' for item in results) else 'FAIL'}**")
    lines.append("")
    return "\n".join(lines)


def parse_arguments() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wine", required=True, help="absolute path to the Boreal runtime wine executable")
    parser.add_argument("--wineserver", help="path to wineserver; defaults to a sibling of --wine")
    parser.add_argument("--exe", default=str(script_dir / "bin" / "BorealRuntimeTest.exe"))
    parser.add_argument("--work-dir", help="persistent work directory; otherwise a temporary directory is used")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--json-report", default=str(script_dir / "Reports" / "latest.json"))
    parser.add_argument("--markdown-report", default=str(script_dir / "Reports" / "latest.md"))
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        wine = executable_path(arguments.wine, "wine")
        wineserver = executable_path(arguments.wineserver or str(wine.parent / "wineserver"), "wineserver")
        executable = Path(arguments.exe).expanduser().resolve()
        if not executable.is_file():
            raise ValueError(f"test executable does not exist: {executable}; run ./build.sh first")
        if arguments.timeout <= 0:
            raise ValueError("--timeout must be greater than zero")
    except (ValueError, argparse.ArgumentTypeError) as error:
        print(f"PREFLIGHT FAIL: {error}", file=sys.stderr)
        return 2

    started_at = datetime.now(timezone.utc).isoformat()
    temporary: tempfile.TemporaryDirectory[str] | None = None
    if arguments.work_dir:
        work_dir = Path(arguments.work_dir).expanduser().resolve()
        work_dir.mkdir(parents=True, exist_ok=True)
    else:
        temporary = tempfile.TemporaryDirectory(prefix="boreal-p0-runtime-")
        work_dir = Path(temporary.name)

    harness = Harness(wine, wineserver, executable, work_dir, arguments.timeout)
    results = harness.run()
    payload = {
        "generatedAt": started_at,
        "wine": str(wine),
        "wineserver": str(wineserver),
        "executable": str(executable),
        "overall": "PASS" if results and all(result.status == "PASS" for result in results) else "FAIL",
        "results": [asdict(result) for result in results],
    }

    json_path = Path(arguments.json_report).expanduser().resolve()
    markdown_path = Path(arguments.markdown_report).expanduser().resolve()
    json_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    markdown_path.write_text(markdown_report(started_at, wine, executable, results), encoding="utf-8")

    print(markdown_report(started_at, wine, executable, results))
    print(f"JSON report: {json_path}")
    print(f"Markdown report: {markdown_path}")
    if temporary is not None:
        temporary.cleanup()
    return 0 if payload["overall"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
