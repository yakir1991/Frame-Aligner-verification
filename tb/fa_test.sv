`timescale 1ns / 1ps
//==============================================================================
// fa_test -- test program: reads the run-time options and runs the environment
//------------------------------------------------------------------------------
//  Plusargs
//    +TEST=<name>        regression (default) | directed | boundary | random |
//                        <scenario>   (see tb/sequence_lib.sv for the list)
//    +MODEL=spec|dut     primary reference: specification (default) or the
//                        DUT-as-designed model (regression mode, known defects
//                        tolerated)
//    +NUM_ITEMS=<n>      number of random items (random / regression)
//    +SEED=<n>           seed of the stimulus random generator
//    +VERBOSITY=<0..3>   log detail (default 1)
//    +DUT_NAME=<text>    label printed in the report
//    +STIM_FILE=<path>   raw stimulus for +TEST=file
//    +TIMEOUT_CYCLES=<n> watchdog (default 2,000,000 cycles)
//    +COV_BINS           print every coverage bin
//==============================================================================
program automatic fa_test (frame_inf vif);

  import fa_pkg::*;

  environment env;

  initial begin
    string       s;
    int unsigned n;
    int unsigned timeout_cycles = 2_000_000;

    env = new(vif);

    if ($value$plusargs("VERBOSITY=%d", n)) fa_verbosity = n;
    if ($value$plusargs("TEST=%s", s))      env.gen.test_name = s;
    if ($value$plusargs("NUM_ITEMS=%d", n)) env.gen.num_random_items = n;
    if ($value$plusargs("DUT_NAME=%s", s))  env.dut_name = s;
    if ($value$plusargs("STIM_FILE=%s", s)) env.gen.stim_file = s;
    if ($value$plusargs("TIMEOUT_CYCLES=%d", n)) timeout_cycles = n;
    if ($test$plusargs("COV_BINS"))         env.show_cov_bins = 1;
    if ($value$plusargs("MODEL=%s", s)) begin
      if (s == "dut")       env.scb.primary_is_dut = 1;
      else if (s != "spec") fa_error("TEST", $sformatf("unknown +MODEL=%s (use spec or dut)", s));
    end
    if ($value$plusargs("SEED=%d", n)) begin
      std::process p = std::process::self();
      p.srandom(n);
      fa_info(1, "TEST", $sformatf("stimulus seed %0d", n));
    end

    fa_info(1, "TEST", $sformatf("test=%s model=%s dut=%s", env.gen.test_name,
                                 fa_sel(env.scb.primary_is_dut, "dut", "spec"), env.dut_name));

    fork
      env.run();
      begin
        repeat (timeout_cycles) @(posedge vif.clk);
        fa_error("TEST", $sformatf("watchdog: test did not finish within %0d cycles", timeout_cycles));
        env.report();
      end
    join_any
    $finish;
  end

endprogram
