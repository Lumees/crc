// =============================================================================
// Copyright (c) 2026 Lumees Lab / Hasan Kurşun
// SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
//
// Licensed under the Apache License 2.0 with Commons Clause restriction.
// You may use this file freely for non-commercial purposes (academic,
// research, hobby, education, personal projects).
//
// COMMERCIAL USE requires a separate license from Lumees Lab.
// Contact: info@lumeeslab.com · https://lumeeslab.com
// =============================================================================
// CRC IP — Package: types, parameters, combinational XOR step function
// =============================================================================

`timescale 1ns/1ps

package crc_pkg;

  // ── Compile-time width selection ──────────────────────────────────────────
`ifdef CRC_PKG_CRC_W
  localparam int CRC_W  = `CRC_PKG_CRC_W;
`else
  localparam int CRC_W  = 32;
`endif

`ifdef CRC_PKG_DATA_W
  localparam int DATA_W = `CRC_PKG_DATA_W;
`else
  localparam int DATA_W = 8;
`endif

  localparam int IP_VERSION = 32'h0001_0000;

  // ── Configuration struct ──────────────────────────────────────────────────
  typedef struct packed {
    logic [CRC_W-1:0] polynomial;
    logic [CRC_W-1:0] init_val;
    logic [CRC_W-1:0] final_xor;
    logic              reflect_in;
    logic              reflect_out;
  } crc_config_t;

  // ── Bit reflection (pure wiring) ──────────────────────────────────────────
  function automatic logic [CRC_W-1:0] reflect_crc(input logic [CRC_W-1:0] d);
    for (int i = 0; i < CRC_W; i++)
      reflect_crc[i] = d[CRC_W-1-i];
  endfunction

  function automatic logic [DATA_W-1:0] reflect_data(input logic [DATA_W-1:0] d);
    for (int i = 0; i < DATA_W; i++)
      reflect_data[i] = d[DATA_W-1-i];
  endfunction

  // ── Single-step CRC computation (DATA_W bits at a time) ──────────────────
  // MSB-first bit processing, unrolled for DATA_W iterations.
  // The caller is responsible for reflecting data_in if reflect_in is set.
  function automatic logic [CRC_W-1:0] crc_step(
    input logic [CRC_W-1:0]  crc_in,
    input logic [DATA_W-1:0] data_in,
    input logic [CRC_W-1:0]  poly
  );
    logic [CRC_W-1:0] c;
    c = crc_in;
    for (int i = DATA_W-1; i >= 0; i--) begin
      if (c[CRC_W-1] ^ data_in[i])
        c = (c << 1) ^ poly;
      else
        c = c << 1;
    end
    return c;
  endfunction

  // ── Preset configurations ─────────────────────────────────────────────────

  // CRC-32/ISO-HDLC (Ethernet)
  function automatic crc_config_t preset_crc32_ethernet();
    crc_config_t cfg;
    cfg.polynomial  = CRC_W'(32'h04C11DB7);
    cfg.init_val    = CRC_W'({CRC_W{1'b1}});
    cfg.final_xor   = CRC_W'({CRC_W{1'b1}});
    cfg.reflect_in  = 1'b1;
    cfg.reflect_out = 1'b1;
    return cfg;
  endfunction

  // CRC-16/CCITT-FALSE
  function automatic crc_config_t preset_crc16_ccitt();
    crc_config_t cfg;
    cfg.polynomial  = CRC_W'(16'h1021);
    cfg.init_val    = CRC_W'(16'hFFFF);
    cfg.final_xor   = '0;
    cfg.reflect_in  = 1'b0;
    cfg.reflect_out = 1'b0;
    return cfg;
  endfunction

  // CRC-8/AUTOSAR
  function automatic crc_config_t preset_crc8_autosar();
    crc_config_t cfg;
    cfg.polynomial  = CRC_W'(8'h2F);
    cfg.init_val    = CRC_W'(8'hFF);
    cfg.final_xor   = CRC_W'(8'hFF);
    cfg.reflect_in  = 1'b0;
    cfg.reflect_out = 1'b0;
    return cfg;
  endfunction

endpackage : crc_pkg
