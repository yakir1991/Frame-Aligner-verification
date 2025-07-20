`include "test_5_head1.sv"
`include "test_4_illegal_header.sv"
`include "test_5_head2.sv"
`include "test_45_bytes.sv"
`include "test_47_bytes.sv"
`include "test_46_bytes.sv"
`include "test_illegal_headers_with_a_valid_header_in_the_middle_frame.sv"
`include "test_3_random_valid_headers.sv"
`include "test_header_swapped__lsb_msb.sv"
`include "test_reversed_bit_headers.sv"
`include "test_msb_and_lsb_and_valid_header_in_middle_frame.sv"
`include "test_correct_lsb_invalid_msb.sv"
`include "test_correct_msb_invalid_lsb.sv"
`include "test_illegal_headers_with_a_valid_header_in_the_middle_frame_10_clock.sv"
`include "test_3_valid_frames_in_the_invalid_frame.sv"
`include "test_illegal_headers_with_a_valid_header_in_the_middle_frame_random.sv"

//This generator ensures a balanced approach to testing by covering predefined test cases for specific frame aligner scenarios
// while also adding random tests to capture unexpected behaviors or edge cases.
// It sends each transaction to the driver for processing, contributing to a robust test of the Frame Aligner's functionality.
//All tests are conducted in a random order.

class generator;

  // Declare transaction class 
  transaction trans;

  // Repeat count
  int repeat_count;

  // Total transactions sent
  int total_transactions_sent;

  int num_random_transactions;

  // Declare mailbox
  mailbox gen2drv;

  // Declare event
  event ended;

  // Define an enum for test IDs
  typedef enum int {
    TEST_5_HEAD1,
    TEST_4_ILLEGAL_HEADER,
    TEST_5_HEAD2,
    TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME,
    TEST_47_BYTES,
    TEST_46_BYTES,
    TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME_10_CLOCK,
    TEST_3_RANDOM_VALID_HEADERS,
    TEST_HEADER_SWAPPED__LSB_MSB,
    TEST_REVERSED_BIT_HEADERS,
    TEST_MSB_AND_LSB_AND_VALID_HEADER_IN_MIDDLE_FRAME,
    TEST_CORRECT_LSB_INVALID_MSB,
    TEST_CORRECT_MSB_INVALID_LSB,
    TEST_45_BYTES,
    TEST_3_VALID_FRAMES_IN_THE_INVALID_FRAME,
    TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME_RANDOM,
    RANDOM_TRANSACTION
  } test_id_t;

  // Create a queue to hold the test IDs
  test_id_t test_queue[$];

  // Constructor
  function new(mailbox gen2drv);
    this.gen2drv = gen2drv;
    this.total_transactions_sent = 0; // Initialize total transactions sent
  endfunction

   // Main task
  task main();  
    // Initialize total_transactions_sent
    total_transactions_sent = 0; 


    // Add each test ID 3 times (for tests 0 to 14)
    for (int i = 0; i <= 14; i++) begin // total 15 tests
      test_id_t test_id = test_id_t'(i); // cast integer to enum
      repeat (3) begin
        test_queue.push_back(test_id);
      end
    end

    // Add the specific test 30 times (test ID 15)
    repeat (30) begin
      test_queue.push_back(TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME_RANDOM);
    end

    // Decide how many random transactions to generate
    num_random_transactions = repeat_count - test_queue.size();
    if (num_random_transactions < 0)
      num_random_transactions = 0;

    // Add random transactions
    repeat (num_random_transactions) begin
      test_queue.push_back(RANDOM_TRANSACTION);
    end

    // Shuffle the test queue
    test_queue.shuffle();

    // Now execute the tests in random order
    foreach (test_queue[i]) begin
      test_id_t test_id = test_queue[i];
      // Display the test being run
      $display("[Generator] Running test ID: %0d at index %0d", test_id, i);
      case (test_id)
        TEST_5_HEAD1: begin
          test_5_head1(gen2drv, total_transactions_sent);
        end
        TEST_4_ILLEGAL_HEADER: begin
          test_4_illegal_header(gen2drv, total_transactions_sent);
        end
        TEST_5_HEAD2: begin
          test_5_head2(gen2drv, total_transactions_sent);
        end
        TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME: begin
          test_illegal_headers_with_a_valid_header_in_the_middle_frame(gen2drv, total_transactions_sent);
        end
        TEST_47_BYTES: begin
          test_47_bytes(gen2drv, total_transactions_sent);
        end
        TEST_46_BYTES: begin
          test_46_bytes(gen2drv, total_transactions_sent);
        end
        TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME_10_CLOCK: begin
          test_illegal_headers_with_a_valid_header_in_the_middle_frame_10_clock(gen2drv, total_transactions_sent);
        end
        TEST_3_RANDOM_VALID_HEADERS: begin
          test_3_random_valid_headers(gen2drv, total_transactions_sent);
        end
        TEST_HEADER_SWAPPED__LSB_MSB: begin
          test_header_swapped__lsb_msb(gen2drv, total_transactions_sent);
        end
        TEST_REVERSED_BIT_HEADERS: begin
          test_reversed_bit_headers(gen2drv, total_transactions_sent);
        end
        TEST_MSB_AND_LSB_AND_VALID_HEADER_IN_MIDDLE_FRAME: begin
          test_msb_and_lsb_and_valid_header_in_middle_frame(gen2drv, total_transactions_sent);
        end
        TEST_CORRECT_LSB_INVALID_MSB: begin
          test_correct_lsb_invalid_msb(gen2drv, total_transactions_sent);
        end
        TEST_CORRECT_MSB_INVALID_LSB: begin
          test_correct_msb_invalid_lsb(gen2drv, total_transactions_sent);
        end
        TEST_45_BYTES: begin
          test_45_bytes(gen2drv, total_transactions_sent);
        end
        TEST_3_VALID_FRAMES_IN_THE_INVALID_FRAME: begin
          test_3_valid_frames_in_the_invalid_frame(gen2drv, total_transactions_sent);
        end
        TEST_ILLEGAL_HEADERS_WITH_A_VALID_HEADER_IN_THE_MIDDLE_FRAME_RANDOM: begin
          test_illegal_headers_with_a_valid_header_in_the_middle_frame_random(gen2drv, total_transactions_sent);
        end
        RANDOM_TRANSACTION: begin
          trans = new();
          // Perform full randomization (header_type and payload)
          if (!trans.randomize()) begin
            $fatal("Randomization failed for random transaction");
          end
          // Display the generated transaction
          $display("[ --Generator-- ] Generated Transaction:");
          $display("  Header Type    : %s",
                  trans.header_type_to_string(trans.header_type));
          $display("  Payload Size   : %0d bytes", trans.payload.size());
          $display("  Frame Size     : %0d bytes", trans.frame.size());
          $display("  Frame Data     : {");
          foreach (trans.frame[i]) $display("    Byte %0d: 0x%0h", i, trans.frame[i]);
          $display("  }");

          // Send the transaction to driver
          gen2drv.put(trans);
          total_transactions_sent++;
        end
      endcase
    end

    // Trigger the event to signal that generation is complete
    -> ended;
  endtask

endclass
