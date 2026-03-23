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
// CRC UVM Testbench — Agent
// =============================================================================
// Active UVM agent containing:
//   - crc_driver    (active mode only)
//   - crc_monitor   (always present)
//   - uvm_sequencer (active mode only)
//
// The agent is active by default (is_active = UVM_ACTIVE).
// Pass UVM_PASSIVE via uvm_config_db to disable the driver/sequencer.
//
// Virtual interface is retrieved from config_db and forwarded to child components.
// =============================================================================

`ifndef CRC_AGENT_SV
`define CRC_AGENT_SV

`include "uvm_macros.svh"

class crc_agent extends uvm_agent;

  import crc_pkg::*;

  `uvm_component_utils(crc_agent)

  // Child components
  crc_driver                     driver;
  crc_monitor                    monitor;
  uvm_sequencer #(crc_seq_item)  sequencer;

  // Virtual interface stored here for convenience
  virtual crc_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Retrieve virtual interface
    if (!uvm_config_db #(virtual crc_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "crc_agent: cannot get virtual interface from config_db")

    // Always build monitor
    monitor = crc_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      driver    = crc_driver::type_id::create("driver",    this);
      sequencer = uvm_sequencer #(crc_seq_item)::type_id::create("sequencer", this);
    end
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // connect_phase: wire driver sequencer port; propagate vif to children
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // Push vif down to sub-components via config_db
    uvm_config_db #(virtual crc_if)::set(this, "driver",  "vif", vif);
    uvm_config_db #(virtual crc_if)::set(this, "monitor", "vif", vif);

    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction : connect_phase

  // ---------------------------------------------------------------------------
  // start_of_simulation_phase: print topology
  // ---------------------------------------------------------------------------
  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info("AGENT",
      $sformatf("crc_agent is %s",
        (get_is_active() == UVM_ACTIVE) ? "ACTIVE" : "PASSIVE"),
      UVM_MEDIUM)
  endfunction : start_of_simulation_phase

endclass : crc_agent

`endif // CRC_AGENT_SV
