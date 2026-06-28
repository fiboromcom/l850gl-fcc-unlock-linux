#!/usr/bin/env python3
"""
l850gl-fcc-unlock.py

AT-command helper for clearing the Fibocom L850-GL / Intel XMM7360 FCC lock.

Public reference command sequence:

    at@nvm:fix_cat_fcclock.fcclock_mode=0
    at@store_nvm(fix_cat_fcclock)

This script intentionally requires an explicit confirmation flag before writing.
"""

import argparse
import os
import re
import sys
import time
from pathlib import Path

try:
    import serial
except ImportError:
    print("ERROR: missing pyserial. On Fedora: sudo dnf install python3-pyserial", file=sys.stderr)
    raise

DEFAULT_PORT = "/dev/ttyACM0"
MARKER = Path("/etc/l850gl-fcc-unlock.done")


def read_available(ser: serial.Serial, deadline: float) -> str:
    chunks: list[bytes] = []
    while time.time() < deadline:
        waiting = ser.in_waiting
        if waiting:
            chunks.append(ser.read(waiting))
            blob = b"".join(chunks)
            if b"\r\nOK\r\n" in blob or b"\nOK\r" in blob or b"\r\nERROR\r\n" in blob or b"\nERROR\r" in blob:
                break
        time.sleep(0.05)
    return b"".join(chunks).decode("utf-8", errors="replace")


def send_at(ser: serial.Serial, command: str, timeout: float = 3.0) -> str:
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    ser.write((command + "\r").encode("ascii"))
    ser.flush()
    response = read_available(ser, time.time() + timeout)
    print(f">>> {command}")
    print(response.strip() if response.strip() else "(no response)")
    print()
    return response


def response_ok(response: str) -> bool:
    return bool(re.search(r"(^|\r|\n)OK(\r|\n|$)", response))


def parse_mode(response: str) -> str | None:
    # Known output styles vary. Accept any bare integer after the command echo/noise.
    for line in response.replace("\r", "\n").split("\n"):
        line = line.strip()
        if re.fullmatch(r"[0-9]+", line):
            return line
        m = re.search(r"fcclock_mode[^0-9]*([0-9]+)", line, re.IGNORECASE)
        if m:
            return m.group(1)
    nums = re.findall(r"\b[0-9]+\b", response)
    return nums[-1] if nums else None


def main() -> int:
    parser = argparse.ArgumentParser(description="Clear/check Fibocom L850-GL FCC lock.")
    parser.add_argument("--port", default=DEFAULT_PORT, help=f"AT serial port, default {DEFAULT_PORT}")
    parser.add_argument("--check-only", action="store_true", help="Only query FCC lock mode; do not write")
    parser.add_argument("--persistent", action="store_true", help="Store FCC unlock change in NVM")
    parser.add_argument("--yes-i-understand-regulatory-risk", action="store_true", help="Required for any write")
    parser.add_argument("--marker", default=str(MARKER), help=f"Marker path, default {MARKER}")
    args = parser.parse_args()

    if not os.path.exists(args.port):
        print(f"ERROR: port not found: {args.port}", file=sys.stderr)
        print("Run prepare-usb-mode-fedora.sh first.", file=sys.stderr)
        return 1

    if not args.check_only and not args.yes_i_understand_regulatory_risk:
        print("ERROR: refusing to write without --yes-i-understand-regulatory-risk", file=sys.stderr)
        return 2

    marker = Path(args.marker)

    with serial.Serial(args.port, baudrate=115200, timeout=0.2, write_timeout=2) as ser:
        time.sleep(0.5)

        # Wake/check AT.
        ok = False
        for _ in range(3):
            if response_ok(send_at(ser, "AT")):
                ok = True
                break
            time.sleep(0.5)
        if not ok:
            print("ERROR: modem did not respond OK to AT", file=sys.stderr)
            return 1

        query = send_at(ser, "at@nvm:fix_cat_fcclock.fcclock_mode?", timeout=4.0)
        mode = parse_mode(query)
        if mode is not None:
            print(f"Detected fcclock_mode={mode}")
        else:
            print("WARNING: could not parse fcclock_mode from response")

        if args.check_only:
            return 0

        if mode == "0":
            print("FCC lock mode already appears to be 0; no write needed.")
        else:
            set_resp = send_at(ser, "at@nvm:fix_cat_fcclock.fcclock_mode=0", timeout=4.0)
            if not response_ok(set_resp):
                print("ERROR: set command did not return OK", file=sys.stderr)
                return 1

            verify = send_at(ser, "at@nvm:fix_cat_fcclock.fcclock_mode?", timeout=4.0)
            new_mode = parse_mode(verify)
            if new_mode is not None:
                print(f"Detected fcclock_mode after set={new_mode}")

        if args.persistent:
            store = send_at(ser, "at@store_nvm(fix_cat_fcclock)", timeout=6.0)
            if not response_ok(store):
                print("ERROR: persistent store command did not return OK", file=sys.stderr)
                return 1

            try:
                marker.write_text(
                    "Fibocom L850-GL FCC lock persistent clear attempted successfully.\n",
                    encoding="utf-8",
                )
                os.chmod(marker, 0o644)
                print(f"Wrote marker: {marker}")
            except PermissionError:
                print(f"WARNING: could not write marker {marker}; run with sudo if you need the marker.")

    print("Done.")
    if args.persistent:
        print("Power-cycle/reboot before relying on the persistent state.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
