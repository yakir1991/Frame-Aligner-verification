`timescale 1ns / 1ps
//==============================================================================
// tb_trace -- minimal RTL trace harness (Icarus Verilog / any simulator)
//------------------------------------------------------------------------------
//  Used by the Python tools in scripts/ (differential fuzzing, waveform
//  figures).  It is deliberately independent of the class-based testbench.
//
//  Stimulus file (+IN=<file>, $readmemh): one 9-bit word per clock cycle
//     bit 8   : 1 = reset asserted during this cycle
//     bit 7:0 : rx_data byte
//  Words are applied on the falling edge; the DUT samples them on the next
//  rising edge.
//  Output file (+OUT=<file>): one line per cycle, written 1ns after the rising
//  edge, i.e. the registered response to that cycle's byte:
//     <fr_byte_position:1 hex><frame_detect:1><state:1><legal:1><na:2 hex>
//==============================================================================
module tb_trace;
  reg        clk = 1'b0, reset = 1'b1;
  reg  [7:0] rx = 8'h00;
  wire [3:0] pos;
  wire       fd;

  frame_aligner dut (.clk(clk), .rx_data(rx), .reset(reset), .fr_byte_position(pos), .frame_detect(fd));

  always #5 clk = ~clk;

  reg [8:0]    mem [0:4194303];
  integer      n, i, fo;
  string       fin, fout;          // file names (any length)

  initial begin
    if (!$value$plusargs("N=%d", n))     n    = 0;
    if (!$value$plusargs("IN=%s", fin))  fin  = "stim.hex";
    if (!$value$plusargs("OUT=%s", fout)) fout = "resp.txt";
    $readmemh(fin, mem);
    fo = $fopen(fout, "w");
    #12 reset = 1'b0;
    for (i = 0; i < n; i = i + 1) begin
      @(negedge clk) begin reset = mem[i][8]; rx = mem[i][7:0]; end
      @(posedge clk) #1 $fwrite(fo, "%h%h%h%h%h\n", pos, fd, dut.current_state,
                                dut.legal_frame_counter, dut.na_byte_counter);
    end
    $fclose(fo);
    $finish;
  end
endmodule
