#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
CRC SoC for Arty A7-100T
=========================
Builds a LiteX SoC with:
  - No CPU (UARTBone for register access)
  - UART at 115200 baud
  - CRC IP (CRC_W=32, DATA_W=8)
  - LED0 = busy, LED1 = done/irq

Usage:
    python3 crc_soc.py --build
    python3 crc_soc.py --load
"""

import argparse
import os
import sys

# ── LiteX CSR monkey-patch for Python 3.12 compatibility ─────────────────────
import itertools as _it
_csr_counter = _it.count()
import litex.soc.interconnect.csr as _litex_csr
_CSRBase_orig_init = _litex_csr._CSRBase.__init__
def _CSRBase_patched_init(self, size, name, n=None):
    from migen.fhdl.tracer import get_obj_var_name
    try:
        resolved = get_obj_var_name(name)
    except Exception:
        resolved = None
    if resolved is None:
        resolved = name if name is not None else f"_csr_{next(_csr_counter)}"
    from migen import DUID
    DUID.__init__(self)
    self.n     = n
    self.fixed = n is not None
    self.size  = size
    self.name  = resolved
_litex_csr._CSRBase.__init__ = _CSRBase_patched_init

from migen import *

from litex.soc.cores.clock            import S7PLL
from litex.soc.integration.soc_core   import SoCCore, soc_core_argdict, soc_core_args
from litex.soc.integration.builder    import Builder, builder_argdict, builder_args
from litex.soc.interconnect.csr       import *
from litex.soc.cores.gpio             import GPIOOut

from litex_boards.platforms import digilent_arty

sys.path.insert(0, os.path.dirname(__file__))
from crc_litex import CRC

# ── Parameters ───────────────────────────────────────────────────────────────
CRC_W  = 32
DATA_W = 8


# ── Clock / Reset ────────────────────────────────────────────────────────────
class _CRG(Module):
    def __init__(self, platform, sys_clk_freq):
        self.clock_domains.cd_sys = ClockDomain("sys")

        self.submodules.pll = pll = S7PLL(speedgrade=-1)
        pll.register_clkin(platform.request("clk100"), 100e6)
        pll.create_clkout(self.cd_sys, sys_clk_freq)

        platform.add_false_path_constraints(self.cd_sys.clk)


# ── CRC SoC ──────────────────────────────────────────────────────────────────
class CRCSoC(SoCCore):
    def __init__(self, sys_clk_freq: float = 100e6, **kwargs):
        platform = digilent_arty.Platform(variant="a7-100")

        kwargs["cpu_type"]             = None
        kwargs["uart_name"]            = "uartbone"
        kwargs["integrated_rom_size"]  = 0
        kwargs["integrated_sram_size"] = 0
        SoCCore.__init__(self, platform,
            clk_freq = sys_clk_freq,
            ident    = "CRC IP Test SoC - Arty A7-100T",
            **kwargs
        )

        # ── CRG ──────────────────────────────────────────────────────────
        self.submodules.crg = _CRG(platform, sys_clk_freq)

        # ── CRC IP ───────────────────────────────────────────────────────
        self.submodules.crc = CRC(platform, crc_w=CRC_W, data_w=DATA_W)
        self.add_csr("crc")

        # ── LEDs ─────────────────────────────────────────────────────────
        leds = platform.request_all("user_led")
        self.submodules.leds = GPIOOut(leds)
        self.add_csr("leds")
        self.comb += [
            leds[0].eq(self.crc.status.status[2]),  # busy
            leds[1].eq(self.crc.irq),                # done/irq
        ]


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="CRC SoC on Arty A7-100T")
    builder_args(parser)
    soc_core_args(parser)
    parser.add_argument("--build", action="store_true", help="Build bitstream")
    parser.add_argument("--load",  action="store_true", help="Load bitstream via JTAG")
    args = parser.parse_args()

    soc = CRCSoC(**soc_core_argdict(args))
    builder = Builder(soc, **builder_argdict(args))
    builder.build(run=args.build)

    if args.load:
        prog = soc.platform.create_programmer()
        prog.load_bitstream(
            os.path.join(builder.gateware_dir, soc.build_name + ".bit")
        )


if __name__ == "__main__":
    main()
