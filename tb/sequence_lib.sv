//==============================================================================
// fa_sequence_lib -- directed test scenarios (the test plan, executable)
//------------------------------------------------------------------------------
//  Every scenario
//    * starts from reset, so its preconditions are guaranteed (the legacy
//      tests were shuffled randomly, so e.g. "while frame_detect is high" was
//      not actually established);
//    * builds its bytes explicitly with 2-state values (several legacy tests
//      left most bytes uninitialised and drove X into the DUT);
//    * attaches checkpoints = the "Expected Outcome" column of the test plan,
//      derived from the specification rules R1..R7 (tb/fa_ref_model.sv), NOT
//      from what the RTL happens to do.
//  The reference model additionally checks every single byte.
//
//  Test-plan ID -> scenario (docs/VERIFICATION_PLAN.md §4 has the full table;
//  "legacy:" names the original test file that the scenario replaces)
//    TP01 spec_suggested        5xHEAD_1, 4 illegal, 5xHEAD_2 (spec p.23)   legacy: test_5_head1/_4_illegal/_5_head2
//    TP02 mixed_headers         HEAD_1/HEAD_2 mixed                           legacy: test_3_random_valid_headers
//    TP03 swapped_header        MSB before LSB                                legacy: test_header_swapped__lsb_msb
//    TP04 inverted_header       bit-inverted and bit-reversed headers         legacy: test_reversed_bit_headers
//    TP05 lsb_ok_msb_bad        valid LSB, wrong MSB                          legacy: test_correct_lsb_invalid_msb
//    TP06 lsb_bad_msb_ok        wrong LSB, valid MSB                          legacy: test_correct_msb_invalid_lsb
//    TP07 msb_in_payload        header MSB bytes inside payloads              legacy: test_msb_and_lsb_and_valid_header_in_middle_frame
//    TP08 header_in_payload     full headers inside payloads are ignored      legacy: (same)
//    TP09 restart_header        stray LSB(s) right before a header  (DUT-01)  legacy: test_47_bytes (first part)
//    TP10 loss_boundary         45/46/47/48 header-less bytes      (DUT-02)   legacy: test_45/46/47/48_bytes
//    TP11 corrupted_frames      1..4 corrupted frames while aligned (DUT-03)  new
//    TP12 header_in_illegal     header inside an illegal frame                legacy: test_illegal_headers_with_a_valid_header_in_the_middle_frame(_10_clock)
//    TP13 frames_in_illegal     3 frames inside an illegal frame              legacy: test_3_valid_frames_in_the_invalid_frame
//    TP14 header_soup           49-byte frames of random header bytes         legacy: ..._middle_frame_random
//    TP15 lsb_at_payload_end    header LSB/MSB as last payload bytes          new
//    TP16 long_valid_run        10 consecutive frames              (DUT-04)   new
//    TP17 long_garbage          80 header-less bytes               (DUT-05)   new
//    TP18 reset_every_phase     async reset while hunting / LSB / in frame, aligned or not
//    TP19 false_lock_in_sync    corrupted header + header in payload (SPEC-03) new
//    TP20 consecutive_rule      a single hunting byte breaks the frame chain  new
//    TP21 header_across_items   header split across two stimulus items        new
//    TP22 illegal_lengths       illegal frames of 2..49 bytes while aligned   new
//    TP23 boundary (sweep)      0..60 header-less bytes x {no prefix, stray LSB}
//    TP24 loss_cause            48th byte = rejected MSB / restart LSB; restart while aligned
//    TP25 midstream_entry       start mid-stream, payloads end in AA/55    (DUT-01: never aligns)
//    TP26 error_then_lsb_payloads one header error, payloads end in 55  (DUT-01: permanent loss)
//    TP27 slip_in_sync          13-byte frames before/after alignment      (DUT-07 demonstration)
//==============================================================================
class fa_sequence_lib;

  generator gen;

  // Directed scenarios in execution order.
  string names[$] = '{
    "spec_suggested", "mixed_headers", "swapped_header", "inverted_header",
    "lsb_ok_msb_bad", "lsb_bad_msb_ok", "msb_in_payload", "header_in_payload",
    "restart_header", "loss_boundary", "corrupted_frames", "header_in_illegal",
    "frames_in_illegal", "header_soup", "lsb_at_payload_end", "long_valid_run",
    "long_garbage", "reset_every_phase", "false_lock_in_sync", "consecutive_rule",
    "header_across_items", "illegal_lengths", "loss_cause", "midstream_entry",
    "error_then_lsb_payloads", "slip_in_sync"};

  function new(generator gen);
    this.gen = gen;
  endfunction

  function string names2str();
    string s = "";
    foreach (names[i]) s = {s, fa_sel(i == 0, "", " "), names[i]};
    return s;
  endfunction

  //===========================================================================
  // Byte builders
  //===========================================================================
  // Header bytes: ht = 1 -> AA AF, ht = 2 -> 55 BA, ht = 0 -> random type.
  function byte_q_t hdr(int ht);
    byte_q_t q;
    if (ht == 0) ht = $urandom_range(1, 2);
    if (ht == 1) q = '{HEAD1_LSB, HEAD1_MSB};
    else         q = '{HEAD2_LSB, HEAD2_MSB};
    return q;
  endfunction

  // A single byte as a queue.
  function byte_q_t one(byte unsigned b);
    byte_q_t q;
    q.push_back(b);
    return q;
  endfunction

  // Bit-reversed byte (bit 7 <-> bit 0, ...).
  function byte unsigned bitrev(byte unsigned b);
    byte unsigned r = 0;
    for (int i = 0; i < 8; i++) r[i] = b[7 - i];
    return r;
  endfunction

  // n bytes that are none of AA/55/AF/BA (can never form or start a header).
  function byte_q_t clean(int n);
    byte_q_t q;
    repeat (n) q.push_back(transaction::clean_byte());
    return q;
  endfunction

  // n completely random bytes.
  function byte_q_t rnd(int n);
    byte_q_t q;
    repeat (n) q.push_back(transaction::any_byte());
    return q;
  endfunction

  // A complete valid frame.  The payload is clean by default so that a
  // directed scenario is never disturbed by an accidental pattern.
  function byte_q_t frame(int ht = 0, bit clean_payload = 1);
    byte_q_t q = hdr(ht);
    byte_q_t p = clean_payload ? clean(PAYLOAD_LEN) : rnd(PAYLOAD_LEN);
    return {q, p};
  endfunction

  // A 12-byte frame whose header is broken as 'lsb msb' (payload clean).
  function byte_q_t broken_frame(byte unsigned lsb, byte unsigned msb);
    byte_q_t q = '{lsb, msb};
    byte_q_t p = clean(PAYLOAD_LEN);
    return {q, p};
  endfunction

  //===========================================================================
  // Stream helpers
  //===========================================================================
  task start(string name, string purpose);
    gen.begin_scenario(name, purpose);
    gen.put_reset(2, {name, ": reset"});
  endtask

  task send(byte_q_t q, string label);
    gen.put_bytes(q, {gen.cur_scenario, ": ", label});
  endtask

  // Send the first n bytes of q (n <= size), return the rest in q.
  task send_part(ref byte_q_t q, input int n, input string label);
    byte_q_t head;
    repeat (n) head.push_back(q.pop_front());
    send(head, label);
  endtask

  // Send one valid frame in three pieces with checkpoints in between.
  // A value of -1 skips that checkpoint.
  //   msb_pos/msb_fd : outputs after the header MSB
  //   p0_fd          : frame_detect after payload byte 0 (alignment rises here)
  //   end_fd         : frame_detect after the last payload byte
  task frame_checked(int ht, int msb_pos, int msb_fd, int p0_fd, int end_fd, string tag);
    byte_q_t q = frame(ht);
    send_part(q, 2, {tag, " header"});
    if (msb_pos >= 0) gen.expect_pos(msb_pos, {tag, ": header recognised (pos=1 after MSB)"});
    if (msb_fd  >= 0) gen.expect_fd(msb_fd[0], {tag, ": frame_detect after the header MSB"});
    send_part(q, 1, {tag, " payload[0]"});
    if (p0_fd   >= 0) gen.expect_fd(p0_fd[0], {tag, ": frame_detect after payload[0]"});
    send(q, {tag, " payload[1..9]"});
    if (msb_pos == 1) gen.expect_pos(11, {tag, ": last payload byte has position 11"});
    if (end_fd  >= 0) gen.expect_fd(end_fd[0], {tag, ": frame_detect after the frame"});
  endtask

  // Three valid frames from a non-aligned state: alignment must rise exactly
  // one byte after the third header (R4, spec waveform 1).
  task sync(string tag = "sync");
    frame_checked(0, 1, 0, 0, 0, {tag, " frame 1"});
    frame_checked(0, 1, 0, 0, 0, {tag, " frame 2"});
    frame_checked(0, 1, 0, 1, 1, {tag, " frame 3"});
  endtask

  // Send header-less bytes while aligned and check the loss instant (R5):
  // aligned after 47 such bytes, not aligned after the 48th.  'already' is the
  // number of header-less bytes consumed before q.
  task hdrless_with_loss_check(byte_q_t q, int already, string tag);
    int n_to_47 = (LOSS_BYTES - 1) - already;
    if (n_to_47 > 0 && q.size() > n_to_47) begin
      send_part(q, n_to_47, {tag, " (up to 47 header-less bytes)"});
      gen.expect_fd(1, {tag, ": still aligned after 47 header-less bytes"});
      send_part(q, 1, {tag, " (48th header-less byte)"});
      gen.expect_fd(0, {tag, ": alignment lost on the 48th header-less byte"});
    end
    if (q.size() > 0) send(q, {tag, " (rest)"});
  endtask

  //===========================================================================
  // Directed scenarios
  //===========================================================================

  // TP01 -- the test suggested by the specification (p.23).
  task spec_suggested();
    byte_q_t q;
    start("spec_suggested", "5 x HEAD_1, 4 illegal frames, 5 x HEAD_2 (spec p.23)");
    frame_checked(1, 1, 0, 0, 0, "HEAD_1 #1");
    frame_checked(1, 1, 0, 0, 0, "HEAD_1 #2");
    frame_checked(1, 1, 0, 1, 1, "HEAD_1 #3");
    frame_checked(1, 1, 1, 1, 1, "HEAD_1 #4");
    frame_checked(1, 1, 1, 1, 1, "HEAD_1 #5");
    // 4 illegal frames of 12 header-less bytes = 48 bytes -> loss (R5)
    q = {broken_frame(8'h01, 8'h02), broken_frame(8'h03, 8'h04),
         broken_frame(8'h05, 8'h06), broken_frame(8'h07, 8'h08)};
    hdrless_with_loss_check(q, 0, "4 illegal frames");
    frame_checked(2, 1, 0, 0, 0, "HEAD_2 #1");
    frame_checked(2, 1, 0, 0, 0, "HEAD_2 #2");
    frame_checked(2, 1, 0, 1, 1, "HEAD_2 #3");
    frame_checked(2, 1, 1, 1, 1, "HEAD_2 #4");
    frame_checked(2, 1, 1, 1, 1, "HEAD_2 #5");
  endtask

  // TP02 -- header types may be mixed freely.
  task mixed_headers();
    start("mixed_headers", "HEAD_1/HEAD_2/HEAD_1 aligns; any mix of types counts");
    frame_checked(1, 1, 0, 0, 0, "HEAD_1");
    frame_checked(2, 1, 0, 0, 0, "HEAD_2");
    frame_checked(1, 1, 0, 1, 1, "HEAD_1");
    start("mixed_headers", "HEAD_2/HEAD_1/HEAD_2");
    frame_checked(2, 1, 0, 0, 0, "HEAD_2");
    frame_checked(1, 1, 0, 0, 0, "HEAD_1");
    frame_checked(2, 1, 0, 1, 1, "HEAD_2");
    frame_checked(1, 1, 1, 1, 1, "HEAD_1");
  endtask

  // TP03 -- MSB before LSB is not a header.
  task swapped_header();
    byte_q_t q;
    start("swapped_header", "AF AA / BA 55 are not headers (never aligns)");
    repeat (3) begin
      send(broken_frame(HEAD1_MSB, HEAD1_LSB), "AF AA + payload");
      send(broken_frame(HEAD2_MSB, HEAD2_LSB), "BA 55 + payload");
    end
    gen.expect_fd(0, "six swapped headers never align");
    start("swapped_header", "4 swapped-header frames while aligned = 48 header-less bytes");
    sync();
    q = {broken_frame(HEAD1_MSB, HEAD1_LSB), broken_frame(HEAD2_MSB, HEAD2_LSB),
         broken_frame(HEAD1_MSB, HEAD1_LSB), broken_frame(HEAD2_MSB, HEAD2_LSB)};
    hdrless_with_loss_check(q, 0, "4 swapped frames");
  endtask

  // TP04 -- inverted (~) and bit-reversed headers.  Note: both operations map
  // AA <-> 55, so these "headers" start with a VALID LSB of the other type and
  // exercise the rejected-MSB path (the legacy test called the inverted
  // pattern "reversed bits").
  task inverted_header();
    start("inverted_header", "~AFAA=50 55, ~BA55=45 AA, bitrev AFAA=F5 55, bitrev BA55=5D AA");
    repeat (2) begin
      send(broken_frame(~HEAD1_LSB, ~HEAD1_MSB), "inverted HEAD_1 (55 50)");
      send(broken_frame(~HEAD2_LSB, ~HEAD2_MSB), "inverted HEAD_2 (AA 45)");
      send(broken_frame(bitrev(HEAD1_LSB), bitrev(HEAD1_MSB)), "bit-reversed HEAD_1 (55 F5)");
      send(broken_frame(bitrev(HEAD2_LSB), bitrev(HEAD2_MSB)), "bit-reversed HEAD_2 (AA 5D)");
    end
    gen.expect_fd(0, "inverted / reversed headers never align");
  endtask

  // TP05 -- valid LSB, wrong MSB: rejected, and no frame position is reported.
  task lsb_ok_msb_bad();
    byte unsigned bad[6][2] = '{'{HEAD1_LSB, 8'h01}, '{HEAD2_LSB, 8'h01}, '{HEAD1_LSB, 8'h00},
                                '{HEAD2_LSB, 8'h00}, '{HEAD1_LSB, HEAD2_MSB}, '{HEAD2_LSB, HEAD1_MSB}};
    start("lsb_ok_msb_bad", "AA 01, 55 01, AA 00, 55 00, AA BA, 55 AF are rejected; position stays 0 (R6)");
    foreach (bad[i]) begin
      byte_q_t q = broken_frame(bad[i][0], bad[i][1]);
      send_part(q, 2, $sformatf("%02h %02h", bad[i][0], bad[i][1]));
      gen.expect_pos(0, $sformatf("%02h %02h rejected: no frame, position 0", bad[i][0], bad[i][1]));
      send(q, "payload");
    end
    gen.expect_fd(0, "rejected headers never align");
  endtask

  // TP06 -- wrong LSB, valid MSB.
  task lsb_bad_msb_ok();
    start("lsb_bad_msb_ok", "0A AF and 05 BA are not headers");
    repeat (3) begin
      byte_q_t q = broken_frame(8'h0A, HEAD1_MSB);
      send_part(q, 2, "0A AF");
      gen.expect_pos(0, "0A AF: no frame");
      send(q, "payload");
      q = broken_frame(8'h05, HEAD2_MSB);
      send_part(q, 2, "05 BA");
      gen.expect_pos(0, "05 BA: no frame");
      send(q, "payload");
    end
    gen.expect_fd(0, "never aligns");
  endtask

  // TP07 -- header MSB bytes inside payloads have no effect.
  task msb_in_payload();
    start("msb_in_payload", "AF/BA bytes inside payloads are ignored");
    sync();
    repeat (4) begin
      byte_q_t q = hdr(0);
      byte_q_t p = clean(PAYLOAD_LEN);
      p[$urandom_range(0, 9)] = HEAD1_MSB;
      p[$urandom_range(0, 9)] = HEAD2_MSB;
      send({q, p}, "frame with MSB bytes in payload");
      gen.expect_pos(11, "frame boundary unchanged");
      gen.expect_fd(1, "still aligned");
    end
  endtask

  // TP08 -- complete headers inside payloads are ignored (R3).
  task header_in_payload();
    start("header_in_payload", "AA AF / 55 BA inside payloads (every offset) are ignored");
    sync();
    for (int off = 0; off <= PAYLOAD_LEN - 2; off++) begin
      byte_q_t q = hdr(0);
      byte_q_t p = clean(PAYLOAD_LEN);
      byte_q_t h = hdr(0);
      p[off] = h[0];
      p[off + 1] = h[1];
      send({q, p}, $sformatf("header at payload offset %0d", off));
      gen.expect_pos(11, "frame boundary unchanged");
      gen.expect_fd(1, "still aligned");
    end
    start("header_in_payload", "embedded header does not disturb alignment from reset");
    begin
      byte_q_t q = hdr(1);
      byte_q_t p = clean(PAYLOAD_LEN);
      p[4] = HEAD2_LSB; p[5] = HEAD2_MSB;
      send({q, p}, "frame 1 with header in payload");
      gen.expect_pos(11, "frame 1 boundary unchanged");
    end
    frame_checked(0, 1, 0, 0, 0, "frame 2");
    frame_checked(0, 1, 0, 1, 1, "frame 3");
  endtask

  // TP09 -- stray header LSB(s) right before a header (R2).  The header must
  // still be found and three frames must align.  Exposes DUT-01.
  task restart_header();
    // prefix bytes (pre_len of pre0, pre1), header type of frame 1, description
    byte unsigned pre0[6]   = '{HEAD1_LSB, HEAD2_LSB, HEAD1_LSB, HEAD2_LSB, HEAD1_LSB, HEAD2_LSB};
    byte unsigned pre1[6]   = '{8'h00,     8'h00,     8'h00,     8'h00,     HEAD1_LSB, HEAD1_LSB};
    int           pre_len[6] = '{1, 1, 1, 1, 2, 2};
    int           ht[6]      = '{1, 2, 2, 1, 1, 2};
    string        what[6]    = '{"AA | AA AF", "55 | 55 BA", "AA | 55 BA", "55 | AA AF",
                                 "AA AA | AA AF", "55 AA | 55 BA"};
    foreach (ht[i]) begin
      byte_q_t p = one(pre0[i]);
      if (pre_len[i] == 2) p.push_back(pre1[i]);
      start("restart_header", {what[i], " + 2 frames must align"});
      send(p, "stray LSB prefix");
      gen.expect_pos(0, "stray LSB: no frame yet");
      frame_checked(ht[i], 1, 0, 0, 0, {"frame 1 (", what[i], ")"});
      frame_checked(0, 1, 0, 0, 0, "frame 2");
      frame_checked(0, 1, 0, 1, 1, "frame 3");
    end
  endtask

  // TP10 -- the loss threshold (R5).  G header-less bytes after alignment,
  // then a valid header.  G <= 46: the header completes within 48 bytes and
  // alignment is kept.  G = 47: the header LSB is the 48th header-less byte.
  // G = 48: 48 garbage bytes.  Exposes DUT-02 (G = 46).
  task loss_boundary();
    for (int g = 44; g <= 48; g++) begin
      byte_q_t q = clean(g);
      start("loss_boundary", $sformatf("aligned, %0d header-less bytes, then a header", g));
      sync();
      send_part(q, g - 1, $sformatf("%0d header-less bytes", g - 1));
      gen.expect_fd(1, $sformatf("aligned after %0d header-less bytes", g - 1));
      send(q, "last header-less byte");
      gen.expect_fd(g < LOSS_BYTES, $sformatf("after %0d header-less bytes", g));
      frame_checked(1, 1, (g <= 46), (g <= 46), (g <= 46),
                    $sformatf("header after %0d header-less bytes", g));
      frame_checked(2, 1, (g <= 46), (g <= 46), (g <= 46), "next frame");
    end
  endtask

  // TP11 -- 1..4 corrupted frames while aligned.  Spec: out-of-frame after four
  // consecutive incorrect frames (48 bytes).  The corrupted header has a valid
  // LSB, so the position after the rejected MSB is checked too (DUT-03).
  task corrupted_frames();
    for (int n = 1; n <= 4; n++) begin
      byte_q_t q;
      start("corrupted_frames", $sformatf("aligned, %0d frame(s) with a corrupted MSB", n));
      sync();
      repeat (n) q = {q, broken_frame(HEAD1_LSB, 8'h01)};
      send_part(q, 2, "corrupted header AA 01");
      gen.expect_pos(0, "rejected header: position 0");
      if (n < 4) begin
        send(q, "rest of the corrupted frame(s)");
        gen.expect_fd(1, $sformatf("%0d corrupted frame(s): still aligned", n));
        frame_checked(0, 1, 1, 1, 1, "valid frame after the corrupted frames");
      end else begin
        hdrless_with_loss_check(q, 2, "4 corrupted frames");
        sync("re-sync");
      end
    end
  endtask

  // TP12 -- a valid header inside an illegal frame is a valid header (hunting
  // architecture).  Legacy test_illegal_headers_with_a_valid_header_in_the_middle_frame.
  task header_in_illegal();
    byte_q_t q = '{8'hDE, 8'h00, 8'h01, 8'h02, HEAD1_LSB, HEAD1_MSB, 8'h05, 8'h06,
                   HEAD1_LSB, HEAD1_MSB, 8'h07, 8'h08, 8'h08, 8'h08, 8'h08, 8'h08};
    start("header_in_illegal", "illegal frame with a header at byte 4, followed by 2 frames -> aligned");
    send_part(q, 6, "DE 00 01 02 AA AF");
    gen.expect_pos(1, "header at byte 4 recognised");
    send(q, "rest: its frame ends at byte 15 (the header at byte 8 is payload)");
    gen.expect_pos(11, "frame that started at byte 4 ends at byte 15");
    frame_checked(0, 1, 0, 0, 0, "frame 2 (immediately after)");
    frame_checked(0, 1, 0, 1, 1, "frame 3");
    // Legacy 12-byte version: the false frame swallows the first 4 bytes of the
    // next real frame, so that real header is skipped (student finding K7).
    start("header_in_illegal", "12-byte illegal frame: the false frame hides the next real header");
    q = '{8'hDE, 8'h00, 8'h01, 8'h02, HEAD1_LSB, HEAD1_MSB, 8'h05, 8'h06, HEAD1_LSB, HEAD1_MSB, 8'h07, 8'h08};
    send(q, "legacy 12-byte illegal frame");
    send(frame(1), "real frame A (its header falls inside the false frame)");
    frame_checked(0, 1, 0, 0, 0, "real frame B");
    frame_checked(0, 1, 0, 0, 0, "real frame C: only 2 consecutive -> not aligned");
    frame_checked(0, 1, 0, 1, 1, "real frame D: aligned");
  endtask

  // TP13 -- three valid frames inside an illegal frame.
  task frames_in_illegal();
    byte_q_t q;
    start("frames_in_illegal", "49 x 00 with headers at 3, 15, 27 -> aligned");
    repeat (49) q.push_back(8'h00);
    q[3] = HEAD1_LSB; q[4] = HEAD1_MSB; q[15] = HEAD2_LSB; q[16] = HEAD2_MSB;
    q[27] = HEAD2_LSB; q[28] = HEAD2_MSB;
    send_part(q, 29, "bytes 0..28");
    gen.expect_fd(0, "not yet aligned after the 3rd header MSB");
    send_part(q, 1, "byte 29");
    gen.expect_fd(1, "aligned one byte after the 3rd header");
    send(q, "bytes 30..48");
    gen.expect_fd(1, "still aligned");
  endtask

  // TP14 -- frames made of random header bytes only (model-checked).
  task header_soup();
    byte unsigned vals[4] = '{HEAD1_LSB, HEAD1_MSB, HEAD2_LSB, HEAD2_MSB};
    start("header_soup", "3 x (DE 00 + 47 random header bytes); checked by the model");
    repeat (6) begin
      byte_q_t q = '{8'hDE, 8'h00};
      repeat (47) q.push_back(vals[$urandom_range(0, 3)]);
      send(q, "header soup");
    end
  endtask

  // TP15 -- header bytes as the last payload bytes do not disturb the next header.
  task lsb_at_payload_end();
    start("lsb_at_payload_end", "payload ending in AA / 55 / AA AF, followed by a header");
    sync();
    for (int k = 0; k < 3; k++) begin
      byte_q_t q = hdr(0);
      byte_q_t p = clean(PAYLOAD_LEN);
      if (k == 0) p[9] = HEAD1_LSB;
      if (k == 1) p[9] = HEAD2_LSB;
      if (k == 2) begin p[8] = HEAD1_LSB; p[9] = HEAD1_MSB; end
      send({q, p}, $sformatf("frame, payload end variant %0d", k));
      gen.expect_pos(11, "frame ends normally");
      frame_checked(0, 1, 1, 1, 1, "next frame is recognised");
    end
  endtask

  // TP16 -- long run of valid frames (legal-frame counter must not wrap: DUT-04,
  // checked by the white-box assertion).
  task long_valid_run();
    start("long_valid_run", "10 consecutive valid frames");
    sync();
    for (int i = 4; i <= 10; i++) frame_checked(0, 1, 1, 1, 1, $sformatf("frame %0d", i));
  endtask

  // TP17 -- long header-less stream (not-aligned counter must not wrap: DUT-05,
  // checked by the white-box assertion), then re-alignment.
  task long_garbage();
    start("long_garbage", "aligned, 80 header-less bytes, re-align");
    sync();
    hdrless_with_loss_check(clean(80), 0, "80 header-less bytes");
    gen.expect_fd(0, "not aligned");
    sync("re-sync");
  endtask

  // TP18 -- asynchronous reset in every phase, aligned or not (R7).
  task reset_every_phase();
    byte_q_t q;
    for (int aligned = 0; aligned <= 1; aligned++) begin
      string a = fa_sel(aligned, "aligned", "not aligned");
      start("reset_every_phase", {"reset inside a frame, ", a});
      if (aligned) sync();
      q = frame(1);
      send_part(q, 6, "half a frame");
      gen.put_reset(3, "reset inside a frame", 1);
      send(clean(1), "first byte after reset");
      gen.expect_fd(0, "reset clears frame_detect");
      gen.expect_pos(0, "reset clears fr_byte_position");
      sync("after reset");

      start("reset_every_phase", {"reset right after a header LSB, ", a});
      if (aligned) sync();
      send(one(HEAD1_LSB), "header LSB");
      gen.put_reset(1, "reset while a header LSB is pending", 1);
      send(one(HEAD1_MSB), "MSB after reset must not complete a header");
      gen.expect_pos(0, "no header across a reset");
      gen.expect_fd(0, "not aligned after reset");
      send(clean(PAYLOAD_LEN), "payload");

      start("reset_every_phase", {"reset while hunting, ", a});
      if (aligned) sync();
      send(clean(10), "hunting");
      gen.put_reset(2, "reset while hunting", 1);
      sync("after reset");
    end
  endtask

  // TP24 -- every kind of byte that can be the 48th header-less byte (R5),
  // and a header restart while aligned (R2).
  task loss_cause();
    start("loss_cause", "48th header-less byte = a rejected MSB (AA 01)");
    sync();
    send(clean(46), "46 header-less bytes");
    send(one(HEAD1_LSB), "header LSB = 47th byte");
    gen.expect_fd(1, "still aligned after 47 bytes");
    send(one(8'h01), "wrong MSB = 48th byte");
    gen.expect_fd(0, "alignment lost on the rejected MSB");
    start("loss_cause", "48th header-less byte = a wrong MSB that is itself an LSB (AA 55)");
    sync();
    send(clean(46), "46 header-less bytes");
    send(one(HEAD1_LSB), "header LSB = 47th byte");
    send(one(HEAD2_LSB), "other LSB = 48th byte (becomes the new candidate)");
    gen.expect_fd(0, "alignment lost on the restart LSB");
    send(one(HEAD2_MSB), "its MSB completes a header");
    gen.expect_pos(1, "restarted header recognised");
    send(clean(PAYLOAD_LEN), "payload");
    start("loss_cause", "header restart while aligned (AA 55 BA right after a frame)");
    sync();
    send(one(HEAD1_LSB), "stray LSB");
    frame_checked(2, 1, 1, 1, 1, "55 BA frame after the stray LSB");
    frame_checked(0, 1, 1, 1, 1, "next frame");
  endtask

  // TP19 -- SPEC-03 demonstration: no fly-wheel.  While aligned, a corrupted
  // header followed by a header pattern inside that payload makes the aligner
  // lock onto a false frame boundary without dropping frame_detect.  This
  // matches the specified hunting behaviour (so it is not flagged as a bug)
  // but it is a documented limitation of the architecture.
  task false_lock_in_sync();
    byte_q_t q;
    start("false_lock_in_sync", "aligned; corrupted header, header pattern at payload offset 2");
    sync();
    q = broken_frame(HEAD1_LSB, 8'h01);
    q[4] = HEAD2_LSB; q[5] = HEAD2_MSB;
    send_part(q, 6, "corrupted header + false header");
    gen.expect_pos(1, "aligner locked onto the false header (limitation SPEC-03)");
    gen.expect_fd(1, "frame_detect stays high");
    send(q, "rest of the corrupted frame");
    q = frame(1);
    send_part(q, 2, "real next header (inside the false frame)");
    gen.expect_pos(9, "real header is treated as payload of the false frame");
    send(q, "rest of the real frame");
    frame_checked(0, 1, 1, 1, 1, "following real frame is found again");
  endtask

  // TP20 -- "consecutive": a single hunting byte between frames resets the
  // count (R4) -- whether it is an ordinary byte or a stray header LSB that
  // is then rejected/restarted.  (The stray-LSB case was added after mutation
  // testing showed that no scenario checked it: scripts/mutation_test.py M20.)
  task consecutive_rule();
    byte unsigned stray[2] = '{HEAD1_LSB, HEAD2_LSB};
    start("consecutive_rule", "V, 1 byte gap, V, V -> not aligned; + V -> aligned");
    frame_checked(0, 1, 0, 0, 0, "frame 1");
    send(clean(1), "1-byte gap");
    frame_checked(0, 1, 0, 0, 0, "frame 2");
    frame_checked(0, 1, 0, 0, 0, "frame 3 (only 2 consecutive)");
    frame_checked(0, 1, 0, 1, 1, "frame 4 (3 consecutive)");
    foreach (stray[k]) begin
      start("consecutive_rule", $sformatf("V, V, stray %02h, V -> not aligned; + V, V -> aligned", stray[k]));
      frame_checked(0, 1, 0, 0, 0, "frame 1");
      frame_checked(0, 1, 0, 0, 0, "frame 2");
      send(one(stray[k]), "stray header LSB between frames");
      frame_checked(1 + k, 1, 0, 0, 0, "frame 3 after the stray LSB (chain restarted: 1)");
      frame_checked(0, 1, 0, 0, 0, "frame 4 (2 consecutive)");
      frame_checked(0, 1, 0, 1, 1, "frame 5 (3 consecutive)");
    end
  endtask

  // TP21 -- a header split across two stimulus items is still a header.
  task header_across_items();
    byte_q_t q = frame(1);
    start("header_across_items", "... AA | AF ... across two items");
    begin
      byte_q_t first = clean(3);
      first.push_back(q.pop_front());
      send(first, "item ending with the header LSB");
      send(q, "item starting with the header MSB");
    end
    gen.expect_pos(11, "frame found across the item boundary");
    frame_checked(0, 1, 0, 0, 0, "frame 2");
    frame_checked(0, 1, 0, 1, 1, "frame 3");
  endtask

  // TP22 -- illegal frames of various lengths while aligned: loss after exactly
  // 48 header-less bytes whatever the frame lengths are.
  task illegal_lengths();
    byte_q_t q;
    start("illegal_lengths", "aligned; illegal frames of 2, 12 and 36 bytes (50 header-less)");
    sync();
    q = {clean(2), broken_frame(8'h03, 8'h04), clean(36)};
    hdrless_with_loss_check(q, 0, "illegal frames");
    start("illegal_lengths", "aligned; one 49-byte illegal frame (legacy maximum)");
    sync();
    hdrless_with_loss_check(clean(49), 0, "49-byte illegal frame");
  endtask

  // TP25 -- start-up in the middle of a legal stream whose payloads end in a
  // header LSB value (0xAA / 0x55, e.g. an idle/fill pattern).  The last
  // payload byte is seen as a header LSB, the real LSB that follows is
  // rejected, and with DUT-01 the real header is lost -- for EVERY frame.
  // Spec: three consecutive correct frames must always align.
  task midstream_entry();
    byte unsigned last[2] = '{HEAD2_LSB, HEAD1_LSB};
    foreach (last[k]) begin
      start("midstream_entry", $sformatf("enter mid-frame; every payload ends in %02h", last[k]));
      send({clean(4), one(last[k])}, "tail of a frame already in progress");
      for (int f = 1; f <= 6; f++) begin
        byte_q_t q = frame(0);
        q[FRAME_LEN - 1] = last[k];
        send_part(q, 2, $sformatf("frame %0d header", f));
        gen.expect_pos(1, $sformatf("frame %0d header recognised", f));
        send(q, $sformatf("frame %0d payload (ends in %02h)", f, last[k]));
        if (f >= 3) gen.expect_fd(1, $sformatf("aligned after %0d legal frames", f));
      end
    end
  endtask

  // TP26 -- one corrupted header byte while aligned, followed by legal frames
  // whose payloads end in 0x55.  Spec: 12 header-less bytes, alignment kept.
  // With DUT-01 the aligner can never find a header again: alignment is lost
  // permanently although every following frame is correct.
  task error_then_lsb_payloads();
    byte_q_t q;
    start("error_then_lsb_payloads", "aligned; one bad header byte; then 10 legal frames ending in 55");
    sync();
    q = broken_frame(HEAD1_LSB, 8'h01);
    q[FRAME_LEN - 1] = HEAD2_LSB;
    send(q, "frame with a corrupted MSB (payload ends in 55)");
    for (int f = 1; f <= 10; f++) begin
      q = frame(0);
      q[FRAME_LEN - 1] = HEAD2_LSB;
      send_part(q, 2, $sformatf("legal frame %0d header", f));
      gen.expect_pos(1, $sformatf("legal frame %0d header recognised", f));
      send(q, $sformatf("legal frame %0d payload", f));
      gen.expect_fd(1, $sformatf("still aligned after legal frame %0d", f));
    end
  endtask

  // TP27 -- DUT-07 demonstration (architecture, no fly-wheel): 13-byte frames.
  // From reset they never align (no three consecutive frames).  Once aligned,
  // the hunting aligner re-finds every header one byte late and NEVER drops
  // frame_detect, although no frame arrives at the expected position (spec
  // text: out-of-frame after four frames without the expected header).  The
  // checkpoints encode the design-slide (hunting) behaviour; see
  // docs/BUG_REPORT.md DUT-07 for the spec-text deviation.
  task slip_in_sync();
    start("slip_in_sync", "13-byte frames from reset never align");
    repeat (6) send({frame(0), clean(1)}, "13-byte frame");
    gen.expect_fd(0, "13-byte frames: never three consecutive frames");
    start("slip_in_sync", "aligned, then 8 frames of 13 bytes (DUT-07 demonstration)");
    sync();
    repeat (8) send({clean(1), frame(0)}, "1 slip byte + frame");
    gen.expect_fd(1, "hunting architecture keeps alignment through 8 slipped frames (DUT-07)");
  endtask

  //===========================================================================
  // TP23 -- systematic sweep of the loss threshold (R5), with and without a
  // stray LSB in front of the header (R2).  For every case the expected value
  // follows directly from the rule: with H header-less bytes before the
  // header LSB, alignment survives the header iff H <= 46.
  //===========================================================================
  task boundary_sweep();
    for (int g = 0; g <= 60; g++) begin
      for (int pfx = 0; pfx <= 1; pfx++) begin
        int     ht = (g % 2) + 1;
        int     h  = g + pfx;
        byte_q_t q = clean(g);
        gen.begin_scenario("boundary", $sformatf("aligned, %0d header-less bytes%s, header",
                                                   g, fa_sel(pfx, " + stray LSB", "")));
        gen.put_reset(1, "boundary: reset");
        sync();
        if (g > 0) begin
          send(q, $sformatf("%0d header-less bytes", g));
          gen.expect_fd(g < LOSS_BYTES, $sformatf("after %0d header-less bytes", g));
        end
        if (pfx) send(one((ht == 1) ? HEAD2_LSB : HEAD1_LSB), "stray LSB of the other type");
        frame_checked(ht, 1, (h <= 46), (h <= 46), (h <= 46), $sformatf("header after H=%0d", h));
      end
    end
  endtask

  //===========================================================================
  // Dispatch
  //===========================================================================
  task run_by_name(string name, output bit found);
    found = 1;
    case (name)
      "spec_suggested":      spec_suggested();
      "mixed_headers":       mixed_headers();
      "swapped_header":      swapped_header();
      "inverted_header":     inverted_header();
      "lsb_ok_msb_bad":      lsb_ok_msb_bad();
      "lsb_bad_msb_ok":      lsb_bad_msb_ok();
      "msb_in_payload":      msb_in_payload();
      "header_in_payload":   header_in_payload();
      "restart_header":      restart_header();
      "loss_boundary":       loss_boundary();
      "corrupted_frames":    corrupted_frames();
      "header_in_illegal":   header_in_illegal();
      "frames_in_illegal":   frames_in_illegal();
      "header_soup":         header_soup();
      "lsb_at_payload_end":  lsb_at_payload_end();
      "long_valid_run":      long_valid_run();
      "long_garbage":        long_garbage();
      "reset_every_phase":   reset_every_phase();
      "false_lock_in_sync":  false_lock_in_sync();
      "consecutive_rule":    consecutive_rule();
      "header_across_items": header_across_items();
      "illegal_lengths":     illegal_lengths();
      "loss_cause":          loss_cause();
      "midstream_entry":     midstream_entry();
      "error_then_lsb_payloads": error_then_lsb_payloads();
      "slip_in_sync":        slip_in_sync();
      default:               found = 0;
    endcase
  endtask

  task run_all_directed();
    bit found;
    foreach (names[i]) run_by_name(names[i], found);
  endtask

endclass
