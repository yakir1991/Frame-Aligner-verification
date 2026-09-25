//==============================================================================
// scoreboard -- cycle-accurate checker with defect triage
//------------------------------------------------------------------------------
//  Inputs: one mon_item per clock from monitor_in and one from monitor_out.
//
//  Alignment
//    Sample k of monitor_out is the DUT response to the byte of sample k-1
//    of monitor_in (registered outputs).  So, at every sample k:
//      1. compare DUT outputs(k) with the models' current outputs
//         (the models have already consumed byte k-1),
//      2. evaluate checkpoints attached to byte k-1,
//      3. let the models consume byte k.
//    If reset is sampled high, the outputs must already be 0 (asynchronous
//    reset) and both models are reset.
//
//  Two models, three outcomes
//    spec_m : fa_ref_model with every bug knob OFF  (the specification)
//    dut_m  : fa_ref_model with every bug knob ON   (the design as delivered)
//    For every compared cycle:
//      MATCH       DUT == primary model
//      KNOWN       DUT != spec model but DUT == dut model: a documented defect.
//                  It is attributed to the knob(s) that fired in dut_m since the
//                  two models last had identical state, and spec_m is then
//                  re-synchronised to dut_m so checking continues on the DUT's
//                  actual path (one report per defect occurrence, no cascade).
//      UNEXPLAINED DUT matches neither model: a new, unknown problem.
//    +MODEL=spec (default): verdict = no KNOWN and no UNEXPLAINED mismatch.
//    +MODEL=dut           : regression mode for the delivered design:
//                           verdict = no UNEXPLAINED mismatch.
//==============================================================================
class scoreboard;

  std::mailbox #(mon_item) mon_in2scb, mon_out2scb;
  fa_ref_model        spec_m, dut_m;
  fa_coverage         cov;
  fa_checkpoint_db    cps;

  bit primary_is_dut = 0;          // +MODEL=dut

  // Statistics
  int unsigned n_samples, n_reset_samples, n_compared, n_match;
  int unsigned n_known, n_unexplained, n_x, n_reset_err, n_desync;
  int unsigned n_known_by_bug[FA_NUM_BUGS];
  int unsigned n_known_unattributed;
  int unsigned first_known_idx[FA_NUM_BUGS];
  bit          seen_bug[FA_NUM_BUGS];
  int unsigned print_limit = 10;   // detailed mismatch reports per category

  // Divergence bookkeeping (see header)
  bit [FA_NUM_BUGS-1:0] pending_bugs;

  // Previous input sample (whose byte produced the outputs checked now)
  mon_item prev_in;
  bit      in_reset = 1;

  // Short history for mismatch context
  string   hist[$];
  localparam int HIST_DEPTH = 16;

  function new(std::mailbox #(mon_item) mon_in2scb, std::mailbox #(mon_item) mon_out2scb,
               fa_coverage cov, fa_checkpoint_db cps);
    this.mon_in2scb  = mon_in2scb;
    this.mon_out2scb = mon_out2scb;
    this.cov         = cov;
    this.cps         = cps;
    spec_m = new("spec_model");
    dut_m  = new("dut_model");
    dut_m.set_all_bugs(1);
  endfunction

  task run();
    mon_item i, o;
    forever begin
      mon_in2scb.get(i);
      mon_out2scb.get(o);
      if (i.cycle != o.cycle) begin
        n_desync++;
        fa_error("SCOREBOARD", $sformatf("monitor desynchronisation: in cycle %0d, out cycle %0d", i.cycle, o.cycle));
      end
      process(i, o);
    end
  endtask

  //---------------------------------------------------------------------------
  function void push_hist(string s);
    hist.push_back(s);
    if (hist.size() > HIST_DEPTH) void'(hist.pop_front());
  endfunction

  function void dump_hist();
    $display("             last %0d cycles (byte consumed / DUT out / spec / dut-model):", hist.size());
    foreach (hist[k]) $display("             %s", hist[k]);
  endfunction

  function string bugs2str(bit [FA_NUM_BUGS-1:0] m);
    string s = "";
    for (int b = 0; b < FA_NUM_BUGS; b++) if (m[b]) s = {s, fa_sel(s == "", "", " + "), fa_bug_name(b)};
    return fa_sel(s == "", "unattributed", s);
  endfunction

  //---------------------------------------------------------------------------
  function void process(mon_item i, mon_item o);
    logic [3:0] pos = o.fr_byte_position;
    logic       fd  = o.frame_detect;
    string      where;
    n_samples++;

    // 1. Outputs must never be X/Z.
    if ($isunknown({pos, fd})) begin
      n_x++;
      if (n_x <= print_limit) fa_error("SCOREBOARD", $sformatf("X/Z on DUT outputs: %s", o.out2string()));
    end

    // 2. Asynchronous reset: outputs must be 0 now; models restart.
    if (i.reset !== 1'b0) begin
      n_reset_samples++;
      if (pos !== 4'd0 || fd !== 1'b0) begin
        n_reset_err++;
        if (n_reset_err <= print_limit)
          fa_error("SCOREBOARD", $sformatf("outputs not at reset value during reset: %s", o.out2string()));
      end
      if (!in_reset) cov.sample_reset(spec_m.phase, spec_m.fd);
      spec_m.reset();
      dut_m.reset();
      pending_bugs = '0;
      in_reset     = 1;
      prev_in      = null;
      push_hist($sformatf("cyc %0d  RESET", i.cycle));
      return;
    end
    in_reset = 0;

    // 3. Compare with the models (they have consumed byte k-1 already).
    if (prev_in != null) begin
      bit ok_spec = (pos === spec_m.pos) && (fd === spec_m.fd);
      bit ok_dut  = (pos === dut_m.pos)  && (fd === dut_m.fd);
      n_compared++;
      where = (prev_in.byte_valid === 1'b1) ? $sformatf("after byte %0d (%02h)", prev_in.byte_idx, prev_in.rx_data)
                                            : $sformatf("after idle byte (%02h)", prev_in.rx_data);
      push_hist($sformatf("cyc %0d  rx=%02h  dut pos=%0d fd=%b | spec pos=%0d fd=%b | dut-model pos=%0d fd=%b%s",
                          prev_in.cycle, prev_in.rx_data, pos, fd, spec_m.pos, spec_m.fd,
                          dut_m.pos, dut_m.fd, fa_sel(ok_spec, "", "   <<<")));
      if (primary_is_dut ? ok_dut : ok_spec) begin
        n_match++;
        if (primary_is_dut && !ok_spec) record_known(where, pos, fd);   // informational
      end else if (!primary_is_dut && ok_dut) begin
        record_known(where, pos, fd);
      end else begin
        n_unexplained++;
        if (n_unexplained <= print_limit) begin
          fa_error("SCOREBOARD", $sformatf("UNEXPLAINED mismatch %s: DUT pos=%0d fd=%b, spec pos=%0d fd=%b, dut-model pos=%0d fd=%b",
                                           where, pos, fd, spec_m.pos, spec_m.fd, dut_m.pos, dut_m.fd));
          dump_hist();
        end
      end
      // 4. Test-plan checkpoints for the byte that produced these outputs.
      if (prev_in.byte_valid === 1'b1) cps.evaluate(prev_in.byte_idx, pos, fd);
    end

    // 5. Consume the current byte.
    spec_m.step(i.rx_data);
    dut_m.step(i.rx_data);
    pending_bugs |= dut_m.last.bug_hits;
    if (spec_m.same_state(dut_m)) pending_bugs = '0;   // divergence had no effect
    cov.sample_step(primary_is_dut ? dut_m.last : spec_m.last);
    prev_in = i;
  endfunction

  // A deviation from the specification that the DUT model predicts.
  function void record_known(string where, logic [3:0] pos, logic fd);
    n_known++;
    if (pending_bugs == '0) n_known_unattributed++;
    for (int b = 0; b < FA_NUM_BUGS; b++)
      if (pending_bugs[b]) begin
        n_known_by_bug[b]++;
        if (!seen_bug[b]) begin seen_bug[b] = 1; first_known_idx[b] = prev_in.byte_idx; end
      end
    if (n_known <= print_limit || fa_verbosity >= 2) begin
      $display("[%10t] %-11s SPEC VIOLATION %s: DUT pos=%0d fd=%b, spec expects pos=%0d fd=%b  -> known defect: %s",
               $time, "SCOREBOARD", where, pos, fd, spec_m.pos, spec_m.fd, bugs2str(pending_bugs));
      if (n_known <= 3) dump_hist();
    end
    // Continue on the DUT's actual path.
    spec_m.copy_state(dut_m);
    pending_bugs = '0;
  endfunction

  //---------------------------------------------------------------------------
  function void report();
    $display("---------------------------------------------------------------------------");
    $display(" SCOREBOARD (primary model: %s)", fa_sel(primary_is_dut, "DUT-as-designed (regression mode)", "SPECIFICATION"));
    $display("---------------------------------------------------------------------------");
    $display("  samples              : %0d (%0d in reset)", n_samples, n_reset_samples);
    $display("  compared cycles      : %0d", n_compared);
    $display("  matches              : %0d", n_match);
    $display("  spec violations      : %0d  (explained by known DUT defects)", n_known);
    for (int b = 0; b < FA_NUM_BUGS; b++)
      if (n_known_by_bug[b] > 0)
        $display("      %-58s %5d  (first after byte %0d)", fa_bug_name(b), n_known_by_bug[b], first_known_idx[b]);
    if (n_known_unattributed > 0)
      $display("      %-58s %5d", "not attributable to a single knob", n_known_unattributed);
    $display("  UNEXPLAINED mismatch : %0d", n_unexplained);
    $display("  X/Z on outputs       : %0d", n_x);
    $display("  reset value errors   : %0d", n_reset_err);
    $display("  monitor desync       : %0d", n_desync);
    $display("  checkpoints          : %0d passed, %0d failed, %0d never reached",
             cps.n_passed, cps.n_failed, cps.pending());
    foreach (cps.failures[k]) if (k < 25) $display("      FAIL %s", cps.failures[k]);
    if (cps.failures.size() > 25) $display("      ... %0d more", cps.failures.size() - 25);
  endfunction

endclass
