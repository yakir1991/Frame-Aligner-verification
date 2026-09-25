`timescale 1ns / 1ps
//==============================================================================
// frame_aligner  --  ORIGINAL DESIGN UNDER TEST (DUT)
//------------------------------------------------------------------------------
//  Author (RTL)      : Ilan Rachmanov
//  Annotations       : verification team (comments only -- the RTL logic in this
//                      file is byte-for-byte the delivered design; the check
//                      `make check-rtl-untouched` proves it)
//
//  What the block does
//  -------------------
//  The frame aligner receives one byte per clock (rx_data) from the PHY and
//  looks for a 16-bit frame header, transmitted LSB first:
//        HEAD_1 : 0xAA followed by 0xAF   (header value 0xAFAA)
//        HEAD_2 : 0x55 followed by 0xBA   (header value 0xBA55)
//  A frame is 12 bytes: 2 header bytes + 10 payload bytes, frames back-to-back.
//
//  Outputs (both are registered, i.e. they describe the byte sampled on the
//  PREVIOUS rising edge):
//    fr_byte_position[3:0] : index of that byte inside the frame
//                            (header LSB = 0, header MSB = 1, payload = 2..11)
//    frame_detect          : '1' = frame alignment declared
//
//  Alignment algorithm (spec):
//    * in-frame  : three consecutive frames with a correct header
//    * out-of-frame : four consecutive frames with incorrect headers
//                     (implemented as 48 bytes without a header)
//
//  Micro-architecture (see the spec FSM slide):
//    FR_IDLE -> FR_HLSB -> FR_HMSB -> FR_DATA -> FR_IDLE ...
//      FR_IDLE : hunting; waits for a header LSB (0xAA / 0x55)
//      FR_HLSB : LSB seen; checks that this byte is the matching MSB
//      FR_HMSB : header accepted; this byte is payload byte 0
//      FR_DATA : payload bytes 1..9; leaves when fr_byte_position == 10
//    Counters driven by FSM "trigger" signals:
//      fr_byte_position    : byte index inside the frame
//      legal_frame_counter : consecutive frames with a valid header (2 bit)
//      na_byte_counter     : "not aligned" bytes seen since the last frame (6 bit)
//
//  ----------------------------------------------------------------------------
//  KNOWN DEFECTS found by verification (details: docs/BUG_REPORT.md).
//  Each one is marked in the code below with a "DUT-0x" tag.
//    DUT-01  A rejected header MSB that is itself a header LSB is thrown away
//            (AA AA AF, 55 55 BA, AA 55 BA, 55 AA AF -> header missed).
//    DUT-02  frame_detect is cleared on the very byte that completes a VALID
//            header (46 header-less bytes + header); the clear condition is
//            not qualified and the header LSB is counted as a non-aligned byte.
//    DUT-03  fr_byte_position reports 1 ("header MSB") for one cycle after a
//            header was REJECTED, although no frame exists.
//    DUT-04  legal_frame_counter wraps 3 -> 0 on the 4th consecutive frame
//            (latent, not visible at the ports today).
//    DUT-05  na_byte_counter wraps 63 -> 0 on long header-less streams
//            (latent, not visible at the ports today).
//    DUT-06  Coding issues: no default assignment of next_state, width
//            mismatch (4-bit vs 8'd10), misleading comment.
//  A corrected implementation lives in rtl/frame_aligner_fixed.sv.
//==============================================================================


module frame_aligner(clk, rx_data , reset , fr_byte_position , frame_detect) ;

   output [3:0]  fr_byte_position; // byte position in a legal frame
   output frame_detect;            // frame alignment indication

   input  clk;                     // byte clock
   input  [7:0] rx_data;           // byte stream from the PHY
   input  reset;                   // asynchronous, active-high reset


   reg [3:0] fr_byte_position;
   reg [1:0] legal_frame_counter;  // DUT-04: 2-bit, wraps after 3
   reg [5:0] na_byte_counter;      // DUT-05: 6-bit, wraps after 63
   reg 	     frame_detect;
   reg [7:0] header_lsb_samp;      // last header LSB seen (selects the expected MSB)

   // FSM control triggers
   // (combinational outputs of the FSM that tell the counters what to do)
   reg 	     fr_byte_position_rst;
   reg 	     na_byte_count_inc, na_byte_count_rst;
   reg 	     legal_frame_counter_rst , legal_frame_counter_inc;


   typedef enum reg [1:0] {FR_IDLE = 2'b00,  // hunting for a header LSB
			   FR_HLSB = 2'b01,  // header LSB received, checking MSB
			   FR_HMSB = 2'b10,  // header MSB accepted (payload byte 0 now)
			   FR_DATA = 2'b11   // payload bytes 1..9
			   } frame_aligner_state_e;

   frame_aligner_state_e current_state , next_state;

   wire   header_msb_valid , header_lsb_valid;

   //--------------------------------------------------------------
   //--------------------------------------------------------------
   // Frame Aligner state machine
   // State register: asynchronous reset to FR_IDLE.

   always @ (posedge clk or  posedge reset)
     begin
	if (reset)
	  current_state <= FR_IDLE;
	else
	  current_state <= next_state;
     end



   // Next-state and trigger logic (combinational).
   // DUT-06: next_state has no default assignment before the case statement.
   //         It is complete today only because every branch assigns it and all
   //         four encodings are listed; adding a state later infers a latch.
   always @ (*)
     begin
	fr_byte_position_rst = 1'b0;
	na_byte_count_inc = 1'b0;
	na_byte_count_rst = 1'b0;
	legal_frame_counter_rst = 1'b0;
	legal_frame_counter_inc = 1'b0;

	case(current_state)
	  FR_IDLE:
	    begin
	       // Hunting. Every byte here is counted as "not aligned".
	       // DUT-02 (part 1): a header LSB is also counted, so a valid header
	       // that arrives after 46 header-less bytes drives the counter to 47.
	       if(header_lsb_valid)
		 begin
		    fr_byte_position_rst = 1'b1;
		    na_byte_count_inc = 1'b1;
		    next_state = FR_HLSB;
		 end
	       else
		 begin
		    legal_frame_counter_rst = 1'b1;
		    fr_byte_position_rst = 1'b1;
		    na_byte_count_inc = 1'b1;
		    next_state = FR_IDLE;
		 end
	    end
	  FR_HLSB:
	    begin
	       // Previous byte was a header LSB: is this byte the matching MSB?
	       if(header_msb_valid)
		 begin
		    legal_frame_counter_inc = 1'b1; // DUT-04: no saturation
		    next_state = FR_HMSB;
		 end
	       else
		 begin
		    // Header rejected.
		    // DUT-01: if this byte is itself a header LSB (0xAA/0x55) it
		    //         should start a new header candidate (stay in FR_HLSB);
		    //         instead the FSM returns to FR_IDLE and the byte is lost.
		    // DUT-03: fr_byte_position is not reset here, so it increments
		    //         from 0 to 1 and reports "header MSB" for a rejected
		    //         header during the next cycle.
		    legal_frame_counter_rst = 1'b1;
		    na_byte_count_inc = 1'b1;
		    next_state = FR_IDLE;
		 end
	    end
	  FR_HMSB:
	    begin
	       // Header accepted; this byte is payload byte 0.
	       next_state = FR_DATA;
	    end
	  FR_DATA:
	    begin
	       // Payload bytes 1..9 (fr_byte_position 2..10 while in this state).
	       // DUT-06: 4-bit fr_byte_position compared with an 8-bit constant.
	       if(fr_byte_position == 8'd10)
		 begin
		    // Last payload byte: the frame is complete.
		    na_byte_count_rst = 1'b1;
		    next_state = FR_IDLE;
		 end
	       else
		 next_state = FR_DATA;
	    end
	endcase

     end

   //--------------------------------------------------------------
   //--------------------------------------------------------------

   // The code below searches the header pattern and send indications to the FSM to advance to FR_HLSB and FR_HMSB states
   // first the lsb pattern is sampled . in case the msb pattern matches , the FSM will advance to FR_HMSB

   // Combinational: current byte is a header LSB (either header type).
   assign header_lsb_valid = (rx_data == 8'haa) || (rx_data == 8'h55);

     // Remember the most recent header LSB. It is sampled in every state, but
     // it is only consumed in FR_HLSB, whose previous cycle was always FR_IDLE
     // with header_lsb_valid = 1, so the value is always the right LSB.
     always @ (posedge clk or  posedge reset)
       begin
	  if (reset)
	    header_lsb_samp <= 8'h0;
	  else if (header_lsb_valid)
	    header_lsb_samp <= rx_data;
       end

   /// expected lsb header pattern:
   // (DUT-06: the comment above is wrong -- this computes the expected MSB.)
   // 0xAA -> 0xAF, 0x55 -> 0xBA, anything else -> 0x00 (never used in FR_HLSB).
   wire [7:0] expected_header_msb = (header_lsb_samp == 8'haa) ? 8'haf : ( (header_lsb_samp == 8'h55) ? 8'hba : 8'h00); // 00 is illegal since header_lsb_samp can be only 55 or aa

   // Combinational: current byte is the MSB that matches the stored LSB.
   assign header_msb_valid = (expected_header_msb == rx_data);

   //--------------------------------------------------------------
   //--------------------------------------------------------------

   // The code below is implementation of the legal frame counter ,  byte position  . and not aligned byte counter which accepts triggeres from the FSM


   //  fr_byte_position increments by default , reset is controlled by the fsm
   //  Values: 0 after a header LSB (or any hunting byte), 1 after the MSB,
   //  2..11 after payload bytes 0..9.
   always @ (posedge clk or  posedge reset)
     begin
	if (reset)
	  fr_byte_position <= 4'h0;
	else if (fr_byte_position_rst)
	  fr_byte_position <= 4'h0;
	else
	  fr_byte_position <= fr_byte_position + 1'b1;
     end

   // frame counter for legal frames
   // DUT-04: wraps from 3 back to 0 on the 4th consecutive valid header.
   always @ (posedge clk or  posedge reset)
     begin
	if (reset)
	  legal_frame_counter <= 2'h0;
	else if (legal_frame_counter_rst)
	  legal_frame_counter <= 2'h0;
	else if (legal_frame_counter_inc)
	  legal_frame_counter <= legal_frame_counter + 1'b1 ;

     end

   // na_byte_counter is counting the illegal frames . in case there are 48 continues bytes witout header frame_detect will set low
   // It is cleared only on the last payload byte of a frame (not when the
   // header is validated) -- this is one half of DUT-02.
   // DUT-05: wraps from 63 back to 0 on long header-less streams.
     always @ (posedge clk or  posedge reset)
       begin
	  if (reset)
	    na_byte_counter <= 6'h0;
	  else if (na_byte_count_rst)
	    na_byte_counter <= 6'h0;
	  else if (na_byte_count_inc)
	    na_byte_counter <= na_byte_counter + 1'b1;
       end

   // Alignment indication.
   //   set   : one cycle after legal_frame_counter reaches 3 (has priority)
   //   clear : when na_byte_counter == 47, i.e. on the 48th counted byte
   // DUT-02 (part 2): the clear is evaluated in EVERY state. It is not
   //   qualified with na_byte_count_inc, so it also fires on the byte that
   //   completes a valid header and throughout the following payload.
   always @ (posedge clk or  posedge reset)
     begin
	if (reset)
	  frame_detect <= 1'b0;
	else if(legal_frame_counter == 2'h3)
	  frame_detect <= 1'b1;
	else if(na_byte_counter == 6'd47)
	  frame_detect <= 1'b0;
     end


   //--------------------------------------------------------------
   //--------------------------------------------------------------


endmodule
