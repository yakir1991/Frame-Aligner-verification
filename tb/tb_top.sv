`timescale 1ns / 1ps
//==============================================================================
// tb_top -- top-level testbench module
//------------------------------------------------------------------------------
//  * generates the 100 MHz byte clock (reset is owned by the driver so that
//    tests can reset the DUT in mid-stream)
//  * instantiates the interface, the DUT and the test program
//  * binds the assertion modules into every frame_aligner instance:
//      fa_spec_sva     : black-box, uses only the DUT ports (spec rules)
//      fa_whitebox_sva : white-box, uses DUT internals (FSM and counters);
//                        the original and the fixed RTL share these names
//  * +DUMP writes waves.vcd (Verilator: build with --trace)
//
//  Which RTL is simulated is chosen at compile time by the file list
//  (sim/Makefile: DUT=orig -> rtl/frame_aligner.sv,
//                 DUT=fixed -> rtl/frame_aligner_fixed.sv).
//==============================================================================
module tb_top;

  bit clk = 1'b0;
  always #5 clk = ~clk;

  frame_inf vif (clk);

  frame_aligner dut (
    .clk              (clk),
    .reset            (vif.reset),
    .rx_data          (vif.rx_data),
    .fr_byte_position (vif.fr_byte_position),
    .frame_detect     (vif.frame_detect)
  );

  // Assertions are attached to the module type, so they follow the DUT into
  // any hierarchy (the legacy bind used an instance name plus upward
  // references into the testbench and was not elaborated by every tool).
  bind frame_aligner fa_spec_sva u_spec_sva (
    .clk (clk), .reset (reset), .rx_data (rx_data),
    .fr_byte_position (fr_byte_position), .frame_detect (frame_detect));

  bind frame_aligner fa_whitebox_sva u_whitebox_sva (
    .clk (clk), .reset (reset), .rx_data (rx_data),
    .fr_byte_position (fr_byte_position), .frame_detect (frame_detect),
    .current_state (current_state), .legal_frame_counter (legal_frame_counter),
    .na_byte_counter (na_byte_counter), .header_lsb_samp (header_lsb_samp),
    .header_lsb_valid (header_lsb_valid), .header_msb_valid (header_msb_valid),
    .fr_byte_position_rst (fr_byte_position_rst),
    .na_byte_count_inc (na_byte_count_inc), .na_byte_count_rst (na_byte_count_rst),
    .legal_frame_counter_rst (legal_frame_counter_rst),
    .legal_frame_counter_inc (legal_frame_counter_inc));

  fa_test test (vif);

  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
