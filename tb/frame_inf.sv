`timescale 1ns / 1ps
//==============================================================================
// frame_inf -- interface between the testbench and the frame aligner DUT
//------------------------------------------------------------------------------
//  Signals
//    reset             : asynchronous active-high DUT reset, owned by the driver
//                        (so that tests can also reset the DUT in mid-stream)
//    rx_data           : byte stream into the DUT
//    fr_byte_position  : DUT output
//    frame_detect      : DUT output
//    tb_byte_idx /     : testbench-only side band (NOT connected to the DUT).
//    tb_byte_valid       The driver tags every byte it drives with its index
//                        in the generated stream.  The scoreboard uses the tag
//                        to evaluate test-plan checkpoints ("after byte N,
//                        frame_detect must be 1") at exactly the right cycle.
//
//  Timing (why clocking blocks)
//    The legacy environment sampled and drove signals directly on @(posedge clk)
//    and relied on program-block scheduling to avoid races, so its results
//    depended on the simulator.  Here all TB accesses go through clocking blocks:
//      drv_cb : outputs are driven 1ns AFTER the rising edge, so the DUT
//               samples a stable byte on the next edge.
//      mon_cb : inputs are sampled in the #1step region, i.e. the values that
//               were stable just BEFORE the rising edge.
//    Consequence (used by the scoreboard): at monitor sample k,
//      rx_data            = the byte the DUT consumes on edge k, and
//      fr_byte_position / = the DUT response to the byte of sample k-1.
//      frame_detect
//==============================================================================
interface frame_inf (input logic clk);

  logic        reset;
  logic [7:0]  rx_data;
  logic [3:0]  fr_byte_position;
  logic        frame_detect;

  // Testbench side band (never seen by the DUT).
  int unsigned tb_byte_idx;
  logic        tb_byte_valid;

  // Driver view: stimulus is launched 1ns after the active edge.
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output rx_data, tb_byte_idx, tb_byte_valid;
  endclocking

  // Reset view: the asynchronous reset is changed on the FALLING edge, half a
  // cycle away from the sampling edge (the legacy bench released reset
  // exactly on a rising edge -> race between reset and the first byte).
  clocking rst_cb @(negedge clk);
    default output #0;
    output reset;
  endclocking

  // Monitor view: everything sampled just before the active edge.
  clocking mon_cb @(posedge clk);
    default input #1step;
    input reset, rx_data, fr_byte_position, frame_detect, tb_byte_idx, tb_byte_valid;
  endclocking

  // Modports document the direction of every signal for each user.
  modport DUT (input clk, reset, rx_data, output fr_byte_position, frame_detect);
  // Portability rule followed by the TB: a process synchronises ONLY on
  // clocking-block events.  Waiting on @(posedge clk) and then on @(drv_cb)
  // can resume twice in the same time step (the clocking event is triggered
  // after the raw edge), which silently shifts the stream by one byte.
  modport DRV (clocking drv_cb, clocking rst_cb, output reset, input clk);
  modport MON (clocking mon_cb, input clk);

endinterface
