//The monitor_in class is an essential observer that tracks the input data to the DUT,
// logs it for reference, and sends it to the scoreboard for validation.
// It ensures that all input data is accurately captured, enabling the verification
// environment to check that the DUT operates correctly based on the input data provided.

class monitor_in;
  
  // Create virtual interface handle
  virtual frame_inf vinf;
  
  // Create mailbox handle
  mailbox mon2scbin;

  // Covergroup for input signals => I need to consider if it's necessary; maybe I'll check it only in the scoreboard
  covergroup monitor_in_cg @(posedge vinf.clk);
    coverpoint vinf.rx_data {
      bins rx_data_bins[] = { [0:255] };
    }
  endgroup

  // Constructor
  function new(virtual frame_inf vinf, mailbox mon2scbin);
    this.vinf = vinf;
    this.mon2scbin = mon2scbin;
    monitor_in_cg = new();
  endfunction
  
  // Main task
  task main;
    forever begin
      transaction trans;
      trans = new();
      @(posedge vinf.clk)  // Wait for clock edge
      trans.rx_data = vinf.rx_data;  // Capture rx_data from interface


      // Print the rx_data value
      $display("-------------------------");
      $display("[ --Monitor_in-- ] Captured rx_data: 0x%0h", trans.rx_data);
      $display("-------------------------");
      mon2scbin.put(trans);  // Put transaction in the mailbox
    end
  endtask
  
endclass
