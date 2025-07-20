// The scoreboard is the core checker in the verification environment.
// It uses the frame_aligner_model reference model to predict the expected
// frame byte position and frame detection signals, then compares them with
// the DUT outputs. Additional coverage data is gathered to measure test
// completeness across various scenarios.

class scoreboard;

  // Mailbox handles
  mailbox mon2scbin;
  mailbox mon2scbout;

  // Reference model instance
  frame_aligner_model model;

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

  // Error counter
  int num_errors; 



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
    
    cross_headers_frame_detect_na_byte_counter : cross rx_data_headers_cp, prev_rx_data_in_headers_cp, frame_detect_cp, na_byte_position;
    cross_headers_frame_detect_fr_byte_position : cross rx_data_headers_cp, prev_rx_data_in_headers_cp, frame_detect_cp,fr_byte_position_cp;
    cross_frame_detect_rx_data : cross frame_detect_cp, rx_data_cp;
    cross_frame_detect_fr_byte_position : cross frame_detect_cp, fr_byte_position_cp;
    cross_frame_detect_na_byte_position : cross frame_detect_cp, na_byte_position;
    cross_legal_frame_counter_na_byte_position : cross na_byte_position, legal_frame_counter_cp;
    cross_fr_byte_position_legal_frame_counter : cross fr_byte_position_cp, legal_frame_counter_cp;

    cross_frame_detect_legal_frame_counter : cross frame_detect_cp, legal_frame_counter_cp {
      ignore_bins unwanted_combination = binsof(frame_detect_cp) intersect {1} &&
                                         (binsof(legal_frame_counter_cp.three_frames) ||
                                          binsof(legal_frame_counter_cp.above_three_frame));
    }
    
  endgroup

  // Constructor
  function new(mailbox mon2scbin, mailbox mon2scbout);
    this.mon2scbin = mon2scbin;
    this.mon2scbout = mon2scbout;

    // Create reference model
    model = new();

    // Initialize expected values
    exp_fr_byte_position = 4'h0;
    exp_frame_detect = 1'b0;
    exp_legal_frame_counter = 2'h0;
    exp_na_byte_counter = 6'h0;

    // Initialize error counter
    num_errors = 0;

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

      // Step the reference model to compute expected outputs
      model.step(rx_data_in, 0, exp_fr_byte_position, exp_frame_detect);

      // Get additional counters from the model
      exp_na_byte_counter      = model.na_byte_counter[5:0];
      exp_legal_frame_counter  = model.legal_frame_counter[3:0];
      legal_frame_counter_cov  = model.legal_frame_counter[3:0];

      // Compare expected and actual outputs
      compare_outputs();

      // ** Sample coverage **
      sample_coverage();



    end
  endtask

  // Old FSM-based model kept for reference

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
