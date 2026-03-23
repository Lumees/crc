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
// CRC UVM Testbench — Virtual Interface
// =============================================================================
// Provides a SystemVerilog interface wrapping all crc_top ports.
// CRC_W and DATA_W are fixed to package defaults (32 and 8 respectively).
// =============================================================================

`timescale 1ns/1ps

interface crc_if (input logic clk, input logic rst_n);

  import crc_pkg::*;

  // ---------------------------------------------------------------------------
  // DUT ports (all driven/sampled here)
  // ---------------------------------------------------------------------------

  // Configuration
  crc_config_t            s_cfg;

  // Control
  logic                   start_i;
  logic                   busy_o;
  logic                   done_o;

  // Streaming data input
  logic                   s_data_valid;
  logic [DATA_W-1:0]      s_data;
  logic                   s_last;

  // Result
  logic [CRC_W-1:0]       crc_o;

  // Info
  logic [31:0]            version_o;

  // ---------------------------------------------------------------------------
  // Driver clocking block (active driving on posedge; sample 1-step before edge)
  // ---------------------------------------------------------------------------
  clocking driver_cb @(posedge clk);
    default input  #1step
            output #1step;

    // Configuration — driven by driver
    output s_cfg;

    // Control
    output start_i;
    input  busy_o;
    input  done_o;

    // Streaming data
    output s_data_valid;
    output s_data;
    output s_last;

    // Result — driver reads back response
    input  crc_o;

    // Info
    input  version_o;
  endclocking : driver_cb

  // ---------------------------------------------------------------------------
  // Monitor clocking block (passive — only inputs)
  // ---------------------------------------------------------------------------
  clocking monitor_cb @(posedge clk);
    default input #1step;

    input s_cfg;

    input start_i;
    input busy_o;
    input done_o;

    input s_data_valid;
    input s_data;
    input s_last;

    input crc_o;

    input version_o;
  endclocking : monitor_cb

  // ---------------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------------
  modport driver_mp  (clocking driver_cb,  input clk, input rst_n);
  modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : crc_if
