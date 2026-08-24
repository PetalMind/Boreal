#!/usr/bin/env python3
"""Launch Wine and exit immediately, simulating loss of Boreal process state."""

import argparse
import json
import os
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wine", required=True)
    parser.add_argument("--exe", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--stdout", required=True)
    parser.add_argument("--stderr", required=True)
    parser.add_argument("--receipt", required=True)
    arguments = parser.parse_args()

    prefix = Path(arguments.prefix)
    prefix.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["WINEPREFIX"] = str(prefix)
    environment["WINEARCH"] = "win64"

    stdout = Path(arguments.stdout).open("wb")
    stderr = Path(arguments.stderr).open("wb")
    process = subprocess.Popen(
        [arguments.wine, arguments.exe, "--sleep", "60"],
        cwd=str(Path(arguments.exe).parent),
        env=environment,
        stdout=stdout,
        stderr=stderr,
        start_new_session=True,
    )
    receipt = Path(arguments.receipt)
    receipt.write_text(json.dumps({"launcherPID": process.pid}) + "\n", encoding="utf-8")
    with receipt.open("rb") as handle:
        os.fsync(handle.fileno())
    os._exit(0)


if __name__ == "__main__":
    raise SystemExit(main())
