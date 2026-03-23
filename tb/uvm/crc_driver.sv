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
// CRC UVM Testbench — Driver
// =============================================================================
// Drives crc_top via the virtual interface clocking block.
// Protocol per DUT spec (crc_top.sv):
//   1. Write configuration to s_cfg.
//   2. Pulse start_i for one cycle.
//   3. Stream data bytes with s_data_valid; assert s_last on the final byte.
//   4. Wait for done_o, capture crc_o into seq_item response fields.
// =============================================================================

`ifndef CRC_DRIVER_SV
`define CRC_DRIVER_SV

`include "uvm_macros.svh"

class crc_driver extends uvm_driver #(crc_seq_item);

  import crc_pkg::*;

  `uvm_component_utils(crc_driver)

  // Virtual interface handle
  virtual crc_if vif;

  // Max cycles to wait for done_o
  localparam int DONE_TIMEOUT = 5000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase: retrieve virtual interface from config_db
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual crc_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "crc_driver: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // run_phase: main driver loop
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    crc_seq_item req, rsp;

    // Initialise all driven signals to safe defaults
    vif.driver_cb.s_cfg        <= '0;
    vif.driver_cb.start_i      <= 1'b0;
    vif.driver_cb.s_data_valid <= 1'b0;
    vif.driver_cb.s_data       <= '0;
    vif.driver_cb.s_last       <= 1'b0;

    // Wait for reset to deassert
    @(posedge vif.clk);
    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    forever begin
      // Get next item from sequencer
      seq_item_port.get_next_item(req);
      `uvm_info("DRV", $sformatf("Driving: %s", req.convert2string()), UVM_HIGH)

      // Clone for response
      rsp = crc_seq_item::type_id::create("rsp");
      rsp.copy(req);

      // ------------------------------------------------------------------
      // Step 1: Configure and start
      // ------------------------------------------------------------------
      drive_start(req);

      // ------------------------------------------------------------------
      // Step 2: Stream data bytes
      // ------------------------------------------------------------------
      drive_data(req);

      // ------------------------------------------------------------------
      // Step 3: Wait for done and capture CRC
      // ------------------------------------------------------------------
      capture_output(rsp);

      // Return response to sequence
      seq_item_port.item_done(rsp);
    end
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // drive_start: present config, pulse start_i
  // ---------------------------------------------------------------------------
  task drive_start(crc_seq_item item);
    crc_config_t cfg;
    cfg = item.get_config();

    @(vif.driver_cb);
    vif.driver_cb.s_cfg   <= cfg;
    vif.driver_cb.start_i <= 1'b1;
    @(vif.driver_cb);
    vif.driver_cb.start_i <= 1'b0;

    `uvm_info("DRV",
      $sformatf("Start pulsed: poly=%h init=%h xor=%h ref_in=%0b ref_out=%0b",
        cfg.polynomial, cfg.init_val, cfg.final_xor, cfg.reflect_in, cfg.reflect_out),
      UVM_HIGH)
  endtask : drive_start

  // ---------------------------------------------------------------------------
  // drive_data: stream data bytes, assert s_last on final byte
  // ---------------------------------------------------------------------------
  task drive_data(crc_seq_item item);
    int num_bytes;
    num_bytes = item.data.size();

    for (int i = 0; i < num_bytes; i++) begin
      @(vif.driver_cb);
      vif.driver_cb.s_data_valid <= 1'b1;
      vif.driver_cb.s_data       <= item.data[i];
      vif.driver_cb.s_last       <= (i == num_bytes - 1) ? 1'b1 : 1'b0;
    end

    // Deassert after last byte
    @(vif.driver_cb);
    vif.driver_cb.s_data_valid <= 1'b0;
    vif.driver_cb.s_data       <= '0;
    vif.driver_cb.s_last       <= 1'b0;

    `uvm_info("DRV",
      $sformatf("Data streamed: %0d bytes", num_bytes),
      UVM_HIGH)
  endtask : drive_data

  // ---------------------------------------------------------------------------
  // capture_output: wait for done_o, read crc_o
  // ---------------------------------------------------------------------------
  task capture_output(crc_seq_item rsp);
    int timeout;

    timeout = 0;
    @(vif.driver_cb);
    while (!vif.driver_cb.done_o) begin
      @(vif.driver_cb);
      timeout++;
      if (timeout >= DONE_TIMEOUT)
        `uvm_fatal("DRV_TIMEOUT",
          $sformatf("done_o never asserted after %0d cycles", DONE_TIMEOUT))
    end

    rsp.actual_crc = vif.driver_cb.crc_o;
    `uvm_info("DRV",
      $sformatf("Output captured: crc_o=%h", rsp.actual_crc),
      UVM_HIGH)
  endtask : capture_output

endclass : crc_driver

`endif // CRC_DRIVER_SV
