//The scoreboard is the core checker in the verification environment, implementing a detailed FSM to track expected
// frame states and positions. By comparing actual DUT outputs with expected values and logging errors, it ensures that
// the DUT operates correctly. Additionally, it gathers coverage data, providing insights into the test completeness across
// various scenarios and states. This setup allows for thorough validation of the DUT's functionality, error resilience,
// and performance under different input conditions.

class scoreboard;

  // Mailbox handles
  mailbox mon2scbin;
  mailbox mon2scbout;

  // Transaction variables
  bit [7:0] rx_data_in;
  bit [3:0] fr_byte_position_out;
  bit frame_detect_out;
  bit [7:0] prev_rx_data_in; // Previous value of rx_data_in

  // Expected values
  bit [3:0] exp_fr_byte_position;
  bit exp_frame_detect;
  bit [3:0] exp_legal_frame_counter;
  bit [5:0] exp_na_byte_counter;
  bit [5:0] next_exp_na_byte_counter; // Intermediate variable for one clock cycle delay
  bit [7:0] header_lsb_samp;

  // Error counter
  int num_errors; 

  // FSM states
  typedef enum logic [1:0] {IDLE, HLSB, HMSB, DATA} state_t;
  state_t current_state, next_state;

  // Control signals
  bit fr_byte_position_rst;
  bit na_byte_count_inc, na_byte_count_rst;
  bit legal_frame_counter_rst, legal_frame_counter_inc;

  // ** Coverage variables **
  bit [3:0] legal_frame_counter_cov;


  // cover code??
  covergroup combin_all;
    frame_detect_cp : coverpoint frame_detect_out;
    
    fr_byte_position_cp : coverpoint fr_byte_position_out {
      bins byte_position[] = {[0:11]};
      illegal_bins illegal_values = {[12:15]};
    }

    na_byte_position : coverpoint exp_na_byte_counter {
      bins na_byte_position[] = {[0:47]};
      illegal_bins illegal_values = {[48:63]}; 
    }

    legal_frame_counter_cp : coverpoint legal_frame_counter_cov {
      bins one_frame = {1};
      bins two_frames = {2};
      bins three_frames = {3};
      bins above_three_frame = {[4:15]};
    }

    rx_data_cp : coverpoint rx_data_in {
      bins all_values[] = {[8'h00:8'hFF]};
    }

    rx_data_headers_cp : coverpoint rx_data_in {
    bins header1_lsb = {8'hAA};
    bins header2_lsb = {8'h55};
    bins header1_msb = {8'hAF};
    bins header2_msb = {8'hBA};
    bins non_header = default; 
  }

    prev_rx_data_in_headers_cp : coverpoint prev_rx_data_in {
    bins header1_lsb = {8'hAA};
    bins header2_lsb = {8'h55};
    bins header1_msb = {8'hAF};
    bins header2_msb = {8'hBA};
    bins non_header = default; 
  }
    
    cross_headers_frame_detect_na_byte_counter : cross rx_data_headers_cp, prev_rx_data_in_headers_cp, frame_detect_cp,exp_na_byte_counter;
    cross_headers_frame_detect_fr_byte_position : cross rx_data_headers_cp, prev_rx_data_in_headers_cp, frame_detect_cp,fr_byte_position_cp;
    cross_frame_detect_rx_data : cross frame_detect_cp, rx_data_cp;
    cross_frame_detect_fr_byte_position : cross frame_detect_cp, fr_byte_position_cp;
    cross_frame_detect_na_byte_position : cross frame_detect_cp, exp_na_byte_counter;
    cross_legal_frame_counter_na_byte_position : cross exp_na_byte_counter, legal_frame_counter_cp;
    cross_fr_byte_position_legal_frame_counter : cross fr_byte_position_cp, legal_frame_counter_cp;

    // not working
    cross_frame_detect_legal_frame_counter : cross frame_detect_cp, legal_frame_counter_cp { 
      ignore_bins unwanted_combination = binsof(frame_detect_cp) intersect {1} &&
                                         (binsof(legal_frame_counter_cp.three_frames) || binsof(legal_frame_counter_cp.above_three_frame)); // Why is this still appearing ?
    }
    
  endgroup

  // Constructor
  function new(mailbox mon2scbin, mailbox mon2scbout);
    this.mon2scbin = mon2scbin;
    this.mon2scbout = mon2scbout;

    // Initialize expected values
    exp_fr_byte_position = 4'h0;
    exp_frame_detect = 1'b0;
    exp_legal_frame_counter = 2'h0;
    exp_na_byte_counter = 6'h0;
    next_exp_na_byte_counter = 6'h0;
    header_lsb_samp = 8'h00;

    // Initialize error counter
    num_errors = 0;

    // Initialize FSM state
    current_state = IDLE;
    next_state = IDLE;

    // ** Initialize coverage variables **
    legal_frame_counter_cov = 2'b0;
    prev_rx_data_in = 8'h00; // Initialize previous rx_data_in

    // ** Instantiate covergroups **
    combin_all = new();
  endfunction

  // Helper: check if current byte is a valid header LSB
  function bit is_valid_header_lsb(bit [7:0] data);
    return (data == 8'hAA) || (data == 8'h55);
  endfunction

  // Helper: compute expected header MSB based on previously sampled LSB
  function bit [7:0] get_expected_header_msb(bit [7:0] lsb);
    case (lsb)
      8'hAA: get_expected_header_msb = 8'hAF;
      8'h55: get_expected_header_msb = 8'hBA;
      default: get_expected_header_msb = 8'h00;
    endcase
  endfunction

  // Helper: check if the current byte matches the expected header MSB
  function bit is_valid_header_msb(bit [7:0] lsb, bit [7:0] data);
    return (get_expected_header_msb(lsb) == data);
  endfunction

  // Main task
  task main;
    transaction trans_in;
    transaction trans_out;

    forever begin
      // Get transactions from monitors
      mon2scbin.get(trans_in);     // Contains rx_data
      mon2scbout.get(trans_out);   // Contains fr_byte_position and frame_detect

      prev_rx_data_in = rx_data_in; // Update previous rx_data_in before updating current
      rx_data_in = trans_in.rx_data;
      fr_byte_position_out = trans_out.fr_byte_position;
      frame_detect_out = trans_out.frame_detect;

      // Process the FSM
      process_fsm();

      // Update exp_na_byte_counter with next_exp_na_byte_counter (introduce one cycle delay)
      exp_na_byte_counter = next_exp_na_byte_counter;

      // Compare expected and actual outputs
      compare_outputs();

      // ** Sample coverage **
      sample_coverage();

      // Update current state
      current_state = next_state;

    end
  endtask

  // FSM processing
  task process_fsm;
    // **Declare local variables at the beginning**
    bit header_lsb_valid;
    bit header_msb_valid;
    bit [7:0] expected_header_msb;

    // Default control signals
    fr_byte_position_rst = 1'b0;
    na_byte_count_inc = 1'b0;
    na_byte_count_rst = 1'b0;
    legal_frame_counter_rst = 1'b0;
    legal_frame_counter_inc = 1'b0;

    // Define header validity using helper functions
    header_lsb_valid   = is_valid_header_lsb(rx_data_in);
    expected_header_msb = get_expected_header_msb(header_lsb_samp);
    header_msb_valid   = is_valid_header_msb(header_lsb_samp, rx_data_in);

    // FSM logic
    case (current_state)
      IDLE: begin
        if (header_lsb_valid) begin
          fr_byte_position_rst = 1'b1;
          na_byte_count_inc = 1'b1;
          next_state = HLSB;
          header_lsb_samp = rx_data_in; // Sample LSB
          $display("[Scoreboard] State: IDLE -> HLSB, header_lsb_samp: 0x%0h", header_lsb_samp);
        end else begin
          legal_frame_counter_rst = 1'b1;
          fr_byte_position_rst = 1'b1;
          na_byte_count_inc = 1'b1;
          next_state = IDLE;
          $display("[Scoreboard] State: IDLE remains, invalid LSB received: 0x%0h", rx_data_in);
        end
      end
      HLSB: begin
        if (header_msb_valid) begin
          next_state = HMSB;
          $display("[Scoreboard] State: HLSB -> HMSB, valid MSB received: 0x%0h", rx_data_in);
        end else begin
          legal_frame_counter_rst = 1'b1;
          na_byte_count_inc = 1'b1;
          // fr_byte_position_rst = 1'b1;  // Reset byte position if MSB invalid -- No need, as the reset is performed on the next clock cycle.
          next_state = IDLE;
          $display("[Scoreboard] State: HLSB -> IDLE, invalid MSB received: 0x%0h", rx_data_in);
        end
      end
      HMSB: begin
        legal_frame_counter_inc = 1'b1; // included it here to delay by one clock cycle.
        next_state = DATA;
        $display("[Scoreboard] State: HMSB -> DATA");
      end
      DATA: begin
        if (exp_fr_byte_position == 4'd10) begin
          na_byte_count_rst = 1'b1;
          next_state = IDLE;
          $display("[Scoreboard] State: DATA -> IDLE, reached fr_byte_position 10");
        end else begin
          next_state = DATA;
          $display("[Scoreboard] State: DATA remains, fr_byte_position: %0d", exp_fr_byte_position);
        end
      end
      default: begin
        next_state = IDLE;
      end
    endcase

    // Update expected counters based on control signals
    update_expected_counters();
  endtask

  // Update expected counters
  task update_expected_counters;
    // fr_byte_position
    if (fr_byte_position_rst) begin
      exp_fr_byte_position = 4'h0;
    end else if (current_state == DATA || current_state == HMSB || current_state == HLSB) begin
      exp_fr_byte_position += 1'b1;
    end

    // legal_frame_counter
    if (legal_frame_counter_rst) begin
      exp_legal_frame_counter = 2'h0;
      legal_frame_counter_cov = 2'h0;
    end else if (legal_frame_counter_inc) begin
      exp_legal_frame_counter += 1'b1;
      legal_frame_counter_cov += 1'b1;
    end

    // na_byte_counter
    if (na_byte_count_rst) begin
      exp_na_byte_counter = 6'h0;
      next_exp_na_byte_counter = 6'h0;
    end else if (na_byte_count_inc) begin
      if (exp_na_byte_counter < 6'd47) begin
        next_exp_na_byte_counter = exp_na_byte_counter + 1'b1;
      end else begin
        next_exp_na_byte_counter = exp_na_byte_counter; 
      end
    end else begin
      next_exp_na_byte_counter = exp_na_byte_counter;
    end

    // frame_detect
    if (exp_legal_frame_counter == 2'h3) begin
      exp_frame_detect = 1'b1;
      exp_legal_frame_counter = 2'h0; // Reset after setting frame_detect
      $display("[Scoreboard] frame_detect set to 1 after 3 legal frames");
    end else if (exp_na_byte_counter == 6'd47) begin
      exp_frame_detect = 1'b0;
      next_exp_na_byte_counter = 6'h0; // Reset after clearing frame_detect
      $display("[Scoreboard] frame_detect cleared to 0 after 47 bytes without header ");
    end
  endtask

  // Compare outputs
  task compare_outputs;
    // Compare fr_byte_position
    if (exp_fr_byte_position == fr_byte_position_out) begin
      $display("[Scoreboard] fr_byte_position matches: Expected=%0d, DUT=%0d", exp_fr_byte_position, fr_byte_position_out);
    end else begin
      $error("[Scoreboard] fr_byte_position mismatch: Expected=%0d, DUT=%0d", exp_fr_byte_position, fr_byte_position_out);
      num_errors++;
    end

    // Compare frame_detect
    if (exp_frame_detect == frame_detect_out) begin
      $display("[Scoreboard] frame_detect matches: Expected=%b, DUT=%b", exp_frame_detect, frame_detect_out);
    end else begin
      $error("[Scoreboard] frame_detect mismatch: Expected=%b, DUT=%b", exp_frame_detect, frame_detect_out);
      num_errors++;
    end
  endtask

  // ** Sample coverage **
  task sample_coverage;
    combin_all.sample();
  endtask


endclass
