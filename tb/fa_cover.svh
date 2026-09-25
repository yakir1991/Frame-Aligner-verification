//==============================================================================
// fa_cover.svh -- portable cover-property macro for the assertion modules
//------------------------------------------------------------------------------
//  `FA_COVER(label, seq) counts every match of sequence 'seq' in
//  fa_pkg::fa_sva_cover_count["label"] so the final report can show that each
//  assertion antecedent was really exercised (non-vacuous checking).
//
//  Commercial simulators: a normal cover property with a pass statement.
//  Some tools (e.g. Verilator 5.x) never execute cover-property pass statements; there the
//  match is counted through the failure action of the negated sequence
//  (assert property (not seq) fails exactly when seq matches).
//  The macros expect 'clk' and 'reset' signals in the enclosing module.
//==============================================================================
`ifndef FA_COVER_SVH
`define FA_COVER_SVH
`ifdef VERILATOR
  `define FA_COVER(label, seq) \
    label: assert property (@(posedge clk) disable iff (reset) not (seq)) else fa_pkg::fa_sva_cover(`"label`");
`else
  `define FA_COVER(label, seq) \
    label: cover property (@(posedge clk) disable iff (reset) (seq)) fa_pkg::fa_sva_cover(`"label`");
`endif
`endif
