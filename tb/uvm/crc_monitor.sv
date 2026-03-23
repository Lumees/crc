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
// CRC UVM Testbench — Monitor
// =============================================================================
// Passive monitor split into two logical sub-monitors in a single class:
//
//   Input sub-monitor  : captures start_i pulse and data streaming
//   Output sub-monitor : captures done_o pulse and crc_o result
//
// The input analysis port emits items when data streaming completes; the output
// port emits items when the DUT produces a result. The scoreboard correlates
// them via FIFO ordering (pipeline is in-order).
// =============================================================================

`ifndef CRC_MONITOR_SV
`define CRC_MONITOR_SV

`include "uvm_macros.svh"

class crc_monitor extends uvm_monitor;

  import crc_pkg::*;

  `uvm_component_utils(crc_monitor)

  // Analysis ports
  uvm_analysis_port #(crc_seq_item) ap_in;   // stimuli accepted by DUT
  uvm_analysis_port #(crc_seq_item) ap_out;  // results produced by DUT

  // Virtual interface (read-only via monitor_cb)
  virtual crc_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_in  = new("ap_in",  this);
    ap_out = new("ap_out", this);

    if (!uvm_config_db #(virtual crc_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "crc_monitor: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // run_phase: fork both sub-monitors
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      monitor_input();
      monitor_output();
    join
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // monitor_input: watch for start_i pulse and capture streaming data
  // ---------------------------------------------------------------------------
  task monitor_input();
    crc_seq_item item;
    forever begin
      // Wait for start_i pulse
      @(vif.monitor_cb);
      if (vif.monitor_cb.start_i === 1'b1) begin
        item = crc_seq_item::type_id::create("mon_in_item");
        item.polynomial  = vif.monitor_cb.s_cfg.polynomial;
        item.init_val    = vif.monitor_cb.s_cfg.init_val;
        item.final_xor   = vif.monitor_cb.s_cfg.final_xor;
        item.reflect_in  = vif.monitor_cb.s_cfg.reflect_in;
        item.reflect_out = vif.monitor_cb.s_cfg.reflect_out;

        // Collect data bytes until s_last
        item.data = new[0];
        forever begin
          @(vif.monitor_cb);
          if (vif.monitor_cb.s_data_valid === 1'b1) begin
            item.data = new[item.data.size() + 1](item.data);
            item.data[item.data.size() - 1] = vif.monitor_cb.s_data;
            if (vif.monitor_cb.s_last === 1'b1) break;
          end
        end

        `uvm_info("MON_IN",
          $sformatf("Input captured: poly=%h len=%0d",
            item.polynomial, item.data.size()),
          UVM_HIGH)
        ap_in.write(item);
      end
    end
  endtask : monitor_input

  // ---------------------------------------------------------------------------
  // monitor_output: watch for done_o assertion
  // ---------------------------------------------------------------------------
  task monitor_output();
    crc_seq_item item;
    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.done_o === 1'b1) begin
        item = crc_seq_item::type_id::create("mon_out_item");
        item.actual_crc = vif.monitor_cb.crc_o;

        `uvm_info("MON_OUT",
          $sformatf("Output valid: crc_o=%h", item.actual_crc),
          UVM_HIGH)
        ap_out.write(item);
      end
    end
  endtask : monitor_output

endclass : crc_monitor

`endif // CRC_MONITOR_SV
