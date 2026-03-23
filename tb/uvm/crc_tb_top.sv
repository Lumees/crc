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
// CRC UVM Testbench — Top-level Module
// =============================================================================
// Instantiates:
//   - crc_top DUT
//   - Clock generator (10 ns period)
//   - Reset sequence (active-low, deassert after 10 cycles)
//   - crc_if virtual interface
//   - UVM config_db registration
//   - run_test() kick-off
//
// Simulation plusargs:
//   +UVM_TESTNAME=<test>   (e.g., crc_directed_test, crc_random_test)
// =============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"

import uvm_pkg::*;
import crc_pkg::*;

// Include all testbench files in order of dependency
`include "crc_seq_item.sv"
`include "crc_if.sv"
`include "crc_driver.sv"
`include "crc_monitor.sv"
`include "crc_scoreboard.sv"
`include "crc_coverage.sv"
`include "crc_agent.sv"
`include "crc_env.sv"
`include "crc_sequences.sv"
`include "crc_tests.sv"

module crc_tb_top;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  // 10 ns period -> 100 MHz
  initial clk = 1'b0;
  always #5ns clk = ~clk;

  // Reset: assert for 10 cycles, then release
  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    @(negedge clk);   // deassert on falling edge for clean setup
    rst_n = 1'b1;
    `uvm_info("TB_TOP", "Reset deasserted", UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Virtual interface instantiation
  // ---------------------------------------------------------------------------
  crc_if dut_if (.clk(clk), .rst_n(rst_n));

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  crc_top dut (
    .clk          (clk),
    .rst_n        (rst_n),

    // Configuration
    .s_cfg        (dut_if.s_cfg),

    // Control
    .start_i      (dut_if.start_i),
    .busy_o       (dut_if.busy_o),
    .done_o       (dut_if.done_o),

    // Streaming data input
    .s_data_valid (dut_if.s_data_valid),
    .s_data       (dut_if.s_data),
    .s_last       (dut_if.s_last),

    // Result
    .crc_o        (dut_if.crc_o),

    // Info
    .version_o    (dut_if.version_o)
  );

  // ---------------------------------------------------------------------------
  // UVM config_db: register virtual interface
  // ---------------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual crc_if)::set(
      null,          // from context (global)
      "uvm_test_top.*",
      "vif",
      dut_if
    );

    `uvm_info("TB_TOP",
      "CRC DUT instantiated, vif registered in config_db",
      UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Simulation timeout watchdog (prevents infinite hang on protocol errors)
  // ---------------------------------------------------------------------------
  initial begin
    // Allow enough time for stress test (200 txns x ~300 cycles x 10 ns)
    #1ms;
    `uvm_fatal("WATCHDOG", "Simulation timeout — check for protocol deadlock")
  end

  // ---------------------------------------------------------------------------
  // Waveform dump (uncomment for VCD/FSDB capture)
  // ---------------------------------------------------------------------------
  // initial begin
  //   $dumpfile("crc_tb.vcd");
  //   $dumpvars(0, crc_tb_top);
  // end

  // ---------------------------------------------------------------------------
  // Start UVM test
  // ---------------------------------------------------------------------------
  initial begin
    run_test();
  end

endmodule : crc_tb_top
