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
// CRC UVM Testbench — Environment
// =============================================================================
// Top-level UVM environment containing:
//   - crc_agent       (active)
//   - crc_scoreboard
//   - crc_coverage
//
// Analysis port connections:
//   agent.monitor.ap_in  -> scoreboard.ae_in
//   agent.monitor.ap_out -> scoreboard.ae_out
//   ap_context           -> scoreboard.ae_context
//   ap_context           -> coverage (via subscriber write())
// =============================================================================

`ifndef CRC_ENV_SV
`define CRC_ENV_SV

`include "uvm_macros.svh"

class crc_env extends uvm_env;

  import crc_pkg::*;

  `uvm_component_utils(crc_env)

  // Sub-components
  crc_agent       agent;
  crc_scoreboard  scoreboard;
  crc_coverage    coverage;

  // Broadcast analysis port for full context items.
  // Sequences write to this port after each item is sent; the env fans it
  // out to the scoreboard context FIFO and coverage collector.
  uvm_analysis_port #(crc_seq_item) ap_context;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    agent      = crc_agent::type_id::create      ("agent",      this);
    scoreboard = crc_scoreboard::type_id::create  ("scoreboard", this);
    coverage   = crc_coverage::type_id::create    ("coverage",   this);

    ap_context = new("ap_context", this);
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // connect_phase: wire analysis ports
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // Monitor input captures -> scoreboard input FIFO
    agent.monitor.ap_in.connect(scoreboard.ae_in);

    // Monitor output captures -> scoreboard output FIFO
    agent.monitor.ap_out.connect(scoreboard.ae_out);

    // Full-context items (with all config) -> scoreboard context FIFO
    ap_context.connect(scoreboard.ae_context);

    // Full-context items -> coverage collector
    ap_context.connect(coverage.analysis_export);
  endfunction : connect_phase

  // ---------------------------------------------------------------------------
  // start_of_simulation_phase
  // ---------------------------------------------------------------------------
  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info("ENV", "CRC UVM Environment topology:", UVM_MEDIUM)
    this.print();
  endfunction : start_of_simulation_phase

endclass : crc_env

`endif // CRC_ENV_SV
