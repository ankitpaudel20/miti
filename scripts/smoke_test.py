#!/usr/bin/env python3
"""End-to-end check of a built miti binary, on any OS: CLI, JSON contract, and (unix) the daemon.

Usage: scripts/smoke_test.py [path/to/miti]   (default target/debug/miti)
The JSON key set is what every widget under widgets/ decodes; changing it breaks them.
"""

import json
import os
import socket
import subprocess
import sys
import tempfile
import time

DAY_KEYS = {
    "bs",
    "ad",
    "year",
    "month",
    "day",
    "weekday",
    "year_np",
    "month_np",
    "day_np",
    "weekday_np",
    "month_en",
    "weekday_en",
    "tithi",
    "holiday",
    "event_np",
    "event_en",
}
MONTH_KEYS = {"year", "month", "year_np", "month_np", "month_en", "days"}

exe = sys.argv[1] if len(sys.argv) > 1 else "target/debug/miti"
if sys.platform == "win32" and not exe.endswith(".exe"):
    exe += ".exe"


def cli(*args, ok=True):
    p = subprocess.run([exe, *args], capture_output=True, encoding="utf-8")
    assert (p.returncode == 0) == ok, (
        f"{args}: exit {p.returncode}\n{p.stdout}{p.stderr}"
    )
    return p.stdout.strip()


def check(cond, msg):
    if not cond:
        sys.exit(f"FAIL: {msg}")
    print("ok:", msg)


today = json.loads(cli("today", "-j"))
check(set(today) == DAY_KEYS, "today -j has the widget key set")

# A known pair.
check(cli("bs2ad", "2083-07-27") == "2026-11-13", "bs2ad 2083-07-27")
check(
    json.loads(cli("ad2bs", "2026-11-13", "-j"))["bs"] == "2083-07-27",
    "ad2bs 2026-11-13",
)

month = json.loads(cli("month", "2083-07"))
check(
    set(month) == MONTH_KEYS and len(month["days"]) == 30, "month 2083-07 has 30 days"
)
check(
    all(set(d) == DAY_KEYS for d in month["days"]), "month days have the widget key set"
)
check(month["days"][0]["bs"] == "2083-07-01", "month starts on day 1")

cli("bs2ad", "nope", ok=False)
cli("bs2ad", "2083-08-30", ok=False)  # Mangsir 2083 has 29 days
print("ok: bad input exits non-zero")

if sys.platform == "win32":
    sys.exit(0)  # no daemon there

# Daemon: unix sockets have a ~100 byte path limit, so use a short directory.
with tempfile.TemporaryDirectory(dir="/tmp") as d:
    env = {**os.environ, "XDG_RUNTIME_DIR": d, "TMPDIR": d}
    sock = f"{d}/miti.sock"
    daemon = subprocess.Popen([exe, "serve"], env=env)
    try:
        for _ in range(50):
            if os.path.exists(sock):
                break
            time.sleep(0.1)

        def ask(line):
            with socket.socket(socket.AF_UNIX) as s:
                s.settimeout(5)
                s.connect(sock)
                s.sendall(line.encode() + b"\n")
                return s.makefile().read().strip()

        check(ask("bs2ad 2083-07-27") == "2026-11-13", "daemon answers bs2ad")
        check(set(json.loads(ask("today -j"))) == DAY_KEYS, "daemon answers today -j")
        check(ask("bs2ad nope").startswith("error:"), "daemon reports errors in-band")
    finally:
        daemon.terminate()
        daemon.wait()
