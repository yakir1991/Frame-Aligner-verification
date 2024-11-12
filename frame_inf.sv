//frame_inf, is essential for connecting the DUT and testbench in a controlled and organized manner.
//It groups the main signals, enforces directional control through modports, 
//and provides a framework for future timing control if required by uncommenting the clocking block.
//This approach keeps the verification environment organized and helps reduce errors in signal connections.

interface frame_inf(input logic clk, reset);
  
  // Declare the signals for the DUT
  logic [7:0] rx_data;
  logic       frame_detect;
  logic [3:0] fr_byte_position;
  
  // Clocking block with default #1 delay => For future implementation.
  //clocking cb @(posedge clk);
  //  default input #1ps output #1ps;
  //  input  frame_detect;
  //  input  [3:0] fr_byte_position;
  //  output [7:0] rx_data;
  //endclocking

  modport DUT  (input clk, reset, rx_data, output frame_detect, fr_byte_position);
  modport TB(input clk, reset, output rx_data, input frame_detect, fr_byte_position);
  
endinterface

