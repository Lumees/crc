# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC LiteX Module
=================
Directly instantiates crc_top.sv and wires it to LiteX CSR registers.

CSR registers:
  ctrl        [0]=start(self-clearing) [1]=busy(RO) [2]=done(RO)
  poly        Polynomial (CRC_W bits, zero-extended to 32)
  init_val    Init value
  xor_out     Final XOR
  cfg         [0]=reflect_in [1]=reflect_out
  data_in     Write triggers s_data_valid (lower DATA_W bits)
  data_last   Write triggers s_data_valid + s_last
  crc_out     CRC result (RO)
  info        [7:0]=CRC_W [15:8]=DATA_W (RO)
  version     IP version (RO)
"""

from migen import *
from litex.soc.interconnect.csr import *

import os

CRC_RTL_DIR = os.path.join(os.path.dirname(__file__), '../rtl')


class CRC(Module, AutoCSR):
    def __init__(self, platform, crc_w=32, data_w=8):
        # ── Platform sources ─────────────────────────────────────────────
        for f in ['crc_pkg.sv', 'crc_core.sv', 'crc_top.sv']:
            platform.add_source(os.path.join(CRC_RTL_DIR, f))

        # ── CSR registers (RW) ───────────────────────────────────────────
        self.ctrl     = CSRStorage(8,  name="ctrl",
                                   description="[0]=start(self-clear)")
        self.poly     = CSRStorage(32, name="poly",
                                   description="CRC polynomial")
        self.init_val = CSRStorage(32, name="init_val",
                                   description="CRC init value")
        self.xor_out  = CSRStorage(32, name="xor_out",
                                   description="Final XOR value")
        self.cfg      = CSRStorage(8,  name="cfg",
                                   description="[0]=reflect_in [1]=reflect_out")
        self.data_in  = CSRStorage(9,  name="data_in",
                                   description="[7:0]=data, write triggers valid")
        self.data_last = CSRStorage(9, name="data_last",
                                   description="[7:0]=data, write triggers valid+last")

        # ── CSR registers (RO) ───────────────────────────────────────────
        self.crc_out = CSRStatus(32, name="crc_out", description="CRC result")
        self.status  = CSRStatus(8,  name="status",
                                 description="[0]=ready [1]=done [2]=busy")
        self.info    = CSRStatus(32, name="info",
                                 description="[7:0]=CRC_W [15:8]=DATA_W")
        self.version = CSRStatus(32, name="version", description="IP version")

        # ── Constant outputs ─────────────────────────────────────────────
        self.comb += [
            self.info.status.eq((data_w << 8) | crc_w),
        ]

        # ── Core signals ─────────────────────────────────────────────────
        start_pulse = Signal()
        data_valid  = Signal()
        data_last_s = Signal()
        busy_sig    = Signal()
        done_sig    = Signal()
        crc_result  = Signal(crc_w)
        version_sig = Signal(32)

        # Build s_cfg packed: {polynomial, init_val, final_xor, reflect_in, reflect_out}
        # Total width = CRC_W*3 + 2
        CFG_W = crc_w * 3 + 2
        s_cfg = Signal(CFG_W)
        self.comb += s_cfg.eq(
            Cat(
                self.cfg.storage[1],          # reflect_out (bit 0 of packed)
                self.cfg.storage[0],          # reflect_in  (bit 1 of packed)
                self.xor_out.storage[:crc_w], # final_xor
                self.init_val.storage[:crc_w],# init_val
                self.poly.storage[:crc_w],    # polynomial (MSB of packed)
            )
        )

        # Start pulse: fires when ctrl register is written with bit[0]=1
        self.comb += start_pulse.eq(self.ctrl.re & self.ctrl.storage[0])

        # Data valid: fires when data_in or data_last register is written
        self.comb += [
            data_valid.eq(self.data_in.re | self.data_last.re),
            data_last_s.eq(self.data_last.re),
        ]

        # Status
        self.comb += [
            self.status.status[0].eq(~busy_sig),    # ready
            self.status.status[1].eq(done_sig),      # done
            self.status.status[2].eq(busy_sig),      # busy
        ]

        # Latch CRC result
        crc_latched = Signal(32)
        self.sync += If(done_sig, crc_latched.eq(crc_result))
        self.comb += self.crc_out.status.eq(crc_latched)

        # IRQ on done
        self.irq = Signal()
        done_prev = Signal()
        self.sync += done_prev.eq(done_sig)
        self.comb += self.irq.eq(done_sig & ~done_prev)

        # ── CRC top instance ─────────────────────────────────────────────
        data_mux = Signal(data_w)
        self.comb += If(self.data_last.re,
            data_mux.eq(self.data_last.storage[:data_w]),
        ).Else(
            data_mux.eq(self.data_in.storage[:data_w]),
        )

        self.specials += Instance("crc_top",
            i_clk          = ClockSignal(),
            i_rst_n        = ~ResetSignal(),
            i_s_cfg        = s_cfg,
            i_start_i      = start_pulse,
            o_busy_o       = busy_sig,
            o_done_o       = done_sig,
            i_s_data_valid = data_valid,
            i_s_data       = data_mux,
            i_s_last       = data_last_s,
            o_crc_o        = crc_result,
            o_version_o    = version_sig,
        )

        self.comb += self.version.status.eq(version_sig)
