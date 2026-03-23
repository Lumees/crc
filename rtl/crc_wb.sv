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
// CRC IP — Wishbone B4 Classic Interface Wrapper
// =============================================================================
// Same register map as crc_axil.sv.
//
//  Offset  Name      Access  Description
//  0x00    CTRL      RW      [0]=start(W,self-clear) [1]=busy(RO) [2]=done(RO)
//  0x04    STATUS    RO      [0]=reflect_in_lat [1]=reflect_out_lat
//  0x08    INFO      RO      [7:0]=CRC_W [15:8]=DATA_W
//  0x0C    VERSION   RO      IP_VERSION
//  0x10    POLY      RW      Polynomial [CRC_W-1:0]
//  0x14    INIT      RW      Init value
//  0x18    XOROUT    RW      Final XOR
//  0x1C    CFG       RW      [0]=reflect_in [1]=reflect_out
//  0x20    DIN       W       Data input (triggers s_data_valid)
//  0x24    DIN_LAST  W       Data input + s_last
//  0x28    DOUT      RO      CRC result [CRC_W-1:0]
// =============================================================================

`timescale 1ns/1ps

import crc_pkg::*;

module crc_wb (
  // Wishbone system
  input  logic        CLK_I,
  input  logic        RST_I,

  // Wishbone slave
  input  logic [31:0] ADR_I,
  input  logic [31:0] DAT_I,
  output logic [31:0] DAT_O,
  input  logic        WE_I,
  input  logic [3:0]  SEL_I,
  input  logic        STB_I,
  input  logic        CYC_I,
  output logic        ACK_O,
  output logic        ERR_O,
  output logic        RTY_O,

  // Interrupt
  output logic        irq
);

  assign ERR_O = 1'b0;
  assign RTY_O = 1'b0;

  // ── Configuration registers ─────────────────────────────────────────────
  logic [CRC_W-1:0] reg_poly, reg_init, reg_xorout;
  logic              reg_reflect_in, reg_reflect_out;
  logic              reg_busy, reg_done;

  // ── CRC top signals ────────────────────────────────────────────────────
  crc_config_t       cfg_out;
  logic              top_start, top_busy, top_done;
  logic              top_data_valid, top_last;
  logic [DATA_W-1:0] top_data;
  logic [CRC_W-1:0]  top_crc;
  logic [31:0]        top_version;

  always_comb begin
    cfg_out.polynomial  = reg_poly;
    cfg_out.init_val    = reg_init;
    cfg_out.final_xor   = reg_xorout;
    cfg_out.reflect_in  = reg_reflect_in;
    cfg_out.reflect_out = reg_reflect_out;
  end

  crc_top u_crc (
    .clk          (CLK_I),
    .rst_n        (~RST_I),
    .s_cfg        (cfg_out),
    .start_i      (top_start),
    .busy_o       (top_busy),
    .done_o       (top_done),
    .s_data_valid (top_data_valid),
    .s_data       (top_data),
    .s_last       (top_last),
    .crc_o        (top_crc),
    .version_o    (top_version)
  );

  // ── IRQ: pulse on done rising edge ──────────────────────────────────────
  logic done_prev;
  always_ff @(posedge CLK_I) begin
    if (RST_I) done_prev <= 1'b0;
    else       done_prev <= top_done;
  end
  assign irq = top_done & ~done_prev;

  // ── Latched CRC result ──────────────────────────────────────────────────
  logic [CRC_W-1:0] crc_result;
  always_ff @(posedge CLK_I) begin
    if (RST_I)
      crc_result <= '0;
    else if (top_done)
      crc_result <= top_crc;
  end

  // ── Bus logic ──────────────────────────────────────────────────────────
  always_ff @(posedge CLK_I) begin
    if (RST_I) begin
      ACK_O          <= 1'b0;
      DAT_O          <= '0;
      reg_poly       <= '0;
      reg_init       <= '0;
      reg_xorout     <= '0;
      reg_reflect_in <= 1'b0;
      reg_reflect_out<= 1'b0;
      reg_busy       <= 1'b0;
      reg_done       <= 1'b0;
      top_start      <= 1'b0;
      top_data_valid <= 1'b0;
      top_last       <= 1'b0;
      top_data       <= '0;
    end else begin
      ACK_O          <= 1'b0;
      top_start      <= 1'b0;
      top_data_valid <= 1'b0;
      top_last       <= 1'b0;

      // Track busy/done from core
      reg_busy <= top_busy;
      if (top_done) reg_done <= 1'b1;

      // ── Wishbone transaction ──────────────────────────────────────────
      if (CYC_I && STB_I && !ACK_O) begin
        ACK_O <= 1'b1;

        if (WE_I) begin
          unique case (ADR_I[5:2])
            4'h0: begin  // CTRL
              if (DAT_I[0] && !reg_busy) begin
                top_start <= 1'b1;
                reg_done  <= 1'b0;
              end
            end
            4'h4: reg_poly       <= CRC_W'(DAT_I);   // POLY
            4'h5: reg_init       <= CRC_W'(DAT_I);   // INIT
            4'h6: reg_xorout     <= CRC_W'(DAT_I);   // XOROUT
            4'h7: begin  // CFG
              reg_reflect_in  <= DAT_I[0];
              reg_reflect_out <= DAT_I[1];
            end
            4'h8: begin  // DIN
              top_data_valid <= 1'b1;
              top_data       <= DATA_W'(DAT_I);
            end
            4'h9: begin  // DIN_LAST
              top_data_valid <= 1'b1;
              top_last       <= 1'b1;
              top_data       <= DATA_W'(DAT_I);
            end
            default: ;
          endcase
        end else begin
          // Read
          unique case (ADR_I[5:2])
            4'h0: DAT_O <= {29'd0, reg_done, reg_busy, 1'b0};  // CTRL
            4'h1: DAT_O <= {30'd0, reg_reflect_out, reg_reflect_in};  // STATUS
            4'h2: DAT_O <= {16'd0, DATA_W[7:0], CRC_W[7:0]};   // INFO
            4'h3: DAT_O <= top_version;                           // VERSION
            4'h4: DAT_O <= 32'(reg_poly);                         // POLY
            4'h5: DAT_O <= 32'(reg_init);                         // INIT
            4'h6: DAT_O <= 32'(reg_xorout);                       // XOROUT
            4'h7: DAT_O <= {30'd0, reg_reflect_out, reg_reflect_in};  // CFG
            4'hA: DAT_O <= 32'(crc_result);                       // DOUT
            default: DAT_O <= 32'hDEAD_BEEF;
          endcase
        end
      end
    end
  end

endmodule : crc_wb
