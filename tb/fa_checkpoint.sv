//==============================================================================
// Monitor sample item and test-plan checkpoints
//==============================================================================

//------------------------------------------------------------------------------
// mon_item -- what a monitor observed at one rising clock edge.
//   monitor_in  fills: cycle, reset, rx_data, byte_idx, byte_valid
//   monitor_out fills: cycle, fr_byte_position, frame_detect
// Output fields are 4-state on purpose: an X/Z on a DUT output must be seen by
// the scoreboard (the legacy scoreboard stored them in 2-state 'bit'
// variables, which silently turned X into 0).
//------------------------------------------------------------------------------
class mon_item;
  longint unsigned cycle;          // sample number since the monitors started
  logic            reset;
  logic [7:0]      rx_data;
  int unsigned     byte_idx;       // stream index of rx_data (driver side band)
  logic            byte_valid;     // 0 = idle filler byte (no stream index)
  logic [3:0]      fr_byte_position;
  logic            frame_detect;

  function string in2string();
    return $sformatf("cyc=%0d rst=%b rx=%02h idx=%0d%s", cycle, reset, rx_data, byte_idx,
                     fa_sel(byte_valid === 1'b1, "", "(idle)"));
  endfunction

  function string out2string();
    return $sformatf("cyc=%0d pos=%0d fd=%b", cycle, fr_byte_position, frame_detect);
  endfunction
endclass

//------------------------------------------------------------------------------
// fa_checkpoint -- an expected outcome from the test plan, attached to a byte.
//   "after the DUT has consumed byte <byte_idx>, <signal> must equal <value>"
// Checkpoints are written by the directed scenarios (tb/sequence_lib.sv) and
// evaluated by the scoreboard at exactly that cycle.  They are a second,
// independent oracle next to the cycle-by-cycle reference model: they encode
// the "Expected Outcome" column of the test plan.
//------------------------------------------------------------------------------
class fa_checkpoint;
  int unsigned byte_idx;
  string       signal;     // "frame_detect" or "fr_byte_position"
  int          value;
  string       descr;
  string       scenario;
endclass

class fa_checkpoint_db;
  fa_checkpoint q[$];                 // pending checkpoints, in stream order
  int unsigned  n_added, n_passed, n_failed;
  string        failures[$];

  function void add(int unsigned byte_idx, string signal, int value, string descr, string scenario);
    fa_checkpoint c = new();
    c.byte_idx = byte_idx;
    c.signal   = signal;
    c.value    = value;
    c.descr    = descr;
    c.scenario = scenario;
    q.push_back(c);
    n_added++;
  endfunction

  // Evaluate every checkpoint attached to byte 'idx' against the DUT outputs
  // observed after that byte was consumed.
  function void evaluate(int unsigned idx, logic [3:0] pos, logic fd);
    while (q.size() > 0 && q[0].byte_idx < idx) begin
      // The byte was never observed (e.g. swallowed by a reset): report it.
      fa_checkpoint c = q.pop_front();
      n_failed++;
      failures.push_back($sformatf("%s: '%s' at byte %0d was never evaluated", c.scenario, c.descr, c.byte_idx));
      fa_error("CHECKPOINT", failures[$]);
    end
    while (q.size() > 0 && q[0].byte_idx == idx) begin
      fa_checkpoint c   = q.pop_front();
      logic [3:0]   got = (c.signal == "frame_detect") ? {3'b000, fd} : pos;
      if (got === c.value[3:0]) begin
        n_passed++;
        fa_info(2, "CHECKPOINT", $sformatf("PASS %s: %s (%s=%0d after byte %0d)",
                                            c.scenario, c.descr, c.signal, c.value, c.byte_idx));
      end else begin
        n_failed++;
        failures.push_back($sformatf("%s: %s -- expected %s=%0d after byte %0d, DUT shows %0d",
                                     c.scenario, c.descr, c.signal, c.value, c.byte_idx, got));
        fa_error("CHECKPOINT", failures[$]);
      end
    end
  endfunction

  function int unsigned pending();
    return q.size();
  endfunction
endclass
