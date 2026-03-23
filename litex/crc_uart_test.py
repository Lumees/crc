#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC UART Hardware Regression Test
===================================
Runs on Arty A7-100T via litex_server + RemoteClient.
Requires: litex_server --uart --uart-port /dev/ttyUSB1 --uart-baudrate 115200
"""

import os
import sys
import time
import random

from litex.tools.litex_client import RemoteClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../model'))
from crc_model import CRCModel, crc32_iso_hdlc, crc16_ccitt, crc8_autosar

CRC_W  = 32
DATA_W = 8
MASK   = (1 << CRC_W) - 1

PASS_COUNT = 0
FAIL_COUNT = 0


class CRCClient:
    def __init__(self, host='localhost', tcp_port=1234, csr_csv=None):
        self.client = RemoteClient(host=host, port=tcp_port, csr_csv=csr_csv)
        self.client.open()

    def close(self):
        self.client.close()

    def _w(self, reg: str, val: int):
        getattr(self.client.regs, f"crc_{reg}").write(val & 0xFFFFFFFF)

    def _r(self, reg: str) -> int:
        return int(getattr(self.client.regs, f"crc_{reg}").read())

    def configure(self, model: CRCModel):
        self._w("poly", model.polynomial & MASK)
        self._w("init_val", model.init_val & MASK)
        self._w("xor_out", model.final_xor & MASK)
        cfg = (int(model.reflect_out) << 1) | int(model.reflect_in)
        self._w("cfg", cfg)

    def start(self):
        self._w("ctrl", 0x01)

    def write_byte(self, b: int):
        self._w("data_in", b & 0xFF)

    def write_byte_last(self, b: int):
        self._w("data_last", b & 0xFF)

    def status(self) -> dict:
        s = self._r("status")
        return {"ready": bool(s & 1), "done": bool(s & 2), "busy": bool(s & 4)}

    def wait_done(self, timeout=5.0) -> bool:
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.status()["done"]:
                return True
            time.sleep(0.001)
        return False

    def read_crc(self) -> int:
        return self._r("crc_out") & MASK

    def version(self) -> int:
        return self._r("version")

    def info(self) -> dict:
        v = self._r("info")
        return {"CRC_W": v & 0xFF, "DATA_W": (v >> 8) & 0xFF}

    def compute(self, model: CRCModel, data: bytes) -> int:
        """Full CRC computation: configure, start, stream data, read result."""
        self.configure(model)
        self.start()
        time.sleep(0.001)
        for i, b in enumerate(data):
            if i == len(data) - 1:
                self.write_byte_last(b)
            else:
                self.write_byte(b)
            time.sleep(0.0001)
        self.wait_done(timeout=5.0)
        return self.read_crc()


def check(name, condition, detail=""):
    global PASS_COUNT, FAIL_COUNT
    if condition:
        print(f"  [PASS] {name}")
        PASS_COUNT += 1
    else:
        print(f"  [FAIL] {name}  {detail}")
        FAIL_COUNT += 1


# ── Tests ────────────────────────────────────────────────────────────────────

def test_version(dut: CRCClient):
    print("\n[T01] Version / Info registers")
    ver = dut.version()
    check("VERSION == 0x00010000", ver == 0x00010000, f"got 0x{ver:08X}")
    info = dut.info()
    check(f"INFO.CRC_W == {CRC_W}", info["CRC_W"] == CRC_W, f"got {info['CRC_W']}")
    check(f"INFO.DATA_W == {DATA_W}", info["DATA_W"] == DATA_W, f"got {info['DATA_W']}")


def test_check_string(dut: CRCClient):
    print("\n[T02] CRC-32 of '123456789' = 0xCBF43926")
    model = crc32_iso_hdlc()
    data = b"123456789"
    expected = model.compute(data)
    got = dut.compute(model, data)
    check(f"CRC = 0x{expected:08X}", got == expected,
          f"got 0x{got:08X}")


def test_single_byte(dut: CRCClient):
    print("\n[T03] CRC-32 of single byte 0x00")
    model = crc32_iso_hdlc()
    expected = model.compute(b"\x00")
    got = dut.compute(model, b"\x00")
    check(f"CRC = 0x{expected:08X}", got == expected,
          f"got 0x{got:08X}")


def test_all_ff(dut: CRCClient):
    print("\n[T04] CRC-32 of 0xFFFFFFFF")
    model = crc32_iso_hdlc()
    data = b"\xFF\xFF\xFF\xFF"
    expected = model.compute(data)
    got = dut.compute(model, data)
    check(f"CRC = 0x{expected:08X}", got == expected,
          f"got 0x{got:08X}")


def test_back_to_back(dut: CRCClient):
    print("\n[T05] Back-to-back CRC computations")
    model = crc32_iso_hdlc()
    data = b"123456789"
    expected = model.compute(data)
    got1 = dut.compute(model, data)
    got2 = dut.compute(model, data)
    check("First  == expected", got1 == expected, f"got 0x{got1:08X}")
    check("Second == expected", got2 == expected, f"got 0x{got2:08X}")


def test_random(dut: CRCClient):
    print("\n[T06] 10 random-length random-data messages")
    model = crc32_iso_hdlc()
    rng = random.Random(0xCAFE)
    mismatches = 0
    for i in range(10):
        length = rng.randint(1, 64)
        data = bytes([rng.randint(0, 255) for _ in range(length)])
        expected = model.compute(data)
        got = dut.compute(model, data)
        if got != expected:
            print(f"    Mismatch #{i}: len={length} got=0x{got:08X} expected=0x{expected:08X}")
            mismatches += 1
    check(f"10/10 random matched", mismatches == 0,
          f"{mismatches} mismatches")


def test_ethernet_frame(dut: CRCClient):
    print("\n[T07] Ethernet FCS verification")
    model = crc32_iso_hdlc()
    # Synthetic 20-byte payload
    payload = bytes(range(20))
    fcs = model.compute(payload)
    # Append FCS (little-endian for Ethernet)
    frame = payload + fcs.to_bytes(4, 'little')
    # CRC of frame+FCS should be the magic value 0x2144DF1C
    verify = model.compute(frame)
    check("CRC32(frame+FCS) == 0x2144DF1C (magic residue)",
          verify == 0x2144DF1C, f"got 0x{verify:08X}")
    # Now verify on hardware
    got = dut.compute(model, frame)
    check("HW CRC32(frame+FCS) == 0x2144DF1C",
          got == 0x2144DF1C, f"got 0x{got:08X}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    csr_csv = os.path.join(os.path.dirname(__file__),
                           'build/digilent_arty/csr.csv')
    if not os.path.exists(csr_csv):
        csr_csv = None

    dut = CRCClient(csr_csv=csr_csv)

    try:
        print("=" * 60)
        print("CRC UART Hardware Regression")
        print(f"  CRC_W={CRC_W} DATA_W={DATA_W}")
        print("=" * 60)

        test_version(dut)
        test_check_string(dut)
        test_single_byte(dut)
        test_all_ff(dut)
        test_back_to_back(dut)
        test_random(dut)
        test_ethernet_frame(dut)

        print("\n" + "=" * 60)
        total = PASS_COUNT + FAIL_COUNT
        print(f"Result: {PASS_COUNT}/{total} PASS  {FAIL_COUNT}/{total} FAIL")
        print("=" * 60)
        sys.exit(0 if FAIL_COUNT == 0 else 1)

    finally:
        dut.close()


if __name__ == "__main__":
    main()
