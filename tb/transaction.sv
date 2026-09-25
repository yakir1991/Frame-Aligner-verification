//==============================================================================
// transaction -- one stimulus item (the spec's "frame_item")
//------------------------------------------------------------------------------
//  A transaction is a group of bytes that the driver sends back-to-back, or a
//  request to reset the DUT.  Randomisation follows the spec's suggestion
//  (header_type with a distribution, dynamic payload, post_randomize() builds
//  the bytes) and adds the corner cases found during verification:
//
//    IK_VALID    : header (HEAD_1 / HEAD_2) + 10 payload bytes            (12 B)
//    IK_ILLEGAL  : 2 "header" bytes that are NOT a valid header + 0..47
//                  payload bytes; illegal_kind selects how the header is
//                  broken (random, good LSB/bad MSB, swapped, ...)
//    IK_RESTART  : 1..2 stray header LSBs immediately followed by a valid
//                  frame (exercises header restart, DUT-01)
//    IK_GAP      : a run of header-less bytes whose length is biased around
//                  the 48-byte loss threshold (exercises DUT-02)
//    IK_RESET    : assert the asynchronous reset in mid-stream
//    IK_RAW      : explicit bytes written by a directed scenario
//
//  Legacy defects fixed here:
//    * bytes are 2-state (byte unsigned): the legacy class used 4-state
//      logic arrays and several directed tests drove X into the DUT;
//    * an "illegal" frame can be requested with no header pattern anywhere
//      (embed_headers = 0), so that "illegal" really means illegal;
//    * byte values come from $urandom in post_randomize().  Constraint
//      solvers are only asked to pick the kind/type/length (some solvers
//      return strongly biased values for constrained data bytes).
//==============================================================================
class transaction;

  typedef enum bit [1:0] {HEAD_1, HEAD_2, ILLEGAL} header_type_t;
  typedef enum int {IK_VALID, IK_ILLEGAL, IK_RESTART, IK_GAP, IK_RESET, IK_RAW} item_kind_t;
  typedef enum int {
    ILL_RANDOM,        // two random bytes that do not form a valid header
    ILL_LSB_BAD_MSB,   // valid LSB followed by a wrong MSB
    ILL_BAD_LSB_MSB,   // wrong LSB followed by a valid MSB
    ILL_SWAPPED,       // MSB transmitted before LSB
    ILL_CROSS_TYPE     // LSB of one header type with the MSB of the other
  } illegal_kind_t;

  //---------------------------------------------------------------------------
  // Randomised fields
  //---------------------------------------------------------------------------
  rand item_kind_t    item_kind;
  rand header_type_t  header_type;
  rand illegal_kind_t illegal_kind;
  rand int unsigned   payload_len;     // IK_ILLEGAL payload length
  rand int unsigned   gap_len;         // IK_GAP length
  rand int unsigned   restart_len;     // IK_RESTART number of stray LSBs
  rand int unsigned   reset_cycles;    // IK_RESET length
  rand bit            embed_headers;   // IK_ILLEGAL payload may contain headers

  //---------------------------------------------------------------------------
  // Derived / bookkeeping fields
  //---------------------------------------------------------------------------
  byte unsigned payload[];             // payload bytes
  byte unsigned frame[];               // every byte to drive, in order
  int unsigned  reset_idle_before = 2; // IK_RESET: idle bytes before reset asserts
  string        label;                 // description for logs
  int unsigned  first_byte_idx;        // stream index of frame[0] (set by generator)

  //---------------------------------------------------------------------------
  // Constraints
  //---------------------------------------------------------------------------
  // Default mix used by the random test (directed code overrides it).
  constraint c_kind_dist {
    item_kind != IK_RAW;
    item_kind dist {IK_VALID := 60, IK_ILLEGAL := 18, IK_RESTART := 8, IK_GAP := 12, IK_RESET := 2};
  }
  // Spec suggestion: header type distribution.  Kinds other than IK_ILLEGAL
  // always carry a valid header.
  constraint c_header_type {
    (item_kind == IK_ILLEGAL) -> header_type == ILLEGAL;
    (item_kind != IK_ILLEGAL) -> header_type != ILLEGAL;
    header_type dist {HEAD_1 := 40, HEAD_2 := 40, ILLEGAL := 20};
  }
  constraint c_illegal_kind {
    illegal_kind dist {ILL_RANDOM := 40, ILL_LSB_BAD_MSB := 20, ILL_BAD_LSB_MSB := 15,
                       ILL_SWAPPED := 15, ILL_CROSS_TYPE := 10};
  }
  // Legacy definition of an illegal frame: 0..47 payload bytes.  Both ends
  // of the range are weighted up.
  constraint c_payload_len {
    payload_len <= MAX_ILLEGAL_PAYLOAD;
    payload_len dist {0 := 5, [1:9] :/ 20, 10 := 10, [11:46] :/ 50, 47 := 15};
  }
  // Gap lengths concentrated on the loss threshold (48 header-less bytes).
  constraint c_gap_len {
    gap_len inside {[1:60]};
    gap_len dist {[1:11] :/ 10, [12:35] :/ 10, [36:43] :/ 15, [44:49] :/ 50, [50:60] :/ 15};
  }
  constraint c_restart_len { restart_len inside {[1:2]}; }
  constraint c_reset_cycles { reset_cycles inside {[1:4]}; }
  constraint c_embed { embed_headers dist {0 := 50, 1 := 50}; }

  //---------------------------------------------------------------------------
  // Byte helpers
  //---------------------------------------------------------------------------
  // A random byte that is none of the four header byte values.
  static function byte unsigned clean_byte();
    byte unsigned b;
    do b = byte'($urandom_range(0, 255));
    while (fa_is_lsb(b) || fa_is_msb(b));
    return b;
  endfunction

  static function byte unsigned any_byte();
    return byte'($urandom_range(0, 255));
  endfunction

  static function byte unsigned lsb_of(header_type_t t);
    return (t == HEAD_2) ? HEAD2_LSB : HEAD1_LSB;
  endfunction

  static function byte unsigned msb_of(header_type_t t);
    return (t == HEAD_2) ? HEAD2_MSB : HEAD1_MSB;
  endfunction

  // Build the two bytes of a broken header.
  function void build_illegal_header(output byte unsigned lsb, output byte unsigned msb);
    header_type_t t = ($urandom_range(0, 1) == 0) ? HEAD_1 : HEAD_2;
    case (illegal_kind)
      ILL_LSB_BAD_MSB: begin lsb = lsb_of(t); msb = clean_byte(); end
      ILL_BAD_LSB_MSB: begin lsb = clean_byte(); msb = msb_of(t); end
      ILL_SWAPPED:     begin lsb = msb_of(t); msb = lsb_of(t); end
      ILL_CROSS_TYPE:  begin lsb = lsb_of(t); msb = msb_of((t == HEAD_1) ? HEAD_2 : HEAD_1); end
      default: begin   // ILL_RANDOM
        do begin lsb = any_byte(); msb = any_byte(); end
        while (fa_is_lsb(lsb) && msb == fa_msb_for(lsb));
      end
    endcase
  endfunction

  //---------------------------------------------------------------------------
  // post_randomize: turn the randomised fields into bytes
  //---------------------------------------------------------------------------
  function void post_randomize();
    byte unsigned q[$];
    byte unsigned l, m;
    case (item_kind)
      IK_VALID, IK_RESTART: begin
        if (item_kind == IK_RESTART)
          repeat (restart_len) q.push_back(($urandom_range(0, 1) == 0) ? HEAD1_LSB : HEAD2_LSB);
        q.push_back(lsb_of(header_type));
        q.push_back(msb_of(header_type));
        payload = new[PAYLOAD_LEN];
        foreach (payload[i]) payload[i] = any_byte();   // payload content is irrelevant (R3)
        foreach (payload[i]) q.push_back(payload[i]);
        label = $sformatf("%s%s", (item_kind == IK_RESTART) ? $sformatf("%0dxLSB+", restart_len) : "",
                          header_type.name());
      end
      IK_ILLEGAL: begin
        build_illegal_header(l, m);
        q.push_back(l);
        q.push_back(m);
        payload = new[payload_len];
        foreach (payload[i]) payload[i] = embed_headers ? any_byte() : clean_byte();
        if (embed_headers && payload_len >= 2 && $urandom_range(0, 1)) begin
          int unsigned p = $urandom_range(0, payload_len - 2);   // plant a header
          header_type_t t = ($urandom_range(0, 1) == 0) ? HEAD_1 : HEAD_2;
          payload[p]     = lsb_of(t);
          payload[p + 1] = msb_of(t);
        end
        foreach (payload[i]) q.push_back(payload[i]);
        label = $sformatf("ILLEGAL/%s len=%0d%s", illegal_kind.name(), payload_len,
                          fa_sel(embed_headers, " (may embed headers)", ""));
      end
      IK_GAP: begin
        repeat (gap_len) q.push_back(clean_byte());
        label = $sformatf("GAP %0d header-less bytes", gap_len);
      end
      IK_RESET: begin
        label = $sformatf("RESET %0d cycles", reset_cycles);
      end
    endcase
    frame = new[q.size()];
    foreach (q[i]) frame[i] = q[i];
  endfunction

  //---------------------------------------------------------------------------
  // Directed construction helpers (no randomisation)
  //---------------------------------------------------------------------------
  // Raw byte group.
  static function transaction from_bytes(byte_q_t q, string label);
    transaction t = new();
    t.item_kind = IK_RAW;
    t.frame     = new[q.size()];
    foreach (q[i]) t.frame[i] = q[i];
    t.label     = label;
    return t;
  endfunction

  // idle_before = 2 lets the DUT response to the last byte be sampled before
  // the reset; idle_before = 1 resets while the last byte's state is still
  // held (used to reset in a precise phase, e.g. right after a header LSB).
  static function transaction reset_req(int unsigned cycles, string label = "", int unsigned idle_before = 2);
    transaction t = new();
    t.item_kind         = IK_RESET;
    t.reset_cycles      = cycles;
    t.reset_idle_before = idle_before;
    t.label        = (label == "") ? $sformatf("RESET %0d cycles", cycles) : label;
    return t;
  endfunction

  function string header_type_to_string();
    return header_type.name();
  endfunction

  function string convert2string();
    byte_q_t q;
    foreach (frame[i]) q.push_back(frame[i]);
    if (item_kind == IK_RESET) return label;
    return $sformatf("%s [%0d B @%0d]: %s", label, frame.size(), first_byte_idx, fa_bytes2str(q, 20));
  endfunction

endclass
