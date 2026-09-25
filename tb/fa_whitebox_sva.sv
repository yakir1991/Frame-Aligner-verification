`timescale 1ns / 1ps
`include "fa_cover.svh"
//==============================================================================
// fa_whitebox_sva -- white-box assertions on the DUT internals
//------------------------------------------------------------------------------
//  Bound to every frame_aligner instance (tb/tb_top.sv).  These properties
//  check the micro-architecture described in the spec's design slides (FSM,
//  counters, triggers) and pin-point defects at their root cause, one cycle
//  after they happen, even when the effect is not (yet) visible on the ports:
//    WB_LEGAL_NO_WRAP and WB_NA_NO_WRAP catch the latent counter wrap-arounds
//    DUT-04 and DUT-05, which the port-level checks cannot see.
//  Both the original and the corrected RTL use the same internal names.
//==============================================================================
module fa_whitebox_sva (
  input logic       clk,
  input logic       reset,
  input logic [7:0] rx_data,
  input logic [3:0] fr_byte_position,
  input logic       frame_detect,
  input logic [1:0] current_state,
  input logic [1:0] legal_frame_counter,
  input logic [5:0] na_byte_counter,
  input logic [7:0] header_lsb_samp,
  input logic       header_lsb_valid,
  input logic       header_msb_valid,
  input logic       fr_byte_position_rst,
  input logic       na_byte_count_inc,
  input logic       na_byte_count_rst,
  input logic       legal_frame_counter_rst,
  input logic       legal_frame_counter_inc
);
  import fa_pkg::*;

  localparam logic [1:0] FR_IDLE = 2'b00, FR_HLSB = 2'b01, FR_HMSB = 2'b10, FR_DATA = 2'b11;

  //---------------------------------------------------------------------------
  // FSM structure (spec FSM slide)
  //---------------------------------------------------------------------------
  WB_STATE_KNOWN: assert property (@(posedge clk) disable iff (reset) !$isunknown(current_state))
    else fa_sva_fail("WB_STATE_KNOWN", "FSM state is X/Z");

  WB_HMSB_TO_DATA: assert property (@(posedge clk) disable iff (reset)
      current_state == FR_HMSB |=> current_state == FR_DATA)
    else fa_sva_fail("WB_HMSB_TO_DATA", "FR_HMSB not followed by FR_DATA");

  WB_HLSB_ENTRY: assert property (@(posedge clk) disable iff (reset)
      current_state == FR_HLSB |-> $past(header_lsb_valid))
    else fa_sva_fail("WB_HLSB_ENTRY", "FR_HLSB entered without a header LSB");

  WB_DATA_POSITION: assert property (@(posedge clk) disable iff (reset)
      current_state == FR_DATA |-> fr_byte_position inside {[4'd2:4'd10]})
    else fa_sva_fail("WB_DATA_POSITION", $sformatf("FR_DATA with fr_byte_position=%0d", $sampled(fr_byte_position)));

  WB_TRIGGERS_EXCLUSIVE: assert property (@(posedge clk) disable iff (reset)
      !(legal_frame_counter_rst && legal_frame_counter_inc) && !(na_byte_count_rst && na_byte_count_inc))
    else fa_sva_fail("WB_TRIGGERS_EXCLUSIVE", "counter reset and increment requested together");

  WB_LSB_SAMP_LEGAL: assert property (@(posedge clk) disable iff (reset)
      header_lsb_samp inside {8'h00, 8'hAA, 8'h55})
    else fa_sva_fail("WB_LSB_SAMP_LEGAL", $sformatf("header_lsb_samp=%02h", $sampled(header_lsb_samp)));

  //---------------------------------------------------------------------------
  // Root-cause checks for the defects found by verification
  //---------------------------------------------------------------------------
  // DUT-01: a rejected MSB that is itself a header LSB must start a new
  // header candidate (stay in FR_HLSB).
  WB_DUT01_NO_LOST_LSB: assert property (@(posedge clk) disable iff (reset)
      current_state == FR_HLSB && !header_msb_valid && header_lsb_valid |=> current_state == FR_HLSB)
    else fa_sva_fail("WB_DUT01_NO_LOST_LSB", "header LSB after a rejected MSB was discarded (DUT-01)");

  // DUT-02: alignment must not be cleared on the byte that completes a valid
  // header, nor while the payload of a validated frame is received.
  WB_DUT02_NO_CLEAR_IN_FRAME: assert property (@(posedge clk) disable iff (reset)
      frame_detect && ((current_state == FR_HLSB && header_msb_valid) || current_state == FR_HMSB ||
                       current_state == FR_DATA) |=> frame_detect)
    else fa_sva_fail("WB_DUT02_NO_CLEAR_IN_FRAME", "frame_detect cleared by a valid header / frame byte (DUT-02)");

  // DUT-03: after a rejected header no frame position may be reported.
  WB_DUT03_POS_RESET_ON_REJECT: assert property (@(posedge clk) disable iff (reset)
      current_state == FR_HLSB && !header_msb_valid |=> fr_byte_position == 4'd0)
    else fa_sva_fail("WB_DUT03_POS_RESET_ON_REJECT", "fr_byte_position not 0 after a rejected header (DUT-03)");

  // DUT-04: the consecutive-frame counter must saturate, not wrap 3 -> 0.
  WB_DUT04_LEGAL_NO_WRAP: assert property (@(posedge clk) disable iff (reset)
      legal_frame_counter == 2'd3 && !legal_frame_counter_rst |=> legal_frame_counter == 2'd3)
    else fa_sva_fail("WB_DUT04_LEGAL_NO_WRAP", "legal_frame_counter wrapped from 3 (DUT-04)");

  // DUT-05: the not-aligned byte counter must saturate, not wrap 63 -> 0.
  WB_DUT05_NA_NO_WRAP: assert property (@(posedge clk) disable iff (reset)
      na_byte_counter == 6'd63 && !na_byte_count_rst |=> na_byte_counter == 6'd63)
    else fa_sva_fail("WB_DUT05_NA_NO_WRAP", "na_byte_counter wrapped from 63 (DUT-05)");

  // Coverage of the root-cause antecedents
  `FA_COVER(C_WB_RESTART_CASE, current_state == FR_HLSB && !header_msb_valid && header_lsb_valid)
  `FA_COVER(C_WB_VALID_HDR_IN_SYNC, frame_detect && current_state == FR_HLSB && header_msb_valid)
  `FA_COVER(C_WB_REJECT, current_state == FR_HLSB && !header_msb_valid)
  `FA_COVER(C_WB_LEGAL_AT_3, legal_frame_counter == 2'd3 && legal_frame_counter_inc)
  `FA_COVER(C_WB_NA_AT_63, na_byte_counter == 6'd63 && na_byte_count_inc)

endmodule
