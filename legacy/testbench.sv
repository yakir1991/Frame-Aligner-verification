//The testbench_top module is the main setup for running simulations on the Frame Aligner.
// It provides clock and reset signals, instantiates the DUT, connects it to the verification
// environment, and activates assertions. This setup enables comprehensive and automated testing,
// with waveform logging for later analysis, making it a complete testbench for verifying
// the DUT’s functionality and compliance with specifications.

module testbench_top;
  
  // Clock and reset signal declaration
  bit clk = 0;
  bit reset;
  
  // Clock generation
  always #5 clk = ~clk;
  
  // Reset generation
  initial begin
    reset = 1;
    #15 reset = 0;
  end
  
  // Dump waveforms
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars();
  end
  
  // Interface instance to connect DUT and testbench
  frame_inf i_inf(clk, reset);
 
  // Testcase instance
  test t1(i_inf);
  
  // DUT instance with port connections
  frame_aligner a1 (
    .clk(i_inf.clk),
    .rx_data(i_inf.rx_data),
    .reset(i_inf.reset),
    .fr_byte_position(i_inf.fr_byte_position),
    .frame_detect(i_inf.frame_detect)
  );


   //Added the bind to connect the frame_assertions to the DUT
  bind a1 frame_assertions checker_inst (
    .clk(i_inf.clk),
    .rx_data(i_inf.rx_data),
    .reset(i_inf.reset),
    .fr_byte_position(i_inf.fr_byte_position),
    .frame_detect(i_inf.frame_detect)
    );

endmodule



