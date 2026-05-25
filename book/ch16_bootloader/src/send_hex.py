#!/usr/bin/env python3
"""
send_hex.py - upload an Intel HEX file to the minimal UART self-updater.

Usage:
    python3 send_hex.py /dev/ttyUSB0 firmware.hex

The script:
  1. Opens the serial port at 9600 baud.
  2. Waits for "SU\r\n" (self-updater banner).
  3. Coalesces input into 64-byte page records.
  4. Sends each data record, waits for '.' (ACK) or '!' (NACK).
  5. Sends the EOF record, waits for "OK\r\n".
"""

import sys
import time
import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
HEX_FILE = sys.argv[2] if len(sys.argv) > 2 else "firmware.hex"
BAUD = 9600
PAGE_SIZE = 64


def checksum_record(length, address, rectype, data):
    total = length + ((address >> 8) & 0xFF) + (address & 0xFF) + rectype
    total += sum(data)
    return (-total) & 0xFF


def make_record(address, rectype, data=b""):
    length = len(data)
    checksum = checksum_record(length, address, rectype, data)
    body = f":{length:02X}{address:04X}{rectype:02X}"
    body += "".join(f"{byte:02X}" for byte in data)
    body += f"{checksum:02X}"
    return body


def parse_hex_file(path):
    memory = {}
    linear_base = 0
    eof_seen = False

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or not line.startswith(":"):
                continue
            raw = bytes.fromhex(line[1:])
            length = raw[0]
            offset = (raw[1] << 8) | raw[2]
            rectype = raw[3]
            data = raw[4:4 + length]
            checksum = raw[4 + length]
            if checksum_record(length, offset, rectype, data) != checksum:
                raise ValueError(f"bad checksum in input HEX record: {line}")

            if rectype == 0x00:
                base = linear_base + offset
                for i, byte in enumerate(data):
                    memory[base + i] = byte
            elif rectype == 0x01:
                eof_seen = True
                break
            elif rectype == 0x04:
                linear_base = ((data[0] << 8) | data[1]) << 16

    if not eof_seen:
        raise ValueError("input HEX file has no EOF record")
    return memory


def coalesce_page_records(path):
    memory = parse_hex_file(path)
    if not memory:
        return [make_record(0, 0x01)]

    records = []
    start = min(memory) & ~(PAGE_SIZE - 1)
    end = (max(memory) + PAGE_SIZE) & ~(PAGE_SIZE - 1)

    for page in range(start, end, PAGE_SIZE):
        data = bytes(memory.get(page + i, 0xFF) for i in range(PAGE_SIZE))
        records.append(make_record(page & 0xFFFF, 0x00, data))
    records.append(make_record(0, 0x01))
    return records


def main():
    with serial.Serial(PORT, BAUD, timeout=5) as ser:
        print(f"Waiting for self-updater on {PORT}...")
        banner = ser.read_until(b"\n")
        if b"SU" not in banner:
            print("ERROR: self-updater banner not received")
            sys.exit(1)
        print("Self-updater ready")

        try:
            lines = coalesce_page_records(HEX_FILE)
        except ValueError as exc:
            print(f"ERROR: {exc}")
            sys.exit(1)

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
