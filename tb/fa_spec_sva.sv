`timescale 1ns / 1ps
`include "fa_cover.svh"
//==============================================================================
// fa_spec_sva -- black-box assertions (DUT ports only), bound to frame_aligner
//------------------------------------------------------------------------------
//  Every property is a direct statement of a specification rule (R1..R7, see
//  tb/fa_ref_model.sv), so the checker is independent of the RTL structure and
//  applies to any implementation.  Failures are reported through
//  fa_pkg::fa_sva_fail() and are counted in the final verdict.
//
//  Sampling reminder: at a rising edge the properties see the values stable
//  just before the edge.  fr_byte_position / frame_detect sampled at edge t
//  describe the byte sampled on rx_data at edge t-1, i.e. $past(rx_data, 1).
//
//  Legacy assertions replaced (see docs/BUG_REPORT.md, TB-07):
//    * check_frame_detect_after_3_headers used ##0 between frames (sequence
//      fusion: frame 2 would have to start on the last byte of frame 1), so it
//      almost never matched and its consequent timing was also wrong;
//    * fr_byte_position_not_reset_when_above_2 fails on every pair of
//      back-to-back frames (11 -> 0 is the normal frame boundary);
//    * check_frame_detect_reset required fr_byte_position <= 2 for 56 cycles
//      after alignment, which is false as soon as the payload continues.
//  SVA note: repetition ([*n]) is only used in antecedents; some tools do
//  not evaluate repetition in a consequent correctly.
//==============================================================================
module fa_spec_sva (
  input logic       clk,
  input logic       reset,
  input logic [7:0] rx_data,
  input logic [3:0] fr_byte_position,
  input logic       frame_detect
);
  import fa_pkg::*;

  // True when l, m form a valid header (R1).
  function automatic bit is_hdr(logic [7:0] l, logic [7:0] m);
    return (l == 8'hAA && m == 8'hAF) || (l == 8'h55 && m == 8'hBA);
  endfunction

  sequence s_hdr;
    (rx_data == 8'hAA ##1 rx_data == 8'hAF) or (rx_data == 8'h55 ##1 rx_data == 8'hBA);
  endsequence

  sequence s_frame;                     // 12 consecutive bytes starting with a header
    s_hdr ##1 1'b1 [*10];
  endsequence

  // Auxiliary: number of consecutive samples (including the current one) in
  // which fr_byte_position == 0, i.e. the aligner was hunting (R6).
  logic [7:0] zrun_q;
  wire  [7:0] zrun = (fr_byte_position == 4'd0) ? ((zrun_q == 8'hFF) ? 8'hFF : zrun_q + 8'd1) : 8'd0;
  always @(posedge clk or posedge reset)
    if (reset) zrun_q <= 8'd0;
    else       zrun_q <= zrun;

  //---------------------------------------------------------------------------
  // Signal integrity
  //---------------------------------------------------------------------------
  SPEC_OUT_KNOWN: assert property (@(posedge clk) !$isunknown({frame_detect, fr_byte_position}))
    else fa_sva_fail("SPEC_OUT_KNOWN", "X/Z on frame_detect / fr_byte_position");

  // Stimulus sanity (a testbench rule: the legacy tests drove X on rx_data).
  TB_IN_KNOWN: assert property (@(posedge clk) disable iff (reset) !$isunknown(rx_data))
    else fa_sva_fail("TB_IN_KNOWN", "X/Z driven on rx_data");

  // R7: asynchronous reset forces both outputs to 0.
  SPEC_RESET_VALUES: assert property (@(posedge clk) reset |-> (frame_detect == 1'b0 && fr_byte_position == 4'd0))
    else fa_sva_fail("SPEC_RESET_VALUES", "outputs not 0 while reset is asserted");

  //---------------------------------------------------------------------------
  // fr_byte_position (R3, R6)
  //---------------------------------------------------------------------------
  SPEC_POS_RANGE: assert property (@(posedge clk) disable iff (reset) fr_byte_position <= 4'd11)
    else fa_sva_fail("SPEC_POS_RANGE", $sformatf("fr_byte_position=%0d outside 0..11", fr_byte_position));

  // Inside a frame the position advances by one per byte.  (Fails on DUT-03:
  // after a rejected header the DUT shows 1 and then 0.)
  SPEC_POS_INCREMENT: assert property (@(posedge clk) disable iff (reset)
      fr_byte_position inside {[4'd1:4'd10]} |=> fr_byte_position == $past(fr_byte_position) + 4'd1)
    else fa_sva_fail("SPEC_POS_INCREMENT", "position inside a frame did not advance by one");

  // After the last payload byte the next byte is a header LSB or a hunting byte.
  SPEC_POS_AFTER_FRAME: assert property (@(posedge clk) disable iff (reset)
      fr_byte_position == 4'd11 |=> fr_byte_position == 4'd0)
    else fa_sva_fail("SPEC_POS_AFTER_FRAME", "position after a complete frame is not 0");

  SPEC_POS_FROM_ZERO: assert property (@(posedge clk) disable iff (reset)
      fr_byte_position == 4'd0 |=> fr_byte_position inside {4'd0, 4'd1})
    else fa_sva_fail("SPEC_POS_FROM_ZERO", "position jumped from 0 to a value other than 0/1");

  // Position 1 ("header MSB") is reported only after a real header (R1, R6).
  SPEC_POS1_AFTER_HEADER: assert property (@(posedge clk) disable iff (reset)
      fr_byte_position == 4'd1 |-> is_hdr($past(rx_data, 2), $past(rx_data, 1)))
    else fa_sva_fail("SPEC_POS1_AFTER_HEADER", $sformatf("position 1 reported after bytes %02h %02h, which are not a header",
                                                         $past(rx_data, 2), $past(rx_data, 1)));

  //---------------------------------------------------------------------------
  // frame_detect: alignment gained (R4)
  //---------------------------------------------------------------------------
  // Alignment rises one byte after the 3rd header MSB, i.e. on payload byte 0.
  SPEC_FD_RISE_POSITION: assert property (@(posedge clk) disable iff (reset)
      $rose(frame_detect) |-> fr_byte_position == 4'd2)
    else fa_sva_fail("SPEC_FD_RISE_POSITION", $sformatf("frame_detect rose at position %0d (expected 2)", fr_byte_position));

  // ... and only after three consecutive frames (positions 1..11, 1..11, 1).
  SPEC_FD_RISE_3_FRAMES: assert property (@(posedge clk) disable iff (reset)
      $rose(frame_detect) |-> ($past(fr_byte_position, 1)  == 4'd1  && $past(fr_byte_position, 3)  == 4'd11 &&
                               $past(fr_byte_position, 13) == 4'd1  && $past(fr_byte_position, 15) == 4'd11 &&
                               $past(fr_byte_position, 25) == 4'd1))
    else fa_sva_fail("SPEC_FD_RISE_3_FRAMES", "frame_detect rose without three consecutive frames");

  // Three consecutive frames starting where a header may start (hunting or at
  // a frame boundary) must leave the aligner aligned.  (Fails on DUT-01 when
  // the first header follows a stray LSB.)
  SPEC_SYNC_AFTER_3_FRAMES: assert property (@(posedge clk) disable iff (reset)
      (fr_byte_position inside {4'd0, 4'd11}) ##0 s_frame ##1 s_frame ##1 s_frame |=> frame_detect)
    else fa_sva_fail("SPEC_SYNC_AFTER_3_FRAMES", "three consecutive frames did not produce alignment");

  //---------------------------------------------------------------------------
  // frame_detect: alignment lost (R5)
  //---------------------------------------------------------------------------
  // The byte that drops alignment is a hunting byte (never a header MSB or a
  // payload byte).  (Fails on DUT-02.)
  SPEC_FD_FALL_WHILE_HUNTING: assert property (@(posedge clk) disable iff (reset)
      $fell(frame_detect) |-> fr_byte_position == 4'd0)
    else fa_sva_fail("SPEC_FD_FALL_WHILE_HUNTING",
                     $sformatf("frame_detect fell at position %0d, i.e. inside a validated header/frame", fr_byte_position));

  // ... and it is the 48th consecutive hunting byte.
  SPEC_FD_FALL_AFTER_48: assert property (@(posedge clk) disable iff (reset)
      $fell(frame_detect) |-> zrun >= 8'd48)
    else fa_sva_fail("SPEC_FD_FALL_AFTER_48", $sformatf("frame_detect fell after only %0d hunting bytes", zrun));

  // Alignment never drops while a frame is being received.
  SPEC_FD_HOLD_IN_FRAME: assert property (@(posedge clk) disable iff (reset)
      frame_detect && fr_byte_position inside {[4'd1:4'd11]} |=> frame_detect)
    else fa_sva_fail("SPEC_FD_HOLD_IN_FRAME", "frame_detect fell on a byte of a validated frame");

  //---------------------------------------------------------------------------
  // Coverage of the interesting antecedents (proves the checks are not vacuous)
  //---------------------------------------------------------------------------
  `FA_COVER(C_SYNC_GAINED, $rose(frame_detect))
  `FA_COVER(C_SYNC_LOST, $fell(frame_detect))
  `FA_COVER(C_THREE_FRAMES, (fr_byte_position inside {4'd0, 4'd11}) ##0 s_frame ##1 s_frame ##1 s_frame)
  `FA_COVER(C_RESTART, (rx_data inside {8'hAA, 8'h55}) ##1 (rx_data inside {8'hAA, 8'h55}) ##1 s_hdr)
  `FA_COVER(C_POS_11, fr_byte_position == 4'd11)
  `FA_COVER(C_LONG_HUNT, zrun == 8'd48)
  `FA_COVER(C_POS1_CHECKED, fr_byte_position == 4'd1)

endmodule
