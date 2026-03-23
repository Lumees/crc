#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC Golden Model — Lumees Lab
==============================
Bit-accurate CRC reference supporting CRC-8/16/32/64 with arbitrary
polynomial, init, final XOR, and input/output reflection.

Usage:
    m = crc32_iso_hdlc()
    assert m.compute(b"123456789") == 0xCBF43926
"""

from __future__ import annotations


class CRCModel:
    """Generic CRC calculator."""

    def __init__(self, width: int, polynomial: int, init_val: int,
                 reflect_in: bool, reflect_out: bool, final_xor: int):
        self.width = width
        self.polynomial = polynomial & ((1 << width) - 1)
        self.init_val = init_val & ((1 << width) - 1)
        self.reflect_in = reflect_in
        self.reflect_out = reflect_out
        self.final_xor = final_xor & ((1 << width) - 1)
        self.mask = (1 << width) - 1
        self.msb = 1 << (width - 1)
        self.crc = self.init_val

    def reset(self):
        self.crc = self.init_val

    @staticmethod
    def _reflect(val: int, width: int) -> int:
        """Bit-reverse *val* within *width* bits."""
        r = 0
        for i in range(width):
            if val & (1 << i):
                r |= 1 << (width - 1 - i)
        return r

    def update_byte(self, byte: int):
        """Process one byte (MSB-first after optional reflect)."""
        b = self._reflect(byte, 8) if self.reflect_in else byte
        self.crc ^= b << (self.width - 8)
        for _ in range(8):
            if self.crc & self.msb:
                self.crc = ((self.crc << 1) ^ self.polynomial) & self.mask
            else:
                self.crc = (self.crc << 1) & self.mask

    def update(self, data: bytes):
        for b in data:
            self.update_byte(b)

    def finalize(self) -> int:
        crc = self.crc
        if self.reflect_out:
            crc = self._reflect(crc, self.width)
        return (crc ^ self.final_xor) & self.mask

    def compute(self, data: bytes) -> int:
        self.reset()
        self.update(data)
        return self.finalize()


# ── Preset factory functions ─────────────────────────────────────────────────

def crc32_iso_hdlc() -> CRCModel:
    """CRC-32/ISO-HDLC (Ethernet, PKZIP, MPEG-2 complement)."""
    return CRCModel(32, 0x04C11DB7, 0xFFFFFFFF, True, True, 0xFFFFFFFF)

def crc16_ccitt() -> CRCModel:
    """CRC-16/CCITT-FALSE (X.25, V.41)."""
    return CRCModel(16, 0x1021, 0xFFFF, False, False, 0x0000)

def crc8_autosar() -> CRCModel:
    """CRC-8/AUTOSAR (SAE J1850)."""
    return CRCModel(8, 0x2F, 0xFF, False, False, 0xFF)

def crc64_ecma() -> CRCModel:
    """CRC-64/ECMA-182."""
    return CRCModel(64, 0x42F0E1EBA9EA3693, 0x0000000000000000,
                    False, False, 0x0000000000000000)

def crc64_xz() -> CRCModel:
    """CRC-64/XZ (used in xz/lzma compression)."""
    return CRCModel(64, 0x42F0E1EBA9EA3693, 0xFFFFFFFFFFFFFFFF,
                    True, True, 0xFFFFFFFFFFFFFFFF)


# ── Self-test ────────────────────────────────────────────────────────────────

def _self_test():
    CHECK = b"123456789"

    tests = [
        ("CRC-32/ISO-HDLC", crc32_iso_hdlc(), 0xCBF43926),
        ("CRC-16/CCITT-FALSE", crc16_ccitt(), 0x29B1),
        ("CRC-8/AUTOSAR", crc8_autosar(), 0xDF),
        ("CRC-64/ECMA-182", crc64_ecma(), 0x6C40DF5F0B497347),
        ("CRC-64/XZ", crc64_xz(), 0x995DC9BBDF1939FA),
    ]

    passed = 0
    for name, model, expected in tests:
        got = model.compute(CHECK)
        ok = got == expected
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {name}: 0x{got:0{model.width // 4}X}"
              f" (expected 0x{expected:0{model.width // 4}X})")
        if ok:
            passed += 1

    # Back-to-back test: compute twice without external reset
    m = crc32_iso_hdlc()
    r1 = m.compute(CHECK)
    r2 = m.compute(CHECK)
    ok = r1 == r2 == 0xCBF43926
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] CRC-32 back-to-back: 0x{r1:08X}, 0x{r2:08X}")
    if ok:
        passed += 1

    # Single-byte test
    m = crc32_iso_hdlc()
    r = m.compute(b"\x00")
    ok = r == 0xD202EF8D
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] CRC-32 single 0x00: 0x{r:08X} (expected 0xD202EF8D)")
    if ok:
        passed += 1

    total = len(tests) + 2
    print(f"\n  {passed}/{total} self-tests passed")
    return passed == total


if __name__ == "__main__":
    print("CRC Model Self-Test")
    print("=" * 40)
    ok = _self_test()
    exit(0 if ok else 1)
