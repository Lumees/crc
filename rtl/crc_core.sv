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
// CRC IP — Core datapath
// =============================================================================
// Byte-at-a-time CRC engine using a combinational XOR matrix.
// Processes one DATA_W-bit chunk per clock cycle.
// No DSP, no BRAM — pure LUT logic.
// =============================================================================

`timescale 1ns/1ps

import crc_pkg::*;

module crc_core (
  input  logic                clk,
  input  logic                rst_n,

  // Configuration (must be stable from init through finalize)
  input  crc_config_t         cfg,

  // Control
  input  logic                init,         // pulse: load cfg.init_val
  input  logic                data_valid,   // new chunk available
  input  logic [DATA_W-1:0]  data_in,      // input data chunk
  input  logic                finalize,     // pulse: apply reflect_out + final_xor

  // Output
  output logic [CRC_W-1:0]   crc_out,      // final or running CRC
  output logic                crc_valid     // pulses one cycle after finalize
);

  logic [CRC_W-1:0] crc_reg;

  // Combinational: optionally reflect input data
  logic [DATA_W-1:0] data_reflected;
  always_comb
    data_reflected = cfg.reflect_in ? reflect_data(data_in) : data_in;

  // Combinational: next CRC state
  logic [CRC_W-1:0] crc_next;
  always_comb
    crc_next = crc_step(crc_reg, data_reflected, cfg.polynomial);

  // Combinational: finalized CRC
  logic [CRC_W-1:0] crc_final;
  always_comb begin
    crc_final = cfg.reflect_out ? reflect_crc(crc_reg) : crc_reg;
    crc_final = crc_final ^ cfg.final_xor;
  end

  // Sequential
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_reg   <= '0;
      crc_out   <= '0;
      crc_valid <= 1'b0;
    end else begin
      crc_valid <= 1'b0;

      if (init)
        crc_reg <= cfg.init_val;
      else if (data_valid)
        crc_reg <= crc_next;

      if (finalize) begin
        crc_out   <= crc_final;
        crc_valid <= 1'b1;
      end
    end
  end

endmodule : crc_core
