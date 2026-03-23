# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC IP — Directed cocotb tests for crc_top
===========================================
Tests CRC-32/ISO-HDLC (Ethernet) by default.
Override CRC_W via environment variable for other widths.
"""

import os
import sys
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Add model to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../model'))
from crc_model import CRCModel, crc32_iso_hdlc, crc16_ccitt, crc8_autosar

CRC_W  = int(os.environ.get("CRC_W", "32"))
DATA_W = int(os.environ.get("DATA_W", "8"))


def get_model():
    """Return appropriate model for the current CRC_W."""
    if CRC_W == 32:
        return crc32_iso_hdlc()
    elif CRC_W == 16:
        return crc16_ccitt()
    elif CRC_W == 8:
        return crc8_autosar()
    else:
        return crc32_iso_hdlc()


def make_cfg(model):
    """Build s_cfg packed value from model config."""
    # crc_config_t is packed: {polynomial, init_val, final_xor, reflect_in, reflect_out}
    # Total width: CRC_W*3 + 2
    poly = model.polynomial & ((1 << CRC_W) - 1)
    init = model.init_val & ((1 << CRC_W) - 1)
    xor  = model.final_xor & ((1 << CRC_W) - 1)
    ri   = int(model.reflect_in)
    ro   = int(model.reflect_out)
    cfg = (poly << (CRC_W * 2 + 2)) | (init << (CRC_W + 2)) | (xor << 2) | (ri << 1) | ro
    return cfg


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start_i.value = 0
    dut.s_data_valid.value = 0
    dut.s_data.value = 0
    dut.s_last.value = 0
    dut.s_cfg.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def compute_crc(dut, data: bytes, model: CRCModel):
    """Feed data bytes and return DUT CRC result."""
    cfg_val = make_cfg(model)
    dut.s_cfg.value = cfg_val

    # Start
    dut.start_i.value = 1
    await RisingEdge(dut.clk)
    dut.start_i.value = 0
    await RisingEdge(dut.clk)  # core_init captured

    # Stream data
    for i, b in enumerate(data):
        dut.s_data.value = b
        dut.s_data_valid.value = 1
        dut.s_last.value = 1 if i == len(data) - 1 else 0
        await RisingEdge(dut.clk)

    dut.s_data_valid.value = 0
    dut.s_last.value = 0

    # Wait for done
    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.done_o.value == 1:
            break

    crc_val = int(dut.crc_o.value) & ((1 << CRC_W) - 1)
    return crc_val


# ── Tests ────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_check_string(dut):
    """T01: CRC of '123456789' matches known check value."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    model = get_model()
    data = b"123456789"
    expected = model.compute(data)

    got = await compute_crc(dut, data, model)
    dut._log.info(f"[T01] CRC-{CRC_W} of '123456789': 0x{got:0{CRC_W//4}X} "
                  f"(expected 0x{expected:0{CRC_W//4}X})")
    assert got == expected, f"CRC mismatch: 0x{got:X} != 0x{expected:X}"


@cocotb.test()
async def test_single_byte(dut):
    """T02: CRC of single byte 0x00."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    model = get_model()
    data = b"\x00"
    expected = model.compute(data)

    got = await compute_crc(dut, data, model)
    dut._log.info(f"[T02] CRC-{CRC_W} of 0x00: 0x{got:0{CRC_W//4}X}")
    assert got == expected


@cocotb.test()
async def test_all_ff(dut):
    """T03: CRC of 4 bytes 0xFF."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    model = get_model()
    data = b"\xFF\xFF\xFF\xFF"
    expected = model.compute(data)

    got = await compute_crc(dut, data, model)
    dut._log.info(f"[T03] CRC-{CRC_W} of 0xFFFFFFFF: 0x{got:0{CRC_W//4}X}")
    assert got == expected


@cocotb.test()
async def test_back_to_back(dut):
    """T04: Two consecutive CRC computations without external reset."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    model = get_model()
    data = b"123456789"
    expected = model.compute(data)

    got1 = await compute_crc(dut, data, model)
    await ClockCycles(dut.clk, 2)
    got2 = await compute_crc(dut, data, model)

    dut._log.info(f"[T04] Back-to-back: 0x{got1:0{CRC_W//4}X}, 0x{got2:0{CRC_W//4}X}")
    assert got1 == expected and got2 == expected


@cocotb.test()
async def test_long_message(dut):
    """T05: 256-byte random message."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    model = get_model()
    rng = random.Random(0xDEAD)
    data = bytes([rng.randint(0, 255) for _ in range(256)])
    expected = model.compute(data)

    got = await compute_crc(dut, data, model)
    dut._log.info(f"[T05] 256B random: 0x{got:0{CRC_W//4}X}")
    assert got == expected


@cocotb.test()
async def test_random_sweep(dut):
    """T06: 20 random-length random-data messages."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    model = get_model()
    rng = random.Random(0xBEEF)
    mismatches = 0

    for i in range(20):
        length = rng.randint(1, 128)
        data = bytes([rng.randint(0, 255) for _ in range(length)])
        expected = model.compute(data)
        got = await compute_crc(dut, data, model)
        if got != expected:
            dut._log.error(f"  Mismatch #{i}: len={length} "
                          f"got=0x{got:0{CRC_W//4}X} expected=0x{expected:0{CRC_W//4}X}")
            mismatches += 1
        await ClockCycles(dut.clk, 2)

    dut._log.info(f"[T06] 20 random messages: {20-mismatches}/20 matched")
    assert mismatches == 0


@cocotb.test()
async def test_version(dut):
    """T07: Version register."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    ver = int(dut.version_o.value)
    dut._log.info(f"[T07] VERSION = 0x{ver:08X}")
    assert ver == 0x00010000
