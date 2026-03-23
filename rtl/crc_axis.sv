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
// CRC IP — AXI4-Stream Interface Wrapper
// =============================================================================
// One CRC result per input packet (delimited by s_axis_tlast).
// Configuration is latched from cfg_i on the first beat of each packet.
// Tag (tuser) is captured on the first beat and propagated to the output.
// Output is always a single beat per packet (m_axis_tlast tied to 1).
//
// Output FIFO depth: configurable via FIFO_DEPTH parameter (default 16).
// =============================================================================

`timescale 1ns/1ps

import crc_pkg::*;

module crc_axis #(
  parameter int FIFO_DEPTH = 16
) (
  input  logic                clk,
  input  logic                rst_n,

  // Sideband configuration (latched on first beat of each packet)
  input  crc_config_t         cfg_i,

  // AXI4-Stream Slave (input)
  input  logic                s_axis_tvalid,
  output logic                s_axis_tready,
  input  logic [DATA_W-1:0]  s_axis_tdata,
  input  logic                s_axis_tlast,
  input  logic [7:0]          s_axis_tuser,   // tag

  // AXI4-Stream Master (output)
  output logic                m_axis_tvalid,
  input  logic                m_axis_tready,
  output logic [CRC_W-1:0]   m_axis_tdata,
  output logic                m_axis_tlast,
  output logic [7:0]          m_axis_tuser    // tag
);

  // ── FSM ──────────────────────────────────────────────────────────────────
  typedef enum logic [1:0] {S_IDLE, S_RUN, S_WAIT} state_t;
  state_t state;

  // Core interface signals
  logic                start;
  logic                busy;
  logic                done;
  logic [CRC_W-1:0]   crc_result;
  crc_config_t         cfg_lat;
  logic [7:0]          tag_lat;

  // Handshake: slave accepted beat
  logic s_beat;
  assign s_beat = s_axis_tvalid && s_axis_tready;

  // ── CRC core instance ───────────────────────────────────────────────────
  crc_top u_crc (
    .clk         (clk),
    .rst_n       (rst_n),
    .s_cfg       (cfg_lat),
    .start_i     (start),
    .busy_o      (busy),
    .done_o      (done),
    .s_data_valid(s_beat && (state == S_RUN)),
    .s_data      (s_axis_tdata),
    .s_last      (s_axis_tlast),
    .crc_o       (crc_result),
    .version_o   (/* unused */)
  );

  // ── Control FSM ─────────────────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      start   <= 1'b0;
      cfg_lat <= '0;
      tag_lat <= '0;
    end else begin
      start <= 1'b0;

      unique case (state)

        // Wait for the first beat of a new packet
        S_IDLE: begin
          if (s_axis_tvalid) begin
            cfg_lat <= cfg_i;
            tag_lat <= s_axis_tuser;
            start   <= 1'b1;
            state   <= S_RUN;
          end
        end

        // Stream data beats into the core
        S_RUN: begin
          if (s_beat && s_axis_tlast) begin
            state <= S_WAIT;
          end
        end

        // Wait for the core to finish (done pulse)
        S_WAIT: begin
          if (done) begin
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;

      endcase
    end
  end

  // Accept slave data in RUN state (core consumes one word per clock)
  assign s_axis_tready = (state == S_RUN);

  // ── Output FIFO — synchronous, stores {tag[7:0], crc[CRC_W-1:0]} ─────
  localparam int FIFO_W  = CRC_W + 8;
  localparam int FIFO_AW = $clog2(FIFO_DEPTH);

  logic [FIFO_W-1:0] fifo_mem [0:FIFO_DEPTH-1];
  logic [FIFO_AW:0]  fifo_wptr, fifo_rptr;
  logic               fifo_empty, fifo_full;
  logic [FIFO_W-1:0] fifo_din, fifo_dout;

  assign fifo_din   = {tag_lat, crc_result};
  assign fifo_empty = (fifo_wptr == fifo_rptr);
  assign fifo_full  = (fifo_wptr[FIFO_AW-1:0] == fifo_rptr[FIFO_AW-1:0]) &&
                      (fifo_wptr[FIFO_AW]      != fifo_rptr[FIFO_AW]);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fifo_wptr <= '0;
      fifo_rptr <= '0;
    end else begin
      if (done && !fifo_full) begin
        fifo_mem[fifo_wptr[FIFO_AW-1:0]] <= fifo_din;
        fifo_wptr <= fifo_wptr + 1;
      end
      if (m_axis_tvalid && m_axis_tready) begin
        fifo_rptr <= fifo_rptr + 1;
      end
    end
  end

  assign fifo_dout = fifo_mem[fifo_rptr[FIFO_AW-1:0]];

  // ── Master AXI4-Stream outputs ──────────────────────────────────────────
  assign m_axis_tvalid = !fifo_empty;
  assign m_axis_tdata  = fifo_dout[CRC_W-1:0];
  assign m_axis_tuser  = fifo_dout[CRC_W+7:CRC_W];
  assign m_axis_tlast  = 1'b1;  // single-beat output per packet

endmodule : crc_axis
