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
// CRC UVM Testbench — Scoreboard
// =============================================================================
// Self-checking scoreboard:
//   - Receives full-context items via ae_context (from sequence)
//   - Receives DUT output items via ae_out (from output monitor)
//   - Computes expected CRC using crc_pkg::crc_step reference model
//   - Compares DUT crc_o against reference CRC
//   - Reports pass/fail counts in check_phase
// =============================================================================

`ifndef CRC_SCOREBOARD_SV
`define CRC_SCOREBOARD_SV

`include "uvm_macros.svh"

class crc_scoreboard extends uvm_scoreboard;

  import crc_pkg::*;

  `uvm_component_utils(crc_scoreboard)

  // TLM FIFOs fed from the monitor / sequence analysis ports
  uvm_tlm_analysis_fifo #(crc_seq_item) fifo_in;
  uvm_tlm_analysis_fifo #(crc_seq_item) fifo_out;
  uvm_tlm_analysis_fifo #(crc_seq_item) fifo_context;

  // Analysis exports (connected in env)
  uvm_analysis_export #(crc_seq_item) ae_in;
  uvm_analysis_export #(crc_seq_item) ae_out;
  uvm_analysis_export #(crc_seq_item) ae_context;

  // Counters
  int unsigned pass_count;
  int unsigned fail_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    pass_count = 0;
    fail_count = 0;
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    fifo_in      = new("fifo_in",      this);
    fifo_out     = new("fifo_out",     this);
    fifo_context = new("fifo_context", this);
    ae_in        = new("ae_in",        this);
    ae_out       = new("ae_out",       this);
    ae_context   = new("ae_context",   this);
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // connect_phase: wire exports to FIFOs
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    ae_in.connect      (fifo_in.analysis_export);
    ae_out.connect     (fifo_out.analysis_export);
    ae_context.connect (fifo_context.analysis_export);
  endfunction : connect_phase

  // ---------------------------------------------------------------------------
  // run_phase: drain FIFOs and check
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    crc_seq_item stim_item, resp_item, ctx_item;
    logic [CRC_W-1:0] expected;

    forever begin
      // Wait for a DUT output
      fifo_out.get(resp_item);

      // Get matching stimulus (in-order pipeline)
      fifo_in.get(stim_item);

      // Get full context (sent by the sequence)
      fifo_context.get(ctx_item);

      // Compute expected CRC using reference model
      expected = ref_crc_compute(ctx_item);

      if (resp_item.actual_crc === expected) begin
        pass_count++;
        `uvm_info("SB_PASS",
          $sformatf("PASS | poly=%h len=%0d | exp=%h | got=%h",
            ctx_item.polynomial,
            ctx_item.data.size(),
            expected,
            resp_item.actual_crc),
          UVM_MEDIUM)
      end else begin
        fail_count++;
        `uvm_error("SB_FAIL",
          $sformatf("FAIL | poly=%h len=%0d | exp=%h | got=%h",
            ctx_item.polynomial,
            ctx_item.data.size(),
            expected,
            resp_item.actual_crc))
      end
    end
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // check_phase: summary report
  // ---------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    `uvm_info("SB_SUMMARY",
      $sformatf("Scoreboard results: PASS=%0d  FAIL=%0d",
        pass_count, fail_count),
      UVM_NONE)

    if (fail_count > 0)
      `uvm_error("SB_SUMMARY",
        $sformatf("%0d transaction(s) FAILED — see above for details", fail_count))

    if (!fifo_in.is_empty())
      `uvm_warning("SB_LEFTOVERS",
        $sformatf("%0d input item(s) unmatched in fifo_in at end of test",
          fifo_in.used()))

    if (!fifo_out.is_empty())
      `uvm_warning("SB_LEFTOVERS",
        $sformatf("%0d output item(s) unmatched in fifo_out at end of test",
          fifo_out.used()))
  endfunction : check_phase

  // ===========================================================================
  // Reference Model — CRC Computation using crc_pkg primitives
  // ===========================================================================
  function automatic logic [CRC_W-1:0] ref_crc_compute(crc_seq_item item);
    logic [CRC_W-1:0]  crc;
    logic [DATA_W-1:0] d;

    // Initialize CRC register
    crc = item.init_val;

    // Process each data byte
    for (int i = 0; i < item.data.size(); i++) begin
      // Optionally reflect input data
      d = item.reflect_in ? reflect_data(item.data[i]) : item.data[i];
      // XOR step
      crc = crc_step(crc, d, item.polynomial);
    end

    // Optionally reflect output CRC
    if (item.reflect_out)
      crc = reflect_crc(crc);

    // Final XOR
    crc = crc ^ item.final_xor;

    return crc;
  endfunction : ref_crc_compute

endclass : crc_scoreboard

`endif // CRC_SCOREBOARD_SV
