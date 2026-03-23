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
// CRC UVM Testbench — Sequence Item
// =============================================================================
// Represents one complete CRC computation (stimulus + response).
// =============================================================================

`ifndef CRC_SEQ_ITEM_SV
`define CRC_SEQ_ITEM_SV

`include "uvm_macros.svh"

class crc_seq_item extends uvm_sequence_item;

  import crc_pkg::*;

  `uvm_object_utils_begin(crc_seq_item)
    `uvm_field_array_int  (data,         UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (polynomial,   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (init_val,     UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (final_xor,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (reflect_in,   UVM_ALL_ON | UVM_BIN)
    `uvm_field_int        (reflect_out,  UVM_ALL_ON | UVM_BIN)
    `uvm_field_int        (expected_crc, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (actual_crc,   UVM_ALL_ON | UVM_HEX)
  `uvm_object_utils_end

  // -------------------------------------------------------------------------
  // Stimulus fields (randomised)
  // -------------------------------------------------------------------------
  rand logic [DATA_W-1:0] data [];         // data bytes array
  rand logic [CRC_W-1:0]  polynomial;      // CRC polynomial
  rand logic [CRC_W-1:0]  init_val;        // initial CRC value
  rand logic [CRC_W-1:0]  final_xor;       // final XOR mask
  rand logic               reflect_in;      // reflect input data bits
  rand logic               reflect_out;     // reflect output CRC bits

  // -------------------------------------------------------------------------
  // Expected and actual result fields
  // -------------------------------------------------------------------------
  logic [CRC_W-1:0]       expected_crc;    // computed by scoreboard reference
  logic [CRC_W-1:0]       actual_crc;      // captured from DUT crc_o

  // -------------------------------------------------------------------------
  // Constraints
  // -------------------------------------------------------------------------

  // Data length: between 1 and 256 bytes
  constraint c_data_len {
    data.size() inside {[1:256]};
    data.size() dist { [1:4] := 20, [5:16] := 40, [17:64] := 30, [65:256] := 10 };
  }

  // Polynomial: common CRC-32 polynomials weighted heavier
  constraint c_polynomial {
    polynomial dist {
      32'h04C11DB7 := 40,   // CRC-32 Ethernet
      32'h1EDC6F41 := 20,   // CRC-32C (Castagnoli)
      32'hA833982B := 10,   // CRC-32Q
      [32'h1 : 32'hFFFF_FFFE] := 30
    };
  }

  // Init value distribution
  constraint c_init_val {
    init_val dist {
      {CRC_W{1'b1}} := 40,
      {CRC_W{1'b0}} := 30,
      [1 : {CRC_W{1'b1}}-1] := 30
    };
  }

  // Final XOR distribution
  constraint c_final_xor {
    final_xor dist {
      {CRC_W{1'b1}} := 40,
      {CRC_W{1'b0}} := 40,
      [1 : {CRC_W{1'b1}}-1] := 20
    };
  }

  // Reflect bits: equal probability
  constraint c_reflect_in {
    reflect_in dist { 1'b0 := 50, 1'b1 := 50 };
  }

  constraint c_reflect_out {
    reflect_out dist { 1'b0 := 50, 1'b1 := 50 };
  }

  // Polynomial must not be zero
  constraint c_poly_nonzero {
    polynomial != '0;
  }

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "crc_seq_item");
    super.new(name);
  endfunction : new

  // -------------------------------------------------------------------------
  // Convenience: build a crc_config_t from this item's fields
  // -------------------------------------------------------------------------
  function crc_config_t get_config();
    crc_config_t cfg;
    cfg.polynomial  = polynomial;
    cfg.init_val    = init_val;
    cfg.final_xor   = final_xor;
    cfg.reflect_in  = reflect_in;
    cfg.reflect_out = reflect_out;
    return cfg;
  endfunction : get_config

  // Short printable summary
  function string convert2string();
    return $sformatf(
      "CRC | poly=%h init=%h xor=%h ref_in=%0b ref_out=%0b | len=%0d | exp=%h act=%h",
      polynomial,
      init_val,
      final_xor,
      reflect_in,
      reflect_out,
      data.size(),
      expected_crc,
      actual_crc
    );
  endfunction : convert2string

endclass : crc_seq_item

`endif // CRC_SEQ_ITEM_SV
