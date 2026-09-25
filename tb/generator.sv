//==============================================================================
// generator -- builds the complete stimulus stream for the selected test
//------------------------------------------------------------------------------
//  The generator runs before the driver starts (zero simulation time) and puts
//  every item into the unbounded gen2drv mailbox.  It keeps track of the
//  stream index of every byte so that scenarios can attach checkpoints
//  ("after this byte frame_detect must be 1") to exact positions.
//
//  Tests (select with +TEST=<name>):
//    regression (default) : directed + boundary + random
//    directed             : every directed scenario, each starting from reset
//    boundary             : systematic sweep of the 48-byte loss threshold
//    random               : constrained-random items (+NUM_ITEMS=<n>, default 400)
//    file                 : replay a raw stimulus file (+STIM_FILE=<path>), one
//                           hex word per line: bit 8 = reset cycle, bits 7:0 =
//                           byte (the format written by scripts/fuzz_rtl.py
//                           --write-stim), so the SV reference model can be
//                           cross-checked on the fuzzing traffic
//    <scenario name>      : a single directed scenario (see sequence_lib.sv)
//
//  Legacy defects fixed here:
//    * the legacy end-of-test compared driven *transactions* with
//      repeat_count although directed tests send several transactions each,
//      so ~13% of the queued stimulus was never driven.  The environment now
//      waits for every queued item (items_queued) to be driven;
//    * directed tests ran in random order, so preconditions such as "while
//      frame_detect is high" were not guaranteed.  Every directed scenario
//      now starts from reset and builds its own preconditions;
//    * test IDs were printed as numbers; names are printed now.
//==============================================================================
class generator;

  std::mailbox #(transaction) gen2drv;
  fa_checkpoint_db       cps;
  fa_coverage            cov;
  fa_sequence_lib        lib;

  string       test_name        = "regression";
  int unsigned num_random_items = 400;
  string       stim_file        = "";

  int unsigned bytes_queued;     // stream index of the next byte
  int unsigned items_queued;
  string       cur_scenario = "";
  string       scenarios_run[$];

  function new(std::mailbox #(transaction) gen2drv, fa_checkpoint_db cps, fa_coverage cov);
    this.gen2drv = gen2drv;
    this.cps     = cps;
    this.cov     = cov;
    this.lib     = new(this);
  endfunction

  //---------------------------------------------------------------------------
  // Low-level stream API (used by the sequence library)
  //---------------------------------------------------------------------------
  task put_item(transaction tr);
    tr.first_byte_idx = bytes_queued;
    bytes_queued     += tr.frame.size();
    items_queued++;
    cov.sample_item(tr);
    fa_info(2, "GENERATOR", $sformatf("item %0d: %s", items_queued, tr.convert2string()));
    gen2drv.put(tr);
  endtask

  task put_bytes(byte_q_t q, string label);
    transaction tr = transaction::from_bytes(q, label);
    put_item(tr);
  endtask

  task put_reset(int unsigned cycles, string label = "", int unsigned idle_before = 2);
    transaction tr = transaction::reset_req(cycles, label, idle_before);
    put_item(tr);
  endtask

  // Weighted draw: returns index i with probability w[i] / sum(w).
  static function int pick(int w[]);
    int total = 0, r;
    foreach (w[i]) total += w[i];
    r = $urandom_range(0, total - 1);
    foreach (w[i]) begin
      if (r < w[i]) return i;
      r -= w[i];
    end
    return 0;
  endfunction

  // Randomised item for the random test.
  // The enum choices (item kind, header type, how an illegal header is
  // broken) are drawn here with explicit weights and then fixed with inline
  // constraints; lengths are left to the class constraints.  Reason: some
  // solvers do not honour 'dist' weights on enums (measured with Verilator
  // 5.048: 16% resets instead of 2%), which would silently skew the traffic.
  // The weights below are the ones documented in transaction.sv.
  task put_random_item();
    transaction                 tr = new();
    transaction::item_kind_t    k  = transaction::item_kind_t'(pick('{60, 18, 8, 12, 2}));
    transaction::header_type_t  h  = transaction::header_type_t'(pick('{50, 50}));
    transaction::illegal_kind_t ik = transaction::illegal_kind_t'(pick('{40, 20, 15, 15, 10}));
    if (k == transaction::IK_ILLEGAL) h = transaction::ILLEGAL;
    if (!tr.randomize() with { item_kind == k; header_type == h; illegal_kind == ik; }) begin
      fa_error("GENERATOR", "randomization failed");
      return;
    end
    put_item(tr);
  endtask

  // Checkpoints refer to the last byte queued so far.
  function void expect_fd(bit value, string descr);
    if (bytes_queued == 0) return;
    cps.add(bytes_queued - 1, "frame_detect", value, descr, cur_scenario);
  endfunction

  function void expect_pos(int value, string descr);
    if (bytes_queued == 0) return;
    cps.add(bytes_queued - 1, "fr_byte_position", value, descr, cur_scenario);
  endfunction

  function void begin_scenario(string name, string purpose);
    cur_scenario = name;
    scenarios_run.push_back(name);
    fa_info(1, "GENERATOR", $sformatf("scenario %-28s : %s", name, purpose));
  endfunction

  //---------------------------------------------------------------------------
  // Test selection
  //---------------------------------------------------------------------------
  task run_random();
    begin_scenario("random", $sformatf("%0d constrained-random items", num_random_items));
    put_reset(2, "random: start from reset");
    repeat (num_random_items) put_random_item();
  endtask

  // Replay a raw stimulus file.  Consecutive reset words become one reset
  // item; bytes are sent in chunks of up to 4096.
  task run_file();
    int          fd, code;
    int unsigned w, n_words, pending_reset;
    byte_q_t     q;
    begin_scenario("file", {"raw stimulus from ", stim_file});
    put_reset(2, "file: start from reset");
    fd = $fopen(stim_file, "r");
    if (fd == 0) begin
      fa_error("GENERATOR", $sformatf("cannot open +STIM_FILE=%s", stim_file));
      return;
    end
    while (1) begin
      code = $fscanf(fd, "%h", w);
      if (code != 1) break;
      n_words++;
      if (w[8]) begin
        if (q.size() > 0) begin put_bytes(q, "file bytes"); q.delete(); end
        pending_reset++;
      end else begin
        if (pending_reset > 0) begin put_reset(pending_reset, "file: reset"); pending_reset = 0; end
        q.push_back(w[7:0]);
        if (q.size() == 4096) begin put_bytes(q, "file bytes"); q.delete(); end
      end
    end
    if (q.size() > 0) put_bytes(q, "file bytes");
    $fclose(fd);
    fa_info(1, "GENERATOR", $sformatf("read %0d words from %s", n_words, stim_file));
  endtask

  task run();
    bit found;
    case (test_name)
      "regression": begin
        lib.run_all_directed();
        lib.boundary_sweep();
        run_random();
      end
      "directed": lib.run_all_directed();
      "boundary": lib.boundary_sweep();
      "random":   run_random();
      "file":     run_file();
      default: begin
        lib.run_by_name(test_name, found);
        if (!found) begin
          fa_error("GENERATOR", $sformatf("unknown test '%s'. Known: regression directed boundary random file %s",
                                          test_name, lib.names2str()));
        end
      end
    endcase
    fa_info(1, "GENERATOR", $sformatf("test '%s': %0d items, %0d bytes, %0d checkpoints queued",
                                      test_name, items_queued, bytes_queued, cps.n_added));
  endtask

endclass
