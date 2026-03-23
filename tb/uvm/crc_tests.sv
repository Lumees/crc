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
// CRC UVM Testbench — Tests
// =============================================================================
// Test hierarchy:
//
//   crc_base_test      — builds env, prints topology
//     crc_directed_test — CRC-32 "123456789" + other directed vectors
//     crc_random_test   — 50 random CRC transactions
//     crc_stress_test   — 200 back-to-back short-message transactions
// =============================================================================

`ifndef CRC_TESTS_SV
`define CRC_TESTS_SV

`include "uvm_macros.svh"

// ============================================================================
// Base test
// ============================================================================
class crc_base_test extends uvm_test;

  import crc_pkg::*;

  `uvm_component_utils(crc_base_test)

  crc_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase: create environment
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = crc_env::type_id::create("env", this);
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // start_of_simulation_phase: print UVM topology
  // ---------------------------------------------------------------------------
  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info("TEST", "=== CRC UVM Testbench ===", UVM_NONE)
    `uvm_info("TEST", "UVM component topology:", UVM_MEDIUM)
    uvm_top.print_topology();
  endfunction : start_of_simulation_phase

  // ---------------------------------------------------------------------------
  // Helper: wire a sequence's context port to the env's ap_context
  // ---------------------------------------------------------------------------
  function void connect_seq_context(crc_base_seq seq);
    seq.ap_context = env.ap_context;
  endfunction : connect_seq_context

  // Default body (must be overridden)
  virtual task run_phase(uvm_phase phase);
    `uvm_warning("TEST", "crc_base_test::run_phase — no sequences run")
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // report_phase: print pass/fail summary
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    uvm_report_server svr;
    svr = uvm_report_server::get_server();
    if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) > 0)
      `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
    else
      `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
  endfunction : report_phase

endclass : crc_base_test


// ============================================================================
// Directed test
// ============================================================================
class crc_directed_test extends crc_base_test;

  `uvm_component_utils(crc_directed_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  virtual task run_phase(uvm_phase phase);
    crc_directed_seq dir_seq;

    phase.raise_objection(this, "crc_directed_test started");

    dir_seq = crc_directed_seq::type_id::create("dir_seq");
    connect_seq_context(dir_seq);

    `uvm_info("DIR_TEST", "Running directed CRC-32 sequences", UVM_MEDIUM)
    dir_seq.start(env.agent.sequencer);

    // Allow pipeline to drain
    #500ns;

    phase.drop_objection(this, "crc_directed_test complete");
  endtask : run_phase

endclass : crc_directed_test


// ============================================================================
// Random test (50 transactions)
// ============================================================================
class crc_random_test extends crc_base_test;

  `uvm_component_utils(crc_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  virtual task run_phase(uvm_phase phase);
    crc_random_seq rand_seq;

    phase.raise_objection(this, "crc_random_test started");

    rand_seq = crc_random_seq::type_id::create("rand_seq");
    connect_seq_context(rand_seq);
    rand_seq.num_transactions = 50;

    `uvm_info("RAND_TEST", "Running 50 random CRC transactions", UVM_MEDIUM)
    rand_seq.start(env.agent.sequencer);

    #500ns;
    phase.drop_objection(this, "crc_random_test complete");
  endtask : run_phase

endclass : crc_random_test


// ============================================================================
// Stress test (200 back-to-back transactions)
// ============================================================================
class crc_stress_test extends crc_base_test;

  `uvm_component_utils(crc_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // build_phase: suppress verbose logging during stress
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_report_verbosity_level_hier(UVM_MEDIUM);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    crc_stress_seq stress_seq;

    phase.raise_objection(this, "crc_stress_test started");

    stress_seq = crc_stress_seq::type_id::create("stress_seq");
    connect_seq_context(stress_seq);
    stress_seq.num_transactions = 200;

    `uvm_info("STRESS_TEST", "Running 200 back-to-back stress CRC transactions", UVM_MEDIUM)
    stress_seq.start(env.agent.sequencer);

    // Longer drain time for 200 transactions
    #2000ns;
    phase.drop_objection(this, "crc_stress_test complete");
  endtask : run_phase

endclass : crc_stress_test

`endif // CRC_TESTS_SV
