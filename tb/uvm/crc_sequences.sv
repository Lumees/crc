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
// CRC UVM Testbench — Sequences
// =============================================================================
// All sequences in one file. Each sequence:
//   1. Randomises (or hard-codes) a seq_item
//   2. Starts it on the sequencer
//   3. Writes the full item to env.ap_context so the scoreboard reference
//      model has all configuration fields available.
//
// Sequences access ap_context through a direct handle set in the test's
// build_phase.
// =============================================================================

`ifndef CRC_SEQUENCES_SV
`define CRC_SEQUENCES_SV

`include "uvm_macros.svh"

// ============================================================================
// Base sequence
// ============================================================================
class crc_base_seq extends uvm_sequence #(crc_seq_item);

  import crc_pkg::*;

  `uvm_object_utils(crc_base_seq)

  // Handle to the env's context analysis port — set by test before starting
  uvm_analysis_port #(crc_seq_item) ap_context;

  function new(string name = "crc_base_seq");
    super.new(name);
  endfunction : new

  // Helper: send one item and publish context
  task send_item(crc_seq_item item);
    start_item(item);
    if (!item.randomize())
      `uvm_fatal("SEQ_RAND", "Failed to randomise seq_item")
    finish_item(item);

    // Publish full item so scoreboard reference model has config
    if (ap_context != null)
      ap_context.write(item);
    else
      `uvm_warning("SEQ_CTX", "ap_context handle is null — scoreboard may not have config")
  endtask : send_item

  // Helper: send a pre-built (non-randomised) item directly
  task send_fixed_item(crc_seq_item item);
    start_item(item);
    finish_item(item);
    if (ap_context != null)
      ap_context.write(item);
    else
      `uvm_warning("SEQ_CTX", "ap_context handle is null — scoreboard may not have config")
  endtask : send_fixed_item

  virtual task body();
    `uvm_warning("SEQ", "crc_base_seq::body() called — override in derived class")
  endtask : body

endclass : crc_base_seq


// ============================================================================
// Directed CRC-32 sequence (standard check value: CRC32("123456789") = 0xCBF43926)
// ============================================================================
class crc_directed_seq extends crc_base_seq;

  `uvm_object_utils(crc_directed_seq)

  function new(string name = "crc_directed_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    crc_seq_item item;

    // ----------------------------------------------------------------
    // CRC-32/ISO-HDLC (Ethernet): "123456789" -> 0xCBF43926
    // poly=0x04C11DB7, init=0xFFFFFFFF, xorout=0xFFFFFFFF,
    // refin=true, refout=true
    // ----------------------------------------------------------------
    item = crc_seq_item::type_id::create("crc32_check");
    item.polynomial  = 32'h04C11DB7;
    item.init_val    = 32'hFFFF_FFFF;
    item.final_xor   = 32'hFFFF_FFFF;
    item.reflect_in  = 1'b1;
    item.reflect_out = 1'b1;
    // ASCII "123456789" = {0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39}
    item.data = new[9];
    item.data[0] = 8'h31;
    item.data[1] = 8'h32;
    item.data[2] = 8'h33;
    item.data[3] = 8'h34;
    item.data[4] = 8'h35;
    item.data[5] = 8'h36;
    item.data[6] = 8'h37;
    item.data[7] = 8'h38;
    item.data[8] = 8'h39;
    item.expected_crc = 32'hCBF43926;
    `uvm_info("SEQ_DIR", "Sending CRC-32 Ethernet check value: \"123456789\"", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // CRC-32/ISO-HDLC: single byte 0x00
    // ----------------------------------------------------------------
    item = crc_seq_item::type_id::create("crc32_single");
    item.polynomial  = 32'h04C11DB7;
    item.init_val    = 32'hFFFF_FFFF;
    item.final_xor   = 32'hFFFF_FFFF;
    item.reflect_in  = 1'b1;
    item.reflect_out = 1'b1;
    item.data = new[1];
    item.data[0] = 8'h00;
    `uvm_info("SEQ_DIR", "Sending CRC-32 Ethernet: single byte 0x00", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // CRC-32C (Castagnoli): "123456789" -> 0xE3069283
    // poly=0x1EDC6F41, init=0xFFFFFFFF, xorout=0xFFFFFFFF,
    // refin=true, refout=true
    // ----------------------------------------------------------------
    item = crc_seq_item::type_id::create("crc32c_check");
    item.polynomial  = 32'h1EDC6F41;
    item.init_val    = 32'hFFFF_FFFF;
    item.final_xor   = 32'hFFFF_FFFF;
    item.reflect_in  = 1'b1;
    item.reflect_out = 1'b1;
    item.data = new[9];
    item.data[0] = 8'h31;
    item.data[1] = 8'h32;
    item.data[2] = 8'h33;
    item.data[3] = 8'h34;
    item.data[4] = 8'h35;
    item.data[5] = 8'h36;
    item.data[6] = 8'h37;
    item.data[7] = 8'h38;
    item.data[8] = 8'h39;
    item.expected_crc = 32'hE3069283;
    `uvm_info("SEQ_DIR", "Sending CRC-32C Castagnoli check value: \"123456789\"", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // CRC-32 with no reflection: "123456789"
    // poly=0x04C11DB7, init=0xFFFFFFFF, xorout=0xFFFFFFFF,
    // refin=false, refout=false
    // (CRC-32/MPEG-2 with final_xor=0xFFFFFFFF instead of 0x00000000)
    // ----------------------------------------------------------------
    item = crc_seq_item::type_id::create("crc32_noref");
    item.polynomial  = 32'h04C11DB7;
    item.init_val    = 32'hFFFF_FFFF;
    item.final_xor   = 32'h0000_0000;
    item.reflect_in  = 1'b0;
    item.reflect_out = 1'b0;
    item.data = new[9];
    item.data[0] = 8'h31;
    item.data[1] = 8'h32;
    item.data[2] = 8'h33;
    item.data[3] = 8'h34;
    item.data[4] = 8'h35;
    item.data[5] = 8'h36;
    item.data[6] = 8'h37;
    item.data[7] = 8'h38;
    item.data[8] = 8'h39;
    `uvm_info("SEQ_DIR", "Sending CRC-32/MPEG-2 check value: \"123456789\"", UVM_MEDIUM)
    send_fixed_item(item);

  endtask : body

endclass : crc_directed_seq


// ============================================================================
// Random sequence
// ============================================================================
class crc_random_seq extends crc_base_seq;

  `uvm_object_utils(crc_random_seq)

  int unsigned num_transactions = 20;

  function new(string name = "crc_random_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    crc_seq_item item;

    repeat (num_transactions) begin
      item = crc_seq_item::type_id::create("rand_crc");
      send_item(item);
    end

    `uvm_info("SEQ_RAND",
      $sformatf("Completed %0d random CRC transactions", num_transactions),
      UVM_MEDIUM)
  endtask : body

endclass : crc_random_seq


// ============================================================================
// Stress sequence (back-to-back transactions, no idle cycles between items)
// ============================================================================
class crc_stress_seq extends crc_base_seq;

  `uvm_object_utils(crc_stress_seq)

  int unsigned num_transactions = 100;

  function new(string name = "crc_stress_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    crc_seq_item item;

    repeat (num_transactions) begin
      item = crc_seq_item::type_id::create("stress_crc");
      start_item(item);
      // Constrain to short messages for rapid back-to-back
      if (!item.randomize() with { data.size() inside {[1:16]}; })
        `uvm_fatal("SEQ_RAND", "Failed to randomise stress seq_item")
      finish_item(item);
      if (ap_context != null) ap_context.write(item);
    end

    `uvm_info("SEQ_STRESS",
      $sformatf("Completed %0d back-to-back stress CRC transactions", num_transactions),
      UVM_MEDIUM)
  endtask : body

endclass : crc_stress_seq

`endif // CRC_SEQUENCES_SV
