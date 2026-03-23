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
// CRC UVM Testbench — Functional Coverage Collector
// =============================================================================
// Subscribes to the output monitor analysis port (via context items).
// Covergroups:
//   cg_crc  : crc_width x reflect_in x reflect_out x data_length (with cross)
// =============================================================================

`ifndef CRC_COVERAGE_SV
`define CRC_COVERAGE_SV

`include "uvm_macros.svh"

class crc_coverage extends uvm_subscriber #(crc_seq_item);

  import crc_pkg::*;

  `uvm_component_utils(crc_coverage)

  // Current sampled item fields (written in write() before sampling)
  logic [CRC_W-1:0] cov_polynomial;
  logic              cov_reflect_in;
  logic              cov_reflect_out;
  int unsigned       cov_data_length;
  logic [CRC_W-1:0] cov_init_val;
  logic [CRC_W-1:0] cov_final_xor;

  // ---------------------------------------------------------------------------
  // Covergroup: CRC configuration space
  // ---------------------------------------------------------------------------
  covergroup cg_crc;
    option.per_instance = 1;
    option.name         = "cg_crc";
    option.comment      = "CRC configuration and data length coverage";

    cp_polynomial: coverpoint cov_polynomial {
      bins crc32_eth   = {32'h04C11DB7};
      bins crc32c      = {32'h1EDC6F41};
      bins crc32q      = {32'hA833982B};
      bins other       = default;
    }

    cp_reflect_in: coverpoint cov_reflect_in {
      bins off = {1'b0};
      bins on  = {1'b1};
    }

    cp_reflect_out: coverpoint cov_reflect_out {
      bins off = {1'b0};
      bins on  = {1'b1};
    }

    cp_data_length: coverpoint cov_data_length {
      bins single_byte = {1};
      bins short_msg   = {[2:8]};
      bins medium_msg  = {[9:64]};
      bins long_msg    = {[65:256]};
    }

    cp_init_val: coverpoint cov_init_val {
      bins all_zeros = {0};
      bins all_ones  = {{CRC_W{1'b1}}};
      bins other     = default;
    }

    cp_final_xor: coverpoint cov_final_xor {
      bins all_zeros = {0};
      bins all_ones  = {{CRC_W{1'b1}}};
      bins other     = default;
    }

    // Cross: reflect_in x reflect_out (all 4 combinations)
    cx_reflect: cross cp_reflect_in, cp_reflect_out;

    // Cross: reflect_in x reflect_out x data_length
    cx_reflect_len: cross cp_reflect_in, cp_reflect_out, cp_data_length;

    // Cross: polynomial x reflect_in x reflect_out
    cx_poly_reflect: cross cp_polynomial, cp_reflect_in, cp_reflect_out;
  endgroup : cg_crc

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_crc = new();
  endfunction : new

  // ---------------------------------------------------------------------------
  // write(): called by analysis port on each context transaction
  // ---------------------------------------------------------------------------
  function void write(crc_seq_item t);
    cov_polynomial  = t.polynomial;
    cov_reflect_in  = t.reflect_in;
    cov_reflect_out = t.reflect_out;
    cov_data_length = t.data.size();
    cov_init_val    = t.init_val;
    cov_final_xor   = t.final_xor;

    cg_crc.sample();

    `uvm_info("COV",
      $sformatf("Sampled: poly=%h ref_in=%0b ref_out=%0b len=%0d",
        cov_polynomial, cov_reflect_in, cov_reflect_out, cov_data_length),
      UVM_DEBUG)
  endfunction : write

  // ---------------------------------------------------------------------------
  // report_phase: print coverage summary
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info("COV_REPORT",
      $sformatf("cg_crc coverage: %.2f%%", cg_crc.get_coverage()),
      UVM_NONE)
  endfunction : report_phase

endclass : crc_coverage

`endif // CRC_COVERAGE_SV
