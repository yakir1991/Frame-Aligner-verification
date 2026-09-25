// Reference model of the frame aligner written entirely in SystemVerilog


class frame_aligner_model;

  typedef enum int {FR_IDLE=0, FR_HLSB=1, FR_HMSB=2, FR_DATA=3} state_t;

  // state variables
  state_t        current_state;
  int unsigned   fr_byte_position;
  int unsigned   legal_frame_counter;
  int unsigned   na_byte_counter;
  bit            frame_detect;
  byte           header_lsb_samp;

  // constructor
  function new();
    reset();
  endfunction

  // reset internal state
  function void reset();
    current_state       = FR_IDLE;
    fr_byte_position    = 0;
    legal_frame_counter = 0;
    na_byte_counter     = 0;
    frame_detect        = 0;
    header_lsb_samp     = 0;
  endfunction

  // step the model with the next byte
  // outputs current frame byte position and frame_detect
  task automatic step(input byte data,
                      input bit rst,
                      output bit [3:0] byte_pos,
                      output bit detect);
    bit header_lsb_valid;
    byte expected_header_msb;
    bit header_msb_valid;
    state_t next_state;

    bit fr_byte_position_rst;
    bit na_byte_count_inc;
    bit na_byte_count_rst;
    bit legal_frame_counter_rst;
    bit legal_frame_counter_inc;

    if (rst) begin
      reset();
      byte_pos = fr_byte_position[3:0];
      detect   = frame_detect;
      return;
    end

    header_lsb_valid = (data == 8'hAA) || (data == 8'h55);

    if (header_lsb_samp == 8'hAA)
      expected_header_msb = 8'hAF;
    else if (header_lsb_samp == 8'h55)
      expected_header_msb = 8'hBA;
    else
      expected_header_msb = 8'h00;

    header_msb_valid = (expected_header_msb == data);

    fr_byte_position_rst    = 0;
    na_byte_count_inc       = 0;
    na_byte_count_rst       = 0;
    legal_frame_counter_rst = 0;
    legal_frame_counter_inc = 0;
    next_state = current_state;

    case (current_state)
      FR_IDLE: begin
        if (header_lsb_valid) begin
          fr_byte_position_rst = 1;
          na_byte_count_inc    = 1;
          next_state           = FR_HLSB;
        end else begin
          legal_frame_counter_rst = 1;
          fr_byte_position_rst    = 1;
          na_byte_count_inc       = 1;
          next_state              = FR_IDLE;
        end
      end
      FR_HLSB: begin
        if (header_msb_valid) begin
          legal_frame_counter_inc = 1;
          next_state              = FR_HMSB;
        end else begin
          legal_frame_counter_rst = 1;
          na_byte_count_inc       = 1;
          next_state              = FR_IDLE;
        end
      end
      FR_HMSB: begin
        next_state = FR_DATA;
      end
      FR_DATA: begin
        if (fr_byte_position == 10) begin
          na_byte_count_rst = 1;
          next_state        = FR_IDLE;
        end else begin
          next_state = FR_DATA;
        end
      end
    endcase

    if (fr_byte_position_rst)
      fr_byte_position = 0;
    else
      fr_byte_position = (fr_byte_position + 1) & 4'hF;

    if (legal_frame_counter_rst)
      legal_frame_counter = 0;
    else if (legal_frame_counter_inc)
      legal_frame_counter = (legal_frame_counter + 1) & 2'h3;

    if (na_byte_count_rst)
      na_byte_counter = 0;
    else if (na_byte_count_inc)
      na_byte_counter = (na_byte_counter + 1) & 6'h3F;

    if (legal_frame_counter == 3)
      frame_detect = 1;
    else if (na_byte_counter == 47)
      frame_detect = 0;

    if (header_lsb_valid)
      header_lsb_samp = data;

    current_state = next_state;
    byte_pos = fr_byte_position[3:0];
    detect   = frame_detect;
  endtask

endclass

