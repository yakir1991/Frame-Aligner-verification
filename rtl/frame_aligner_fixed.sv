`timescale 1ns / 1ps
//==============================================================================
// frame_aligner  --  CORRECTED REFERENCE IMPLEMENTATION
//------------------------------------------------------------------------------
//  This is the original design (rtl/frame_aligner.sv) with the defects found by
//  verification repaired.  It keeps the same module name, ports, state encoding
//  and internal signal names so that:
//    * the same testbench runs on either implementation
//      (make sim DUT=orig | make sim DUT=fixed), and
//    * the same white-box assertion module binds to both.
//
//  Every change is tagged "FIX DUT-0x" and matches an entry in
//  docs/BUG_REPORT.md.  Untagged lines are functionally identical to the original.
//
//  Behaviour summary (the verification reference model implements the same
//  rules independently, see tb/fa_ref_model.sv):
//    * Header search never loses a header LSB (FIX DUT-01).
//    * Sync is lost on the 48th consecutive byte that is NOT part of a
//      validated header.  A header completed within those 48 bytes keeps sync,
//      and sync is never dropped while a validated frame is being received
//      (FIX DUT-02).
//    * fr_byte_position is 0 whenever the aligner is not inside a validated
//      frame (FIX DUT-03).
//    * Counters saturate instead of wrapping (FIX DUT-04, DUT-05).
//==============================================================================

module frame_aligner (
   input  wire       clk,               // byte clock
   input  wire       reset,             // asynchronous, active-high reset
   input  wire [7:0] rx_data,           // byte stream from the PHY
   output reg  [3:0] fr_byte_position,  // index of the byte just sampled (0..11)
   output reg        frame_detect       // frame alignment indication
);

   // Header byte values (LSB is transmitted first).
   localparam [7:0] HEAD1_LSB = 8'hAA, HEAD1_MSB = 8'hAF;
   localparam [7:0] HEAD2_LSB = 8'h55, HEAD2_MSB = 8'hBA;
   localparam [3:0] LAST_POS  = 4'd10;   // position of payload byte 8; the
                                         // next byte (payload 9) ends the frame
   localparam [5:0] NA_LIMIT  = 6'd47;   // 48th header-less byte clears sync

   reg [1:0] legal_frame_counter;        // consecutive valid frames (saturates at 3)
   reg [5:0] na_byte_counter;            // header-less bytes (saturates at 63)
   reg [7:0] header_lsb_samp;            // last header LSB seen

   // FSM control triggers
   reg       fr_byte_position_rst;
   reg       na_byte_count_inc, na_byte_count_rst;
   reg       legal_frame_counter_rst, legal_frame_counter_inc;

   typedef enum reg [1:0] {FR_IDLE = 2'b00,  // hunting for a header LSB
                           FR_HLSB = 2'b01,  // header LSB received, checking MSB
                           FR_HMSB = 2'b10,  // header MSB accepted (payload byte 0 now)
                           FR_DATA = 2'b11   // payload bytes 1..9
                           } frame_aligner_state_e;

   frame_aligner_state_e current_state, next_state;

   wire header_msb_valid, header_lsb_valid;

   //--------------------------------------------------------------------------
   // State register
   //--------------------------------------------------------------------------
   always @(posedge clk or posedge reset) begin
      if (reset) current_state <= FR_IDLE;
      else       current_state <= next_state;
   end

   //--------------------------------------------------------------------------
   // Next-state and trigger logic
   //--------------------------------------------------------------------------
   always @(*) begin
      fr_byte_position_rst    = 1'b0;
      na_byte_count_inc       = 1'b0;
      na_byte_count_rst       = 1'b0;
      legal_frame_counter_rst = 1'b0;
      legal_frame_counter_inc = 1'b0;
      next_state              = current_state;   // FIX DUT-06: default, no latch

      case (current_state)
         FR_IDLE: begin
            fr_byte_position_rst = 1'b1;
            na_byte_count_inc    = 1'b1;
            if (header_lsb_valid) begin
               next_state = FR_HLSB;
            end else begin
               legal_frame_counter_rst = 1'b1;
               next_state              = FR_IDLE;
            end
         end

         FR_HLSB: begin
            if (header_msb_valid) begin
               legal_frame_counter_inc = 1'b1;
               next_state              = FR_HMSB;
            end else if (header_lsb_valid) begin
               // FIX DUT-01: the rejected byte is itself a header LSB, so it
               // starts a new header candidate instead of being thrown away.
               legal_frame_counter_rst = 1'b1;
               fr_byte_position_rst    = 1'b1;
               na_byte_count_inc       = 1'b1;
               next_state              = FR_HLSB;
            end else begin
               legal_frame_counter_rst = 1'b1;
               fr_byte_position_rst    = 1'b1;   // FIX DUT-03: no spurious "1"
               na_byte_count_inc       = 1'b1;
               next_state              = FR_IDLE;
            end
         end

         FR_HMSB: begin
            next_state = FR_DATA;
         end

         FR_DATA: begin
            if (fr_byte_position == LAST_POS) begin   // FIX DUT-06: 4-bit compare
               na_byte_count_rst = 1'b1;
               next_state        = FR_IDLE;
            end else begin
               next_state = FR_DATA;
            end
         end

         default: next_state = FR_IDLE;              // FIX DUT-06
      endcase
   end

   //--------------------------------------------------------------------------
   // Header detection
   //--------------------------------------------------------------------------
   assign header_lsb_valid = (rx_data == HEAD1_LSB) || (rx_data == HEAD2_LSB);

   always @(posedge clk or posedge reset) begin
      if (reset)                 header_lsb_samp <= 8'h00;
      else if (header_lsb_valid) header_lsb_samp <= rx_data;
   end

   // Expected header MSB for the stored LSB.
   wire [7:0] expected_header_msb = (header_lsb_samp == HEAD1_LSB) ? HEAD1_MSB :
                                    (header_lsb_samp == HEAD2_LSB) ? HEAD2_MSB : 8'h00;

   assign header_msb_valid = (expected_header_msb == rx_data);

   //--------------------------------------------------------------------------
   // Counters
   //--------------------------------------------------------------------------
   always @(posedge clk or posedge reset) begin
      if (reset)                     fr_byte_position <= 4'h0;
      else if (fr_byte_position_rst) fr_byte_position <= 4'h0;
      else                           fr_byte_position <= fr_byte_position + 4'd1;
   end

   // FIX DUT-04: saturate at 3 instead of wrapping to 0.
   always @(posedge clk or posedge reset) begin
      if (reset)                        legal_frame_counter <= 2'h0;
      else if (legal_frame_counter_rst) legal_frame_counter <= 2'h0;
      else if (legal_frame_counter_inc && (legal_frame_counter != 2'h3))
                                        legal_frame_counter <= legal_frame_counter + 2'h1;
   end

   // FIX DUT-05: saturate at 63 instead of wrapping to 0.
   always @(posedge clk or posedge reset) begin
      if (reset)                  na_byte_counter <= 6'h0;
      else if (na_byte_count_rst) na_byte_counter <= 6'h0;
      else if (na_byte_count_inc && (na_byte_counter != 6'h3F))
                                  na_byte_counter <= na_byte_counter + 6'h1;
   end

   //--------------------------------------------------------------------------
   // Alignment indication
   //--------------------------------------------------------------------------
   // FIX DUT-02: sync is cleared only when the byte being consumed is itself
   // counted as header-less (na_byte_count_inc) and it is the 48th such byte.
   // The byte that completes a valid header, and all payload bytes, are never
   // counted, so they can never clear frame_detect.
   always @(posedge clk or posedge reset) begin
      if (reset)                                                frame_detect <= 1'b0;
      else if (legal_frame_counter == 2'h3)                     frame_detect <= 1'b1;
      else if (na_byte_count_inc && (na_byte_counter == NA_LIMIT)) frame_detect <= 1'b0;
   end

endmodule
