//==============================================================================
// environment -- builds and connects the components, runs the test phases,
// and produces the final report and verdict
//------------------------------------------------------------------------------
//        +-----------+  gen2drv   +--------+   frame_inf    +-----+
//        | generator |----------->| driver |===============>| DUT |
//        +-----------+            +--------+   (drv_cb)     +-----+
//              |  checkpoints                                  |  |
//              v                   +------------+  mon_in2scb  |  |
//        +-------------+   <-------| monitor_in |<-------------+  |
//        | scoreboard  |           +------------+   (mon_cb)      |
//        | spec model  |           +-------------+ mon_out2scb    |
//        | dut model   |   <-------| monitor_out |<---------------+
//        | coverage    |           +-------------+   (mon_cb)
//        +-------------+
//   + black-box SVA (fa_spec_sva) and white-box SVA (fa_whitebox_sva) bound
//     into the DUT, reporting through fa_sva_fail().
//
//  Phases
//    build  : generator creates the whole stimulus and the checkpoints
//    start  : monitors + scoreboard start BEFORE reset is released, so the
//             very first byte the DUT consumes is also seen by the models
//    reset  : driver applies the initial reset
//    run    : driver sends every queued item
//    drain  : a few idle cycles so the last byte's response is checked
//    report : scoreboard, checkpoints, assertions, coverage, verdict
//==============================================================================
class environment;

  virtual frame_inf      vif;
  generator              gen;
  driver                 drv;
  monitor_in             mon_in;
  monitor_out            mon_out;
  scoreboard             scb;
  fa_coverage            cov;
  fa_checkpoint_db       cps;
  std::mailbox #(transaction) gen2drv;
  std::mailbox #(mon_item)    mon_in2scb, mon_out2scb;

  string       dut_name       = "unknown";
  int unsigned drain_cycles   = 4;
  bit          show_cov_bins  = 0;

  function new(virtual frame_inf vif);
    this.vif    = vif;
    gen2drv     = new();
    mon_in2scb  = new();
    mon_out2scb = new();
    cov         = new();
    cps         = new();
    gen         = new(gen2drv, cps, cov);
    drv         = new(vif, gen2drv);
    mon_in      = new(vif, mon_in2scb);
    mon_out     = new(vif, mon_out2scb);
    scb         = new(mon_in2scb, mon_out2scb, cov, cps);
  endfunction

  task run();
    // build
    gen.run();
    // start observers first, then reset and stream
    fork
      mon_in.run();
      mon_out.run();
      scb.run();
    join_none
    drv.reset_dut();
    fork
      drv.run();
    join_none
    wait (drv.done);
    repeat (drain_cycles) @(vif.mon_cb);
    #1;   // let the scoreboard consume the last samples
    report();
  endtask

  //---------------------------------------------------------------------------
  // Final report and verdict
  //---------------------------------------------------------------------------
  function bit end_of_test_ok();
    bit ok = 1;
    if (drv.items_driven != gen.items_queued) begin
      fa_error("ENV", $sformatf("driven %0d items but %0d were queued", drv.items_driven, gen.items_queued));
      ok = 0;
    end
    if (gen2drv.num() != 0 || mon_in2scb.num() != 0 || mon_out2scb.num() != 0) begin
      fa_error("ENV", $sformatf("mailboxes not empty at end of test (gen2drv=%0d, in=%0d, out=%0d)",
                                gen2drv.num(), mon_in2scb.num(), mon_out2scb.num()));
      ok = 0;
    end
    if (cps.pending() != 0) begin
      fa_error("ENV", $sformatf("%0d checkpoints were never evaluated", cps.pending()));
      ok = 0;
    end
    if (scb.n_compared == 0) begin
      fa_error("ENV", "nothing was compared");
      ok = 0;
    end
    return ok;
  endfunction

  function void report();
    bit          eot_ok = end_of_test_ok();
    int unsigned sva_spec = fa_sva_total("SPEC_");
    int unsigned sva_wb   = fa_sva_total("WB_");
    int unsigned sva_tb   = fa_sva_total("TB_");
    bit          pass;
    string       bugs = "";

    $display("");
    $display("===========================================================================");
    $display(" FRAME ALIGNER VERIFICATION REPORT");
    $display("   test  : %s", gen.test_name);
    $display("   DUT   : %s", dut_name);
    $display("   model : %s", fa_sel(scb.primary_is_dut, "DUT-as-designed (known defects tolerated)", "specification"));
    $display("   stream: %0d items, %0d bytes, %0d scenarios", gen.items_queued, gen.bytes_queued, gen.scenarios_run.size());
    $display("===========================================================================");
    scb.report();
    $display("---------------------------------------------------------------------------");
    $display(" ASSERTIONS  (spec black-box: %0d failures, white-box: %0d, testbench: %0d)", sva_spec, sva_wb, sva_tb);
    $display("---------------------------------------------------------------------------");
    foreach (fa_sva_fail_count[k]) $display("  %-40s %6d failures", k, fa_sva_fail_count[k]);
    $display("  cover properties (antecedent hits):");
    foreach (fa_sva_cover_count[k]) $display("    %-38s %6d", k, fa_sva_cover_count[k]);
    cov.report(show_cov_bins);
    $display("---------------------------------------------------------------------------");

    if (scb.primary_is_dut)
      pass = eot_ok && scb.n_unexplained == 0 && scb.n_x == 0 && scb.n_reset_err == 0 &&
             scb.n_desync == 0 && sva_tb == 0 && fa_error_count == cps.n_failed;
    else
      pass = eot_ok && scb.n_unexplained == 0 && scb.n_known == 0 && scb.n_x == 0 &&
             scb.n_reset_err == 0 && scb.n_desync == 0 && cps.n_failed == 0 &&
             sva_spec == 0 && sva_wb == 0 && sva_tb == 0 && fa_error_count == 0;

    for (int b = 0; b < FA_NUM_BUGS; b++)
      bugs = {bugs, fa_sel(b == 0, "", ","), $sformatf("DUT-%02d:%0d", b + 1, scb.n_known_by_bug[b])};
    // One machine-readable line for the regression script (sim/regress.py).
    $display("FA_RESULT verdict=%s test=%s dut=%s model=%s compared=%0d known=%0d unexplained=%0d x=%0d cp_pass=%0d cp_fail=%0d sva_spec=%0d sva_wb=%0d sva_tb=%0d bugs=%s cov=%0.1f",
             fa_sel(pass, "PASS", "FAIL"), gen.test_name, dut_name, fa_sel(scb.primary_is_dut, "dut", "spec"),
             scb.n_compared, scb.n_known, scb.n_unexplained, scb.n_x, cps.n_passed, cps.n_failed,
             sva_spec, sva_wb, sva_tb, bugs, cov.total_percent());
    $display("===========================================================================");
    if (pass) $display(" TEST PASSED");
    else      $display(" TEST FAILED");
    $display("===========================================================================");
  endfunction

endclass
