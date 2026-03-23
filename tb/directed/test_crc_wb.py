# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC IP — Directed cocotb tests for crc_wb (Wishbone B4 Classic wrapper)
========================================================================
Exercises the CRC Wishbone register interface: VERSION, INFO, CRC-32
computation via DIN/DIN_LAST, back-to-back runs, and IRQ pulse detection.

Register map (byte offsets, decoded via ADR_I[5:2]):
  0x00  CTRL      RW   [0]=start  [1]=busy(RO)  [2]=done(RO)
  0x04  STATUS    RO   [0]=reflect_in_lat [1]=reflect_out_lat
  0x08  INFO      RO   {DATA_W[7:0], CRC_W[7:0]}
  0x0C  VERSION   RO   IP_VERSION (0x00010000)
  0x10  POLY      RW   Polynomial
  0x14  INIT      RW   Init value
  0x18  XOROUT    RW   Final XOR
  0x1C  CFG       RW   [0]=reflect_in [1]=reflect_out
  0x20  DIN       W    Data input
  0x24  DIN_LAST  W    Data input + last
  0x28  DOUT      RO   CRC result
"""

import os
import sys
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Add model to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../model'))
from crc_model import CRCModel, crc32_iso_hdlc, crc16_ccitt, crc8_autosar

CRC_W  = int(os.environ.get("CRC_W", "32"))
DATA_W = int(os.environ.get("DATA_W", "8"))
CRC_MASK = (1 << CRC_W) - 1

CLK_NS = 10

# ── Register byte-address offsets ────────────────────────────────────────────
REG_CTRL     = 0x00
REG_STATUS   = 0x04
REG_INFO     = 0x08
REG_VERSION  = 0x0C
REG_POLY     = 0x10
REG_INIT     = 0x14
REG_XOROUT   = 0x18
REG_CFG      = 0x1C
REG_DIN      = 0x20
REG_DIN_LAST = 0x24
REG_DOUT     = 0x28


def get_model():
    """Return appropriate CRC model for the current CRC_W."""
    if CRC_W == 32:
        return crc32_iso_hdlc()
    elif CRC_W == 16:
        return crc16_ccitt()
    elif CRC_W == 8:
        return crc8_autosar()
    else:
        return crc32_iso_hdlc()


# ── Wishbone Classic helpers ─────────────────────────────────────────────────

async def wb_write(dut, addr, data):
    """Single Wishbone Classic write cycle."""
    dut.ADR_I.value = addr
    dut.DAT_I.value = data & 0xFFFFFFFF
    dut.WE_I.value  = 1
    dut.SEL_I.value = 0xF
    dut.STB_I.value = 1
    dut.CYC_I.value = 1
    for _ in range(20):
        await RisingEdge(dut.CLK_I)
        if int(dut.ACK_O.value) == 1:
            dut.STB_I.value = 0
            dut.CYC_I.value = 0
            dut.WE_I.value  = 0
            await RisingEdge(dut.CLK_I)
            return
    raise TimeoutError(f"wb_write timeout at 0x{addr:02X}")


async def wb_read(dut, addr) -> int:
    """Single Wishbone Classic read cycle."""
    dut.ADR_I.value = addr
    dut.WE_I.value  = 0
    dut.SEL_I.value = 0xF
    dut.STB_I.value = 1
    dut.CYC_I.value = 1
    for _ in range(20):
        await RisingEdge(dut.CLK_I)
        if int(dut.ACK_O.value) == 1:
            data = int(dut.DAT_O.value)
            dut.STB_I.value = 0
            dut.CYC_I.value = 0
            await RisingEdge(dut.CLK_I)
            return data
    raise TimeoutError(f"wb_read timeout at 0x{addr:02X}")


# ── Reset and compute helpers ────────────────────────────────────────────────

async def hw_reset(dut):
    """Assert RST_I for several cycles then deassert."""
    dut.STB_I.value = 0
    dut.CYC_I.value = 0
    dut.WE_I.value  = 0
    dut.ADR_I.value = 0
    dut.DAT_I.value = 0
    dut.SEL_I.value = 0xF
    dut.RST_I.value = 1
    await ClockCycles(dut.CLK_I, 8)
    dut.RST_I.value = 0
    await ClockCycles(dut.CLK_I, 4)


async def configure_crc(dut, model: CRCModel):
    """Write POLY, INIT, XOROUT, CFG registers from model parameters."""
    await wb_write(dut, REG_POLY,   model.polynomial & CRC_MASK)
    await wb_write(dut, REG_INIT,   model.init_val & CRC_MASK)
    await wb_write(dut, REG_XOROUT, model.final_xor & CRC_MASK)
    cfg_val = (int(model.reflect_out) << 1) | int(model.reflect_in)
    await wb_write(dut, REG_CFG, cfg_val)


async def start_crc(dut):
    """Write CTRL.start = 1."""
    await wb_write(dut, REG_CTRL, 0x1)


async def poll_done(dut, timeout=200):
    """Poll CTRL register until done bit (bit 2) is set."""
    for _ in range(timeout):
        ctrl = await wb_read(dut, REG_CTRL)
        if ctrl & 0x4:  # done bit
            return ctrl
    raise TimeoutError("CRC done timeout")


async def compute_crc_wb(dut, data: bytes, model: CRCModel):
    """Full CRC computation via Wishbone: configure, start, stream, poll, read."""
    await configure_crc(dut, model)
    await start_crc(dut)

    # Stream data bytes; last byte via DIN_LAST
    for i, b in enumerate(data):
        if i == len(data) - 1:
            await wb_write(dut, REG_DIN_LAST, b)
        else:
            await wb_write(dut, REG_DIN, b)

    await poll_done(dut)
    result = await wb_read(dut, REG_DOUT)
    return result & CRC_MASK


# ── Test cases ───────────────────────────────────────────────────────────────

@cocotb.test()
async def test_t01_version(dut):
    """T01: Read VERSION register (offset 0x0C) == 0x00010000."""
    cocotb.start_soon(Clock(dut.CLK_I, CLK_NS, units="ns").start())
    await hw_reset(dut)

    ver = await wb_read(dut, REG_VERSION)
    dut._log.info(f"[T01] VERSION = 0x{ver:08X}")
    assert ver == 0x00010000, f"VERSION mismatch: 0x{ver:08X} != 0x00010000"


@cocotb.test()
async def test_t02_info(dut):
    """T02: Read INFO register (offset 0x08) == {DATA_W, CRC_W}."""
    cocotb.start_soon(Clock(dut.CLK_I, CLK_NS, units="ns").start())
    await hw_reset(dut)

    info = await wb_read(dut, REG_INFO)
    expected = ((DATA_W & 0xFF) << 8) | (CRC_W & 0xFF)
    dut._log.info(f"[T02] INFO = 0x{info:08X} (expected 0x{expected:08X})")
    assert info == expected, f"INFO mismatch: 0x{info:08X} != 0x{expected:08X}"


@cocotb.test()
async def test_t03_crc32_check_string(dut):
    """T03: CRC-32 of '123456789' = 0xCBF43926."""
    cocotb.start_soon(Clock(dut.CLK_I, CLK_NS, units="ns").start())
    await hw_reset(dut)

    model = get_model()
    data = b"123456789"
    expected = model.compute(data)

    got = await compute_crc_wb(dut, data, model)
    dut._log.info(f"[T03] CRC-{CRC_W} of '123456789': "
                  f"0x{got:0{CRC_W//4}X} (expected 0x{expected:0{CRC_W//4}X})")
    assert got == expected, (f"CRC mismatch: 0x{got:0{CRC_W//4}X} "
                             f"!= 0x{expected:0{CRC_W//4}X}")


@cocotb.test()
async def test_t04_single_byte_zero(dut):
    """T04: CRC-32 of single byte 0x00."""
    cocotb.start_soon(Clock(dut.CLK_I, CLK_NS, units="ns").start())
    await hw_reset(dut)

    model = get_model()
    data = b"\x00"
    expected = model.compute(data)

    got = await compute_crc_wb(dut, data, model)
    dut._log.info(f"[T04] CRC-{CRC_W} of 0x00: "
                  f"0x{got:0{CRC_W//4}X} (expected 0x{expected:0{CRC_W//4}X})")
    assert got == expected, (f"CRC mismatch: 0x{got:0{CRC_W//4}X} "
                             f"!= 0x{expected:0{CRC_W//4}X}")


@cocotb.test()
async def test_t05_back_to_back(dut):
    """T05: Two consecutive CRC computations without external reset."""
    cocotb.start_soon(Clock(dut.CLK_I, CLK_NS, units="ns").start())
    await hw_reset(dut)

    model = get_model()
    data = b"123456789"
    expected = model.compute(data)

    got1 = await compute_crc_wb(dut, data, model)
    # Second computation immediately after (no hw_reset)
    got2 = await compute_crc_wb(dut, data, model)

    dut._log.info(f"[T05] Back-to-back: "
                  f"0x{got1:0{CRC_W//4}X}, 0x{got2:0{CRC_W//4}X} "
                  f"(expected 0x{expected:0{CRC_W//4}X})")
    assert got1 == expected, f"First CRC mismatch: 0x{got1:X}"
    assert got2 == expected, f"Second CRC mismatch: 0x{got2:X}"


@cocotb.test()
async def test_t06_irq_pulse(dut):
    """T06: IRQ output pulses high for one cycle when CRC computation completes."""
    cocotb.start_soon(Clock(dut.CLK_I, CLK_NS, units="ns").start())
    await hw_reset(dut)

    model = get_model()

    # Configure and start
    await configure_crc(dut, model)
    await start_crc(dut)

    # Send a single byte as DIN_LAST
    await wb_write(dut, REG_DIN_LAST, 0x55)

    # Monitor IRQ: wait until irq goes high, then verify it goes low next cycle
    irq_seen = False
    irq_high_cycles = 0
    for _ in range(100):
        await RisingEdge(dut.CLK_I)
        if int(dut.irq.value) == 1:
            irq_seen = True
            irq_high_cycles += 1
        elif irq_seen:
            # IRQ went low after being high -- done
            break

    dut._log.info(f"[T06] IRQ seen={irq_seen}, high_cycles={irq_high_cycles}")
    assert irq_seen, "IRQ never asserted"
    assert irq_high_cycles == 1, (f"IRQ should pulse for exactly 1 cycle, "
                                  f"was high for {irq_high_cycles}")
