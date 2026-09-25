//The monitor_out class acts as an observer for the DUT’s outputs, 
//recording key signals for comparison against expected values. 
//It ensures that all relevant outputs are captured and transferred to the scoreboard,
// enabling comprehensive validation of the DUT's response and behavior based on its output patterns.

class monitor_out;
  
  // Create virtual interface handle
  virtual frame_inf vinf;
  
  // Create mailbox handle
  mailbox mon2scbout;

  // Covergroup for output signals => I need to consider if it's necessary; maybe I'll check it only in the scoreboard. 
  covergroup monitor_out_cg @(posedge vinf.clk);
    coverpoint vinf.frame_detect;
    coverpoint vinf.fr_byte_position {
      bins fr_byte_bins[] = { [0:10] };
    }
    // Cross coverage between frame_detect and fr_byte_position
    cross vinf.frame_detect, vinf.fr_byte_position;
  endgroup

  // Constructor
  function new(virtual frame_inf vinf, mailbox mon2scbout);
    this.vinf = vinf;
    this.mon2scbout = mon2scbout;
    monitor_out_cg = new();
  endfunction
  
  // Main task
  task main;
    forever begin
      transaction trans;
      trans = new();
      @(posedge vinf.clk); // Wait for next clock edge
      trans.frame_detect     = vinf.frame_detect;
      trans.fr_byte_position = vinf.fr_byte_position;

      // Print the captured data
      $display("-------------------------");
      $display("[ --Monitor_out-- ] Captured frame_detect: %b, fr_byte_position: %0d", trans.frame_detect, trans.fr_byte_position);
      $display("-------------------------");
      mon2scbout.put(trans);  // Put transaction in the mailbox
    end
  endtask
  
endclass
