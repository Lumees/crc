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
// CRC IP — AXI4-Lite Interface Wrapper
// =============================================================================
// Register map (32-bit word address, 4-byte aligned):
//
//  Offset  Name        Access  Description
//  0x00    CTRL        R/W     [0]=start (self-clear W), [1]=busy(RO), [2]=done(RO)
//  0x04    STATUS      RO      [0]=reflect_in_lat, [1]=reflect_out_lat
//  0x08    INFO        RO      [7:0]=CRC_W, [15:8]=DATA_W
//  0x0C    VERSION     RO      IP_VERSION from crc_pkg
//  0x10    POLY        R/W     Polynomial [CRC_W-1:0]
//  0x14    INIT        R/W     Init value [CRC_W-1:0]
//  0x18    XOROUT      R/W     Final XOR [CRC_W-1:0]
//  0x1C    CFG         R/W     [0]=reflect_in, [1]=reflect_out
//  0x20    DIN         W       Data input: write triggers s_data_valid pulse
//  0x24    DIN_LAST    W       Data input + s_last: write triggers s_data_valid + s_last
//  0x28    DOUT        RO      CRC result [CRC_W-1:0] (valid when done)
//
// Write CTRL[0]=1 to trigger a computation.
// Feed data via DIN / DIN_LAST writes while busy.
// Poll CTRL[2] (done) to read result, or wait for irq pulse.
// Done is sticky, cleared on next start.
//
// irq: single-cycle output pulse when done transitions 0→1.
// =============================================================================

`timescale 1ns/1ps

import crc_pkg::*;

module crc_axil (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite Slave
  input  logic [31:0] s_axil_awaddr,
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  output logic [1:0]  s_axil_bresp,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  input  logic [31:0] s_axil_araddr,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,

  // Interrupt — single-cycle pulse when done (CTRL[2]) rises
  output logic        irq
);

  // -------------------------------------------------------------------------
  // Internal registers
  // -------------------------------------------------------------------------
  logic [2:0]              reg_ctrl;       // [0]=start, [1]=busy, [2]=done
  logic [CRC_W-1:0]       reg_poly;
  logic [CRC_W-1:0]       reg_init;
  logic [CRC_W-1:0]       reg_xorout;
  logic [1:0]             reg_cfg;        // [0]=reflect_in, [1]=reflect_out
  logic [CRC_W-1:0]       reg_dout;

  // -------------------------------------------------------------------------
  // CRC engine
  // -------------------------------------------------------------------------
  crc_config_t             core_cfg;
  logic                    core_start;
  logic                    core_busy;
  logic                    core_done;
  logic                    core_data_valid;
  logic [DATA_W-1:0]      core_data;
  logic                    core_last;
  logic [CRC_W-1:0]       core_crc;
  logic [31:0]            core_version;

  assign core_cfg.polynomial  = reg_poly;
  assign core_cfg.init_val    = reg_init;
  assign core_cfg.final_xor   = reg_xorout;
  assign core_cfg.reflect_in  = reg_cfg[0];
  assign core_cfg.reflect_out = reg_cfg[1];

  crc_top u_crc (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_cfg        (core_cfg),
    .start_i      (core_start),
    .busy_o       (core_busy),
    .done_o       (core_done),
    .s_data_valid (core_data_valid),
    .s_data       (core_data),
    .s_last       (core_last),
    .crc_o        (core_crc),
    .version_o    (core_version)
  );

  // -------------------------------------------------------------------------
  // Latched config readback (STATUS register)
  // -------------------------------------------------------------------------
  // crc_top latches config on start; we mirror that here for STATUS readback.
  logic reflect_in_lat, reflect_out_lat;

  // -------------------------------------------------------------------------
  // Control state machine
  // -------------------------------------------------------------------------
  typedef enum logic {
    S_IDLE = 1'b0,
    S_RUN  = 1'b1
  } state_t;
  state_t state;

  // -------------------------------------------------------------------------
  // AXI4-Lite write path + FSM
  // -------------------------------------------------------------------------
  logic [5:0]  wr_addr;
  logic [31:0] wdata_lat;
  logic        aw_active, w_active;

  assign s_axil_awready = !aw_active;
  assign s_axil_wready  = !w_active;
  assign s_axil_bresp   = 2'b00;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_active        <= 1'b0;
      w_active         <= 1'b0;
      wr_addr          <= '0;
      wdata_lat        <= '0;
      s_axil_bvalid    <= 1'b0;
      reg_ctrl         <= '0;
      reg_poly         <= '0;
      reg_init         <= '0;
      reg_xorout       <= '0;
      reg_cfg          <= '0;
      reg_dout         <= '0;
      reflect_in_lat   <= 1'b0;
      reflect_out_lat  <= 1'b0;
      state            <= S_IDLE;
      core_start       <= 1'b0;
      core_data_valid  <= 1'b0;
      core_data        <= '0;
      core_last        <= 1'b0;
    end else begin
      // ── AXI4-Lite write handshake ──────────────────────────────────────
      if (s_axil_awvalid && s_axil_awready) begin
        wr_addr   <= s_axil_awaddr[7:2];
        aw_active <= 1'b1;
      end
      if (s_axil_wvalid && s_axil_wready) begin
        wdata_lat <= s_axil_wdata;
        w_active  <= 1'b1;
      end
      if (s_axil_bvalid && s_axil_bready)
        s_axil_bvalid <= 1'b0;

      // ── Non-CTRL, non-DIN register writes (any FSM state) ─────────────
      if (aw_active && w_active &&
          (wr_addr != 6'h00) && (wr_addr != 6'h08) && (wr_addr != 6'h09)) begin
        aw_active     <= 1'b0;
        w_active      <= 1'b0;
        s_axil_bvalid <= 1'b1;
        unique case (wr_addr)
          6'h04: reg_poly   <= wdata_lat[CRC_W-1:0];
          6'h05: reg_init   <= wdata_lat[CRC_W-1:0];
          6'h06: reg_xorout <= wdata_lat[CRC_W-1:0];
          6'h07: reg_cfg    <= wdata_lat[1:0];
          default: ;
        endcase
      end

      // ── FSM + CTRL + DIN/DIN_LAST ─────────────────────────────────────
      core_start      <= 1'b0;   // default: de-assert each cycle
      core_data_valid <= 1'b0;
      core_last       <= 1'b0;

      unique case (state)
        S_IDLE: begin
          reg_ctrl[1] <= 1'b0;   // busy = 0
          if (aw_active && w_active && (wr_addr == 6'h00)) begin
            aw_active     <= 1'b0;
            w_active      <= 1'b0;
            s_axil_bvalid <= 1'b1;
            if (wdata_lat[0]) begin
              reg_ctrl[0]    <= 1'b0;   // auto-clear start
              reg_ctrl[1]    <= 1'b1;   // set busy
              reg_ctrl[2]    <= 1'b0;   // clear done
              reflect_in_lat <= reg_cfg[0];
              reflect_out_lat<= reg_cfg[1];
              core_start     <= 1'b1;
              state          <= S_RUN;
            end
          end
        end

        S_RUN: begin
          // DIN write (offset 0x20 = word 0x08)
          if (aw_active && w_active && (wr_addr == 6'h08)) begin
            aw_active       <= 1'b0;
            w_active        <= 1'b0;
            s_axil_bvalid   <= 1'b1;
            core_data_valid <= 1'b1;
            core_data       <= wdata_lat[DATA_W-1:0];
            core_last       <= 1'b0;
          end
          // DIN_LAST write (offset 0x24 = word 0x09)
          if (aw_active && w_active && (wr_addr == 6'h09)) begin
            aw_active       <= 1'b0;
            w_active        <= 1'b0;
            s_axil_bvalid   <= 1'b1;
            core_data_valid <= 1'b1;
            core_data       <= wdata_lat[DATA_W-1:0];
            core_last       <= 1'b1;
          end
          // CTRL write while running (ignore start, just ACK)
          if (aw_active && w_active && (wr_addr == 6'h00)) begin
            aw_active     <= 1'b0;
            w_active      <= 1'b0;
            s_axil_bvalid <= 1'b1;
          end
          // Done from core
          if (core_done) begin
            reg_dout    <= core_crc;
            reg_ctrl[1] <= 1'b0;   // clear busy
            reg_ctrl[2] <= 1'b1;   // set done
            state       <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // Interrupt: single-cycle pulse when done bit (CTRL[2]) rises 0→1
  // -------------------------------------------------------------------------
  logic done_prev;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done_prev <= 1'b0;
      irq       <= 1'b0;
    end else begin
      done_prev <= reg_ctrl[2];
      irq       <= reg_ctrl[2] & ~done_prev;
    end
  end

  // -------------------------------------------------------------------------
  // AXI4-Lite read logic
  // -------------------------------------------------------------------------
  assign s_axil_rresp = 2'b00;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b1;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= '0;
    end else begin
      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b1;
        unique case (s_axil_araddr[7:2])
          6'h00: s_axil_rdata <= {29'h0, reg_ctrl};
          6'h01: s_axil_rdata <= {30'h0, reflect_out_lat, reflect_in_lat};
          6'h02: s_axil_rdata <= {16'h0, DATA_W[7:0], CRC_W[7:0]};
          6'h03: s_axil_rdata <= core_version;
          6'h04: s_axil_rdata <= {{(32-CRC_W){1'b0}}, reg_poly};
          6'h05: s_axil_rdata <= {{(32-CRC_W){1'b0}}, reg_init};
          6'h06: s_axil_rdata <= {{(32-CRC_W){1'b0}}, reg_xorout};
          6'h07: s_axil_rdata <= {30'h0, reg_cfg};
          6'h08: s_axil_rdata <= 32'h0;  // DIN (write-only)
          6'h09: s_axil_rdata <= 32'h0;  // DIN_LAST (write-only)
          6'h0A: s_axil_rdata <= {{(32-CRC_W){1'b0}}, reg_dout};
          default: s_axil_rdata <= 32'hDEAD_BEEF;
        endcase
      end
      if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid  <= 1'b0;
        s_axil_arready <= 1'b1;
      end
    end
  end

endmodule : crc_axil
