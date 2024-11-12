//The driver class simulates the sequential transfer of frame data to the DUT,
// carefully synchronizing data transmission with the clock and reset signals.
// It tracks and logs each transaction, ensuring accurate and controlled testing
// of the Frame Aligner’s data input handling. This approach allows precise validation
// of how the DUT responds to different frame structures.

class driver;

  // Count the number of transactions
  int num_transactions;

  // Create virtual interface handle
  virtual frame_inf vinf;

  // Create mailbox handle
  mailbox gen2drv;

  // Constructor
  function new(virtual frame_inf vinf, mailbox gen2drv);
    this.vinf = vinf;
    this.gen2drv = gen2drv;
    num_transactions = 0;
  endfunction

  // Reset task
  task reset;
    wait (vinf.reset);
    $display("-------------------------");
    $display("[ --DRIVER-- ] ----- Reset Started -----");
    $display("-------------------------");
    vinf.rx_data <= 0;
    wait (!vinf.reset);
    $display("-------------------------");
    $display("[ --DRIVER-- ] ----- Reset Ended   -----");
    $display("-------------------------");
  endtask

  // Main task
  task main;
    forever begin
      transaction trans;
      gen2drv.get(trans);        // Get transaction from generator

      // Send the frame bytes
      foreach (trans.frame[i]) begin
        @(posedge vinf.clk)
        vinf.rx_data <= trans.frame[i];

        // Display the sent data
        if (i == 0) begin
          $display("-------------------------");
          $display("[ --Driver-- ] Sending LSB: 0x%0h", trans.frame[i]);
          $display("-------------------------");
        end else if (i == 1) begin
          $display("-------------------------");
          $display("[ --Driver-- ] Sending MSB: 0x%0h", trans.frame[i]);
          $display("-------------------------");
        end else begin
          $display("-------------------------");
          $display("[ --Driver-- ] Sending Payload byte %0d/%0d: 0x%0h", i-1, trans.payload.size(), trans.frame[i]);
          $display("-------------------------");
        end
      end

      num_transactions++;
      $display("-------------------------");
      $display("[ --Driver-- ] Number of transactions sent: %0d", num_transactions);  // Print the transaction count
      $display("-------------------------");
    end
  endtask

endclass
