//==============================================================================
// fa_coverage -- functional coverage model
//------------------------------------------------------------------------------
//  The legacy covergroups had reachable illegal_bins (na counter 48..63),
//  unreachable bins (legal counter 4..15 on a 2-bit value), and very large
//  crosses (rx byte x counters) that could never close.  They measured raw
//  signal values instead of specification features.
//
//  This model samples the reference model's per-byte step information and
//  measures the spec features in the verification plan (docs/VERIFICATION_PLAN.md §5):
//
//    CP01 rx_class          : byte classes (both LSBs, both MSBs, 00, FF, other)
//    CP02 arc               : every transition of the aligner (hunt/lsb/frame)
//    CP03 arc_x_sync        : CP02 crossed with frame_detect
//    CP04 header_x_sync     : header type crossed with frame_detect
//    CP05 consec_frames     : consecutive-frame count at header validation
//    CP06 reject_kind       : what followed a header LSB when it was rejected
//    CP07 gap_in_sync       : header-less bytes before a header while aligned,
//                             with dedicated bins on the loss threshold
//    CP08 loss_cause        : which byte made alignment drop
//    CP09 pos_x_sync        : fr_byte_position 0..11 crossed with frame_detect
//    CP10 sync_event        : alignment gained / lost
//    CP11 reset_phase       : reset asserted in each phase, aligned or not
//    CP12 payload_header    : header pattern inside a payload (must be ignored)
//    CP13 illegal_len       : stimulus - payload length of illegal frames
//    CP14 item_kind         : stimulus - item kinds sent
//
//  Portability: covergroups are ignored by some simulators (e.g. Verilator
//  5.x), so the model is implemented twice:
//    * fa_cov_point / fa_coverage : a portable collector (associative arrays),
//      used for the report on every simulator;
//    * fa_covergroups             : the same points as native covergroups for
//      tools that support them (merging, UCDB/VDB databases).
//==============================================================================

//------------------------------------------------------------------------------
// One coverage point: an ordered list of named bins and their hit counts.
//------------------------------------------------------------------------------
class fa_cov_point;
  string       name;
  string       descr;
  string       bin_names[$];        // declared bins, in report order
  int unsigned hits[string];        // hit count per bin
  int unsigned undeclared[string];  // values that fell outside every bin

  function new(string name, string descr);
    this.name  = name;
    this.descr = descr;
  endfunction

  function void add_bin(string b);
    bin_names.push_back(b);
    hits[b] = 0;
  endfunction

  function void hit(string b);
    if (hits.exists(b)) hits[b]++;
    else if (undeclared.exists(b)) undeclared[b]++;
    else undeclared[b] = 1;
  endfunction

  function int unsigned covered();
    int unsigned n = 0;
    foreach (bin_names[i]) if (hits[bin_names[i]] > 0) n++;
    return n;
  endfunction

  function real percent();
    return (bin_names.size() == 0) ? 100.0 : 100.0 * covered() / bin_names.size();
  endfunction

  function void report(bit show_bins);
    string holes = "";
    foreach (bin_names[i]) if (hits[bin_names[i]] == 0) holes = {holes, " ", bin_names[i]};
    $display("  %-18s %6.1f%%  (%0d/%0d)  %s", name, percent(), covered(), bin_names.size(), descr);
    if (holes != "") $display("  %-18s   holes:%s", "", holes);
    if (show_bins)
      foreach (bin_names[i]) $display("  %-18s     %-28s %0d", "", bin_names[i], hits[bin_names[i]]);
    foreach (undeclared[k]) $display("  %-18s   note: value '%s' outside declared bins (%0d hits)", "", k, undeclared[k]);
  endfunction
endclass

//------------------------------------------------------------------------------
// Native covergroups (same points; used by simulators that support them).
//------------------------------------------------------------------------------
class fa_covergroups;
  covergroup cg_step with function sample(fa_step_info_t si, rx_class_e rc);
    option.per_instance = 1;
    cp_rx_class : coverpoint rc;
    cp_arc : coverpoint {si.prev_phase, si.new_phase, si.header_rejected} {
      // {prev, new, rejected} with PH_HUNT=0, PH_GOT_LSB=1, PH_IN_FRAME=2
      bins hunt_hunt     = {{32'd0, 32'd0, 1'b0}};
      bins hunt_lsb      = {{32'd0, 32'd1, 1'b0}};
      bins lsb_frame     = {{32'd1, 32'd2, 1'b0}};
      bins lsb_reject    = {{32'd1, 32'd0, 1'b1}};
      bins lsb_restart   = {{32'd1, 32'd1, 1'b1}};
      bins frame_frame   = {{32'd2, 32'd2, 1'b0}};
      bins frame_end     = {{32'd2, 32'd0, 1'b0}};
    }
    cp_sync     : coverpoint si.fd_before;
    cp_arc_sync : cross cp_arc, cp_sync;
    cp_pos      : coverpoint si.pos_after { bins pos[] = {[0:11]}; illegal_bins bad = {[12:15]}; }
    cp_pos_sync : cross cp_pos, cp_sync;
    cp_event    : coverpoint {si.set_event, si.loss_event} { bins gained = {2'b10}; bins lost = {2'b01}; }
    cp_loss     : coverpoint si.loss_cause iff (si.loss_event) {
      bins plain = {LOSS_PLAIN_BYTE}; bins cand_lsb = {LOSS_CANDIDATE_LSB};
      bins rej_msb = {LOSS_REJECTED_MSB}; bins restart = {LOSS_RESTART_LSB};
      illegal_bins on_valid_header = {LOSS_VALID_HEADER, LOSS_IN_FRAME};   // DUT-02
    }
    cp_hdr      : coverpoint si.hdr_type iff (si.header_validated) { bins head1 = {1}; bins head2 = {2}; }
    cp_hdr_sync : cross cp_hdr, cp_sync;
    cp_consec   : coverpoint si.consec_frames iff (si.header_validated) {
      bins one = {1}; bins two = {2}; bins three = {3}; bins more = {[4:$]};
    }
    cp_gap      : coverpoint si.gap_before_header iff (si.header_validated && si.fd_before) {
      bins back2back = {0}; bins g1_11 = {[1:11]}; bins g12_23 = {[12:23]}; bins g24_35 = {[24:35]};
      bins g36_44 = {[36:44]}; bins g45 = {45}; bins g46_last_chance = {46};
    }
    cp_payload_hdr : coverpoint si.payload_header_seen { bins seen = {1}; }
  endgroup

  function new();
    cg_step = new();
  endfunction
endclass

//------------------------------------------------------------------------------
// Portable coverage collector
//------------------------------------------------------------------------------
class fa_coverage;

  fa_cov_point cps[$];
  fa_cov_point cp_rx_class, cp_arc, cp_arc_x_sync, cp_header_x_sync, cp_consec,
               cp_reject_kind, cp_gap_in_sync, cp_loss_cause, cp_pos_x_sync,
               cp_sync_event, cp_reset_phase, cp_payload_header, cp_illegal_len,
               cp_item_kind;
  fa_covergroups cgs;

  local function fa_cov_point mk(string name, string descr, string bin_list[$]);
    fa_cov_point p = new(name, descr);
    foreach (bin_list[i]) p.add_bin(bin_list[i]);
    cps.push_back(p);
    return p;
  endfunction

  static function string arc_name(fa_step_info_t si);
    if (si.prev_phase == PH_HUNT)     return fa_sel(si.new_phase == PH_GOT_LSB, "hunt->lsb", "hunt->hunt");
    if (si.prev_phase == PH_IN_FRAME) return fa_sel(si.new_phase == PH_HUNT, "frame->end", "frame->frame");
    if (si.header_validated)          return "lsb->frame";
    if (si.restart)                   return "lsb->restart";
    return "lsb->reject";
  endfunction

  static function string gap_bin(int unsigned g);
    if (g == 0)  return "0";
    if (g <= 11) return "1-11";
    if (g <= 23) return "12-23";
    if (g <= 35) return "24-35";
    if (g <= 44) return "36-44";
    if (g == 45) return "45";
    if (g == 46) return "46(last chance)";
    return $sformatf("%0d", g);      // > 46 while aligned: impossible per R5
  endfunction

  static function string len_bin(int unsigned n);
    if (n == 0)  return "0";
    if (n <= 9)  return "1-9";
    if (n == 10) return "10";
    if (n <= 46) return "11-46";
    return "47";
  endfunction

  function new();
    string arcs[$] = '{"hunt->hunt", "hunt->lsb", "lsb->frame", "lsb->reject", "lsb->restart",
                       "frame->frame", "frame->end"};
    string arcs_x[$], pos_x[$];
    foreach (arcs[i]) begin arcs_x.push_back({arcs[i], "/fd0"}); arcs_x.push_back({arcs[i], "/fd1"}); end
    for (int p = 0; p < 12; p++) begin pos_x.push_back($sformatf("pos%0d/fd0", p)); pos_x.push_back($sformatf("pos%0d/fd1", p)); end

    cp_rx_class      = mk("CP01 rx_class", "byte classes on rx_data",
                          '{"RX_H1_LSB", "RX_H2_LSB", "RX_H1_MSB", "RX_H2_MSB", "RX_ZERO", "RX_ONES", "RX_OTHER"});
    cp_arc           = mk("CP02 arc", "aligner transitions (R1-R3)", arcs);
    cp_arc_x_sync    = mk("CP03 arc_x_sync", "transitions x frame_detect", arcs_x);
    cp_header_x_sync = mk("CP04 header_x_sync", "header type x frame_detect",
                          '{"HEAD_1/fd0", "HEAD_1/fd1", "HEAD_2/fd0", "HEAD_2/fd1"});
    cp_consec        = mk("CP05 consec_frames", "consecutive frames at validation (R4)",
                          '{"1", "2", "3", "4+"});
    cp_reject_kind   = mk("CP06 reject_kind", "byte that followed a rejected LSB (R2)",
                          '{"AA+same_lsb", "AA+other_lsb", "AA+other_msb", "AA+zero", "AA+other",
                            "55+same_lsb", "55+other_lsb", "55+other_msb", "55+zero", "55+other"});
    cp_gap_in_sync   = mk("CP07 gap_in_sync", "header-less bytes before a header while aligned (R5)",
                          '{"0", "1-11", "12-23", "24-35", "36-44", "45", "46(last chance)"});
    cp_loss_cause    = mk("CP08 loss_cause", "byte that caused loss of alignment (R5)",
                          '{"LOSS_PLAIN_BYTE", "LOSS_CANDIDATE_LSB", "LOSS_REJECTED_MSB", "LOSS_RESTART_LSB"});
    cp_pos_x_sync    = mk("CP09 pos_x_sync", "fr_byte_position x frame_detect (R6)", pos_x);
    cp_sync_event    = mk("CP10 sync_event", "alignment gained / lost", '{"gained", "lost"});
    cp_reset_phase   = mk("CP11 reset_phase", "async reset in each phase (R7)",
                          '{"PH_HUNT/fd0", "PH_HUNT/fd1", "PH_GOT_LSB/fd0", "PH_GOT_LSB/fd1",
                            "PH_IN_FRAME/fd0", "PH_IN_FRAME/fd1"});
    cp_payload_header = mk("CP12 payload_header", "header pattern inside a payload (R3)", '{"fd0", "fd1"});
    cp_illegal_len   = mk("CP13 illegal_len", "stimulus: illegal-frame payload length",
                          '{"0", "1-9", "10", "11-46", "47"});
    cp_item_kind     = mk("CP14 item_kind", "stimulus: item kinds (random + directed)",
                          '{"IK_VALID", "IK_ILLEGAL", "IK_RESTART", "IK_GAP", "IK_RESET", "IK_RAW"});
    cgs = new();
  endfunction

  //---------------------------------------------------------------------------
  // Sampling
  //---------------------------------------------------------------------------
  // Called by the scoreboard for every byte consumed (model step info).
  function void sample_step(fa_step_info_t si);
    string fd = fa_sel(si.fd_before, "fd1", "fd0");
    string arc = arc_name(si);
    cp_rx_class.hit(fa_rx_class(si.data).name());
    cp_arc.hit(arc);
    cp_arc_x_sync.hit({arc, "/", fd});
    cp_pos_x_sync.hit($sformatf("pos%0d/%s", si.pos_after, fa_sel(si.fd_after, "fd1", "fd0")));
    if (si.header_validated) begin
      cp_header_x_sync.hit({fa_sel(si.hdr_type == 1, "HEAD_1", "HEAD_2"), "/", fd});
      cp_consec.hit(fa_sel(si.consec_frames >= 4, "4+", $sformatf("%0d", si.consec_frames)));
      if (si.fd_before) begin
        cp_gap_in_sync.hit(gap_bin(si.gap_before_header));
      end
    end
    if (si.header_rejected) begin
      string l = fa_sel(si.rejected_lsb == HEAD1_LSB, "AA", "55");
      string k;
      if (si.data == si.rejected_lsb)  k = "same_lsb";
      else if (fa_is_lsb(si.data))     k = "other_lsb";
      else if (fa_is_msb(si.data))     k = "other_msb";
      else if (si.data == 8'h00)       k = "zero";
      else                             k = "other";
      cp_reject_kind.hit({l, "+", k});
    end
    if (si.loss_event) cp_loss_cause.hit(si.loss_cause.name());
    if (si.set_event)  cp_sync_event.hit("gained");
    if (si.loss_event) cp_sync_event.hit("lost");
    if (si.payload_header_seen) cp_payload_header.hit(fd);
    cgs.cg_step.sample(si, fa_rx_class(si.data));
  endfunction

  // Called by the scoreboard when a reset starts.
  function void sample_reset(fa_phase_e ph, bit fd);
    cp_reset_phase.hit($sformatf("%s/fd%0d", ph.name(), fd));
  endfunction

  // Called by the generator for every stimulus item.
  function void sample_item(transaction tr);
    cp_item_kind.hit(tr.item_kind.name());
    if (tr.item_kind == transaction::IK_ILLEGAL) begin
      int unsigned n = tr.payload.size();
      cp_illegal_len.hit(len_bin(n));
    end
  endfunction

  //---------------------------------------------------------------------------
  // Reporting
  //---------------------------------------------------------------------------
  function real total_percent();
    int unsigned c = 0, n = 0;
    foreach (cps[i]) begin c += cps[i].covered(); n += cps[i].bin_names.size(); end
    return (n == 0) ? 0.0 : 100.0 * c / n;
  endfunction

  function void report(bit show_bins = 0);
    $display("---------------------------------------------------------------------------");
    $display(" FUNCTIONAL COVERAGE (portable collector)   total %0.1f%% of bins", total_percent());
    $display("---------------------------------------------------------------------------");
    foreach (cps[i]) cps[i].report(show_bins);
  endfunction

endclass
