# CRC Engine IP Core

> **Lumees Lab** — FPGA-Verified, Production-Ready Silicon IP

[![License](https://img.shields.io/badge/License-Source_Available-orange.svg)](LICENSE)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--100T-green.svg)]()
[![Fmax](https://img.shields.io/badge/Fmax-100%20MHz-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-11%2F11%20HW%20PASS-blue.svg)]()

---

## Overview

The Lumees Lab CRC IP Core is a parameterizable Cyclic Redundancy Check engine supporting CRC-8, CRC-16, CRC-32, and CRC-64 widths with **runtime-configurable polynomial, initial value, final XOR, and input/output reflection**. A single core handles any standard CRC algorithm — from CRC-32/Ethernet to CRC-16/CCITT to CRC-8/AUTOSAR — by writing configuration registers before computation.

The engine processes one data byte per clock cycle using a combinational XOR matrix (MSB-first bit processing, DATA_W iterations unrolled). At 100 MHz with DATA_W=8, this yields 800 Mbit/s throughput in just 212 LUTs and 210 FFs — zero DSP, zero BRAM.

Verified against published CRC check values ("123456789" → 0xCBF43926 for CRC-32, 0x29B1 for CRC-16, 0xDF for CRC-8) and the Ethernet FCS magic residue (0x2144DF1C). 21/21 cocotb tests across three widths and **11/11 UART hardware regression tests** on Arty A7-100T.

---

## Key Features

| Feature | Detail |
|---|---|
| **CRC Widths** | 8, 16, 32 (compile-time via `CRC_W`); 64 supported by model |
| **Data Width** | 8 bits default (compile-time via `DATA_W`) |
| **Polynomial** | Runtime-configurable (any polynomial up to CRC_W bits) |
| **Init Value** | Runtime-configurable |
| **Final XOR** | Runtime-configurable |
| **Reflection** | Independent input and output reflection flags |
| **Presets** | CRC-32/Ethernet, CRC-16/CCITT, CRC-8/AUTOSAR (in package) |
| **Throughput** | 1 byte/clock = 800 Mbit/s @ 100 MHz (DATA_W=8) |
| **Architecture** | Combinational XOR matrix (MSB-first, DATA_W iterations unrolled) |
| **Bus Interfaces** | AXI4-Lite, Wishbone B4, AXI4-Stream (with packet FIFO) |
| **Technology** | FPGA / ASIC, pure synchronous RTL, no vendor primitives |

---

## Performance — Arty A7-100T (XC7A100T) @ 100 MHz

| Resource | Core (CRC-32) | Full SoC | Available |
|---|---|---|---|
| LUT | 212 | 622 | 63,400 |
| FF | 210 | 856 | 126,800 |
| DSP48 | 0 | 0 | 240 |
| Block RAM | 0 | 0 | 135 |

> **Timing:** WNS = +1.195 ns @ 100 MHz. Core utilization: 0.33% LUTs. Pure LUT/FF — zero DSP/BRAM.

---

## Architecture

```
           ┌───────────────────────────────────────────────┐
           │                   crc_top                      │
           │                                                 │
  s_data ──►│  Config latch    ┌────────────────────────┐    │
  s_valid ──►│  (poly, init,   │      crc_core           │    │
  s_last  ──►│   xor, refl)   │                          │    │
  s_cfg   ──►│                 │  crc_reg ← crc_step()   │    │
  start   ──►│  FSM: IDLE →   │  (XOR matrix, 1 byte/   │──► crc_o
             │  RUN → FINAL   │   cycle, combinational)  │    done_o
             │  → DONE        │  + reflect_out + xorout  │    │
             │                 └────────────────────────┘    │
             │  Latency: N+2 cycles (N data bytes + 2)      │
             └───────────────────────────────────────────────┘
```

**crc_step() function:** Processes DATA_W bits combinationally: for each bit, XOR with polynomial if MSB ⊕ data_bit = 1, then shift left. This is the standard CRC unrolled inner loop.

**Reflection:** `reflect_in` bit-reverses each input byte before XOR. `reflect_out` bit-reverses the final CRC before applying `final_xor`. Both are independently controllable per computation.

---

## Supported CRC Standards

| Standard | Width | Polynomial | Init | XOR Out | Ref In | Ref Out | Check |
|---|---|---|---|---|---|---|---|
| CRC-32/Ethernet | 32 | 0x04C11DB7 | 0xFFFFFFFF | 0xFFFFFFFF | Yes | Yes | 0xCBF43926 |
| CRC-16/CCITT | 16 | 0x1021 | 0xFFFF | 0x0000 | No | No | 0x29B1 |
| CRC-8/AUTOSAR | 8 | 0x2F | 0xFF | 0xFF | No | No | 0xDF |

Check values are for the ASCII string "123456789".

---

## Interface — Bare Core (`crc_top`)

```systemverilog
crc_top #(
  .CRC_W  (32),        // CRC width (8, 16, 32)
  .DATA_W (8)          // Input data width
) u_crc (
  .clk          (clk),
  .rst_n        (rst_n),
  // Configuration (latched on start_i)
  .s_cfg        (cfg),          // {polynomial, init_val, final_xor, reflect_in, reflect_out}
  // Control
  .start_i      (start),        // Pulse: begin new CRC computation
  .s_data       (data_byte),    // [DATA_W-1:0] Input data
  .s_data_valid (data_valid),   // Data byte valid
  .s_last       (last_byte),    // Last byte of message
  // Output
  .busy_o       (busy),
  .done_o       (done),         // Pulse: CRC ready
  .crc_o        (crc_result),   // [CRC_W-1:0] Computed CRC
  .version_o    (version)
);
```

---

## Register Map — AXI4-Lite / Wishbone

| Offset | Register | Access | Description |
|---|---|---|---|
| 0x00 | CTRL | R/W | `[0]`=START(W,self-clear) `[1]`=BUSY(RO) `[2]`=DONE(RO) |
| 0x04 | STATUS | RO | `[0]`=reflect_in_latched `[1]`=reflect_out_latched |
| 0x08 | INFO | RO | `[7:0]`=CRC_W `[15:8]`=DATA_W |
| 0x0C | VERSION | RO | `0x00010000` |
| 0x10 | POLY | R/W | Polynomial (CRC_W bits) |
| 0x14 | INIT | R/W | Initial CRC value |
| 0x18 | XOROUT | R/W | Final XOR value |
| 0x1C | CFG | R/W | `[0]`=reflect_in `[1]`=reflect_out |
| 0x20 | DIN | W | Data byte (write triggers s_data_valid) |
| 0x24 | DIN_LAST | W | Last data byte (write triggers s_data_valid + s_last) |
| 0x28 | DOUT | RO | CRC result (valid after DONE) |

---

## Verification

### Simulation (cocotb + Verilator) — 21/21 PASS

| Test | CRC-32 | CRC-16 | CRC-8 |
|---|---|---|---|
| T01: "123456789" check string | 0xCBF43926 | 0x29B1 | 0xDF |
| T02: Single byte 0x00 | ✓ | ✓ | ✓ |
| T03: All-0xFF (4 bytes) | ✓ | ✓ | ✓ |
| T04: Back-to-back | ✓ | ✓ | ✓ |
| T05: Long message (256 bytes) | ✓ | ✓ | ✓ |
| T06: Random sweep (20 msgs) | ✓ | ✓ | ✓ |
| T07: Version register | ✓ | ✓ | ✓ |

### FPGA Hardware — 11/11 PASS

Arty A7-100T @ 100 MHz. Includes Ethernet FCS magic residue test (0x2144DF1C).

---

## Directory Structure

```
crc/
├── rtl/                       # 6 files, 967 lines
│   ├── crc_pkg.sv             # crc_step(), reflect, presets (CRC-32/16/8)
│   ├── crc_core.sv            # XOR matrix datapath
│   ├── crc_top.sv             # FSM wrapper (IDLE→RUN→FINAL→DONE)
│   ├── crc_axil.sv            # AXI4-Lite slave
│   ├── crc_wb.sv              # Wishbone B4 slave
│   └── crc_axis.sv            # AXI4-Stream with packet FIFO
├── model/
│   └── crc_model.py           # Python golden model (6 self-tests)
├── tb/
│   ├── directed/              # cocotb tests (21/21 PASS across 3 widths)
│   │   ├── test_crc_top.py
│   │   ├── test_crc_axil.py
│   │   └── test_crc_wb.py
│   └── uvm/                   # UVM environment (11 files, 1,587 lines)
├── sim/
│   └── Makefile.cocotb
├── litex/                     # LiteX SoC for Arty A7-100T
│   ├── crc_litex.py
│   ├── crc_soc.py
│   └── crc_uart_test.py
├── README.md
├── LICENSE
└── .gitignore
```

---

## Roadmap

### v1.1
- [ ] CRC-64 FPGA validation (currently model-only)
- [ ] Multi-byte processing (DATA_W=16/32 for higher throughput)
- [ ] Interrupt-driven AXI4-Lite operation

### v1.2
- [ ] Hardware CRC lookup table (trade LUTs for speed)
- [ ] Streaming mode (no start/done — continuous CRC update)

### v2.0
- [ ] SkyWater 130nm silicon-proven version

---

## Why Lumees CRC?

| Differentiator | Detail |
|---|---|
| **Runtime-configurable** | Any polynomial, init, XOR, reflection — one core, all standards |
| **212 LUTs** | Smallest footprint in the Lumees library |
| **Zero DSP/BRAM** | Pure combinational XOR matrix |
| **Three bus interfaces** | AXI4-Lite, Wishbone B4, AXI4-Stream |
| **21/21 sim tests** | Three widths × seven vectors including canonical check values |
| **Ethernet FCS verified** | Magic residue 0x2144DF1C proven on hardware |
| **Source-available** | Full RTL — inspect the XOR matrix |

---

## License

**Dual license:** Free for non-commercial use (Apache 2.0). Commercial use requires a Lumees Lab license.

See [LICENSE](LICENSE) for full terms.

---

**Lumees Lab** · Hasan Kurşun · [lumeeslab.com](https://lumeeslab.com) · info@lumeeslab.com

*Copyright © 2026 Lumees Lab. All rights reserved.*
