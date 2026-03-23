# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC IP — Directed cocotb tests for crc_axil (AXI4-Lite wrapper)
=================================================================
Tests register reads, CRC-32 computations via AXI4-Lite, and IRQ.

Register map:
  0x00 CTRL      [0]=start [1]=busy(RO) [2]=done(RO)
  0x04 STATUS    RO  [0]=reflect_in_lat [1]=reflect_out_lat
  0x08 INFO      RO  [15:8]=DATA_W [7:0]=CRC_W
  0x0C VERSION   RO  IP_VERSION (0x00010000)
  0x10 POLY      R/W polynomial
  0x14 INIT      R/W init value
  0x18 XOROUT    R/W final XOR
  0x1C CFG       R/W [0]=reflect_in [1]=reflect_out
  0x20 DIN       W   data byte (triggers s_data_valid)
  0x24 DIN_LAST  W   data byte + s_last
  0x28 DOUT      RO  CRC result
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../model'))
from crc_model import CRCModel, crc32_iso_hdlc, crc16_ccitt, crc8_autosar

CRC_W  = int(os.environ.get("CRC_W", "32"))
DATA_W = int(os.environ.get("DATA_W", "8"))
CLK_NS = 10

# Register offsets
REG_CTRL    = 0x00
REG_STATUS  = 0x04
REG_INFO    = 0x08
REG_VERSION = 0x0C
REG_POLY    = 0x10
REG_INIT    = 0x14
REG_XOROUT  = 0x18
REG_CFG     = 0x1C
REG_DIN     = 0x20
REG_DIN_LAST = 0x24
REG_DOUT    = 0x28


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


# ---------------------------------------------------------------------------
# AXI4-Lite bus helpers
# ---------------------------------------------------------------------------
async def axil_write(dut, addr, data):
    """Single AXI4-Lite write transaction."""
    dut.s_axil_awaddr.value  = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = data & 0xFFFFFFFF
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_wvalid.value  = 1
    dut.s_axil_bready.value  = 1

    # Wait for AW+W handshake
    while True:
        await RisingEdge(dut.clk)
        aw_done = int(dut.s_axil_awready.value) == 1
        w_done  = int(dut.s_axil_wready.value)  == 1
        if aw_done:
            dut.s_axil_awvalid.value = 0
        if w_done:
            dut.s_axil_wvalid.value = 0
        if aw_done and w_done:
            break

    # Wait for B response
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_bvalid.value) == 1:
            dut.s_axil_bready.value = 0
            return
    raise TimeoutError(f"axil_write timeout at addr=0x{addr:02X}")


async def axil_read(dut, addr) -> int:
    """Single AXI4-Lite read transaction, returns 32-bit data."""
    dut.s_axil_araddr.value  = addr
    dut.s_axil_arvalid.value = 1
    dut.s_axil_rready.value  = 1

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            dut.s_axil_arvalid.value = 0
            break
    else:
        raise TimeoutError(f"axil_read AR timeout at addr=0x{addr:02X}")

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            data = int(dut.s_axil_rdata.value)
            dut.s_axil_rready.value = 0
            return data
    raise TimeoutError(f"axil_read R timeout at addr=0x{addr:02X}")


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------
async def hw_reset(dut):
    """Assert reset and initialize all AXI4-Lite inputs to idle."""
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    dut.s_axil_bready.value  = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value  = 0
    dut.s_axil_awaddr.value  = 0
    dut.s_axil_wdata.value   = 0
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_araddr.value  = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 8)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


# ---------------------------------------------------------------------------
# CRC computation helper via AXI4-Lite
# ---------------------------------------------------------------------------
async def crc_compute(dut, data: bytes, model: CRCModel, timeout=200):
    """Configure CRC engine, stream data, poll done, return DOUT."""
    crc_mask = (1 << CRC_W) - 1

    # Write configuration registers
    await axil_write(dut, REG_POLY,   model.polynomial & crc_mask)
    await axil_write(dut, REG_INIT,   model.init_val & crc_mask)
    await axil_write(dut, REG_XOROUT, model.final_xor & crc_mask)
    cfg_val = (int(model.reflect_in) & 1) | ((int(model.reflect_out) & 1) << 1)
    await axil_write(dut, REG_CFG, cfg_val)

    # Start
    await axil_write(dut, REG_CTRL, 0x01)

    # Stream data bytes
    for i, b in enumerate(data):
        if i == len(data) - 1:
            await axil_write(dut, REG_DIN_LAST, b)
        else:
            await axil_write(dut, REG_DIN, b)

    # Poll done bit (CTRL[2])
    for _ in range(timeout):
        ctrl_val = await axil_read(dut, REG_CTRL)
        if ctrl_val & 0x04:
            break
    else:
        raise TimeoutError("CRC done timeout")

    # Read result
    result = await axil_read(dut, REG_DOUT)
    return result & crc_mask


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_t01_version(dut):
    """T01: Read VERSION register (offset 0x0C) == 0x00010000."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    ver = await axil_read(dut, REG_VERSION)
    dut._log.info(f"[T01] VERSION = 0x{ver:08X}")
    assert ver == 0x00010000, f"VERSION mismatch: 0x{ver:08X} != 0x00010000"


@cocotb.test()
async def test_t02_info(dut):
    """T02: Read INFO register (offset 0x08) == {DATA_W, CRC_W} packed."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    info = await axil_read(dut, REG_INFO)
    expected = ((DATA_W & 0xFF) << 8) | (CRC_W & 0xFF)
    dut._log.info(f"[T02] INFO = 0x{info:08X} (expected 0x{expected:08X})")
    assert info == expected, f"INFO mismatch: 0x{info:08X} != 0x{expected:08X}"


@cocotb.test()
async def test_t03_crc32_check_string(dut):
    """T03: CRC-32 of '123456789' == 0xCBF43926 via AXI4-Lite."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    model = get_model()
    data = b"123456789"
    expected = model.compute(data)

    got = await crc_compute(dut, data, model)
    dut._log.info(f"[T03] CRC-{CRC_W} of '123456789': 0x{got:0{CRC_W//4}X} "
                  f"(expected 0x{expected:0{CRC_W//4}X})")
    assert got == expected, (f"CRC mismatch: 0x{got:0{CRC_W//4}X} "
                             f"!= 0x{expected:0{CRC_W//4}X}")


@cocotb.test()
async def test_t04_single_byte_zero(dut):
    """T04: CRC-32 of single byte 0x00 == 0xD202EF8D."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    model = get_model()
    data = b"\x00"
    expected = model.compute(data)

    got = await crc_compute(dut, data, model)
    dut._log.info(f"[T04] CRC-{CRC_W} of 0x00: 0x{got:0{CRC_W//4}X} "
                  f"(expected 0x{expected:0{CRC_W//4}X})")
    assert got == expected, (f"CRC mismatch: 0x{got:0{CRC_W//4}X} "
                             f"!= 0x{expected:0{CRC_W//4}X}")


@cocotb.test()
async def test_t05_back_to_back(dut):
    """T05: Two consecutive CRC computations without external reset."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    model = get_model()

    # First computation: "123456789"
    data1 = b"123456789"
    expected1 = model.compute(data1)
    got1 = await crc_compute(dut, data1, model)

    # Small gap
    await ClockCycles(dut.clk, 4)

    # Second computation: single 0xFF byte
    data2 = b"\xFF"
    expected2 = model.compute(data2)
    got2 = await crc_compute(dut, data2, model)

    dut._log.info(f"[T05] Back-to-back #1: 0x{got1:0{CRC_W//4}X} "
                  f"(expected 0x{expected1:0{CRC_W//4}X})")
    dut._log.info(f"[T05] Back-to-back #2: 0x{got2:0{CRC_W//4}X} "
                  f"(expected 0x{expected2:0{CRC_W//4}X})")
    assert got1 == expected1, (f"First CRC mismatch: 0x{got1:0{CRC_W//4}X} "
                               f"!= 0x{expected1:0{CRC_W//4}X}")
    assert got2 == expected2, (f"Second CRC mismatch: 0x{got2:0{CRC_W//4}X} "
                               f"!= 0x{expected2:0{CRC_W//4}X}")


@cocotb.test()
async def test_t06_irq(dut):
    """T06: IRQ pulse fires on done."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    model = get_model()
    crc_mask = (1 << CRC_W) - 1

    # Configure
    await axil_write(dut, REG_POLY,   model.polynomial & crc_mask)
    await axil_write(dut, REG_INIT,   model.init_val & crc_mask)
    await axil_write(dut, REG_XOROUT, model.final_xor & crc_mask)
    cfg_val = (int(model.reflect_in) & 1) | ((int(model.reflect_out) & 1) << 1)
    await axil_write(dut, REG_CFG, cfg_val)

    # Start
    await axil_write(dut, REG_CTRL, 0x01)

    # Send single byte via DIN_LAST
    await axil_write(dut, REG_DIN_LAST, 0xAB)

    # Monitor IRQ: wait for it to pulse high
    irq_seen = False
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.irq.value) == 1:
            irq_seen = True
            break

    dut._log.info(f"[T06] IRQ pulse detected: {irq_seen}")
    assert irq_seen, "IRQ pulse was never asserted"

    # Verify IRQ is single-cycle (should be low on next clock)
    await RisingEdge(dut.clk)
    irq_after = int(dut.irq.value)
    dut._log.info(f"[T06] IRQ after one cycle: {irq_after}")
    assert irq_after == 0, "IRQ was not a single-cycle pulse"
