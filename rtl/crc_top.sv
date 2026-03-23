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
// CRC IP — Top-level with start/busy/done flow control
// =============================================================================
// FSM: S_IDLE → S_RUN → S_FINAL → S_DONE → S_IDLE
// One DATA_W-bit chunk consumed per clock in S_RUN.
//
// Software contract:
//   Every computation MUST be terminated by a DIN_LAST write. If software
//   starts a computation (CTRL.start) and never sends DIN_LAST, the FSM
//   stays in S_RUN indefinitely with no timeout or abort. This is by design
//   for a simple byte-stream engine. A CTRL[abort] bit is planned for v1.1.
// =============================================================================

`timescale 1ns/1ps

import crc_pkg::*;

module crc_top (
  input  logic                clk,
  input  logic                rst_n,

  // Configuration (latched on start)
  input  crc_config_t         s_cfg,

  // Control
  input  logic                start_i,
  output logic                busy_o,
  output logic                done_o,

  // Streaming data input
  input  logic                s_data_valid,
  input  logic [DATA_W-1:0]  s_data,
  input  logic                s_last,       // marks final chunk

  // Result
  output logic [CRC_W-1:0]   crc_o,

  // Info
  output logic [31:0]         version_o
);

  assign version_o = IP_VERSION;

  // ── State machine ─────────────────────────────────────────────────────────
  typedef enum logic [1:0] {S_IDLE, S_RUN, S_FINAL, S_DONE} state_t;
  state_t state;

  crc_config_t cfg_lat;

  // Core control signals
  logic core_init;
  logic core_data_valid;
  logic core_finalize;
  logic [DATA_W-1:0] core_data_in;
  logic [CRC_W-1:0]  core_crc_out;
  logic               core_crc_valid;

  crc_core u_core (
    .clk        (clk),
    .rst_n      (rst_n),
    .cfg        (cfg_lat),
    .init       (core_init),
    .data_valid (core_data_valid),
    .data_in    (core_data_in),
    .finalize   (core_finalize),
    .crc_out    (core_crc_out),
    .crc_valid  (core_crc_valid)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= S_IDLE;
      busy_o         <= 1'b0;
      done_o         <= 1'b0;
      crc_o          <= '0;
      core_init      <= 1'b0;
      core_data_valid<= 1'b0;
      core_finalize  <= 1'b0;
      core_data_in   <= '0;
    end else begin
      // Default: deassert pulses
      core_init       <= 1'b0;
      core_data_valid <= 1'b0;
      core_finalize   <= 1'b0;

      unique case (state)

        S_IDLE: begin
          done_o <= 1'b0;
          if (start_i) begin
            state      <= S_RUN;
            busy_o     <= 1'b1;
            cfg_lat    <= s_cfg;
            core_init  <= 1'b1;  // load init_val into CRC register
          end
        end

        S_RUN: begin
          if (s_data_valid) begin
            core_data_valid <= 1'b1;
            core_data_in    <= s_data;
            if (s_last) begin
              state <= S_FINAL;
            end
          end
        end

        S_FINAL: begin
          // One-cycle finalize (reflect + XOR)
          core_finalize <= 1'b1;
          state         <= S_DONE;
        end

        S_DONE: begin
          // core_crc_valid fires this cycle (1 cycle after finalize)
          if (core_crc_valid) begin
            crc_o  <= core_crc_out;
            done_o <= 1'b1;
            busy_o <= 1'b0;
            state  <= S_IDLE;
          end
        end

      endcase
    end
  end

endmodule : crc_top
