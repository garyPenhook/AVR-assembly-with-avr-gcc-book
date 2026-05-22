#!/usr/bin/env python3
"""
send_hex.py — upload an Intel HEX file to the minimal UART bootloader.

Usage:
    python3 send_hex.py /dev/ttyUSB0 firmware.hex

The script:
  1. Opens the serial port at 9600 baud.
  2. Waits for "BL\r\n" (bootloader banner).
  3. Sends each data record, waits for '.' (ACK) or '!' (NACK).
  4. Sends the EOF record, waits for "OK\r\n".
"""

import sys
import time
import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
HEX_FILE = sys.argv[2] if len(sys.argv) > 2 else "firmware.hex"
BAUD = 9600


def main():
    with serial.Serial(PORT, BAUD, timeout=5) as ser:
        print(f"Waiting for bootloader on {PORT}...")
        banner = ser.read_until(b"\n")
        if b"BL" not in banner:
            print("ERROR: bootloader banner not received")
            sys.exit(1)
        print("Bootloader ready")

        with open(HEX_FILE) as f:
            lines = [l.strip() for l in f if l.strip().startswith(":")]

        for i, record in enumerate(lines):
            ser.write((record + "\r\n").encode())
            resp = ser.read(1)
            if resp == b".":
                print(f"  record {i+1}/{len(lines)} OK")
            elif resp == b"!":
                print(f"  record {i+1} CHECKSUM ERROR: {record}")
                sys.exit(1)
            else:
                print(f"  unexpected response: {resp!r}")
                sys.exit(1)
            time.sleep(0.01)

        # Wait for OK after EOF record
        ok = ser.read_until(b"\n")
        if b"OK" in ok:
            print("Upload complete. Application starting.")
        else:
            print(f"Unexpected final response: {ok!r}")


if __name__ == "__main__":
    main()
