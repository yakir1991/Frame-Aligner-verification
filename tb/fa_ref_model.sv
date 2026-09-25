//==============================================================================
// fa_ref_model -- specification reference model of the frame aligner
//------------------------------------------------------------------------------
//  Why a new model?
//    The legacy frame_aligner_model was a line-by-line copy of the RTL, and the
//    legacy flow was "whenever the scoreboard disagreed with the DUT, fix the
//    scoreboard".  A model copied from the design cannot find design bugs.
//    This model is written from the specification rules below, in a different
//    style from the RTL (a stream algorithm with three phases instead of a
//    four-state FSM with trigger signals).  It is cross-checked against an
//    independent Python model (scripts/fa_model.py).
//
//  Specification rules implemented (see docs/VERIFICATION_PLAN.md, section 2)
//    R1  Header = LSB then MSB: AA AF (HEAD_1) or 55 BA (HEAD_2).
//    R2  While hunting, every byte is examined.  A header candidate whose MSB
//        is wrong is rejected; if the rejected byte is itself an LSB it becomes
//        the new candidate, so no header present in the stream is ever missed.
//    R3  After a validated header the next 10 bytes are payload and are not
//        examined (headers inside a payload are ignored).  The byte after the
//        payload is expected to be the next header LSB.
//    R4  frame_detect rises one byte after the 3rd consecutive header is
//        validated (spec waveform 1).  "Consecutive" = no hunting byte between
//        the frames.
//    R5  frame_detect falls on the 48th consecutive byte that is not part of a
//        validated header (4 frames x 12 bytes).  A header completed within
//        those 48 bytes keeps alignment; bytes of a validated frame never
//        count and can never clear alignment.
//    R6  fr_byte_position (registered) = index of the byte just consumed in the
//        current frame: LSB 0, MSB 1, payload 2..11; 0 while hunting.
//    R7  Asynchronous reset returns everything to the hunting state, outputs 0.
//
//  Bug emulation knobs
//    emulate[BUG_DUT0x] = 1 makes the model reproduce the corresponding DUT
//    defect.  All knobs off = pure specification ("spec model").  All knobs on
//    = the design as delivered ("DUT model").  The scoreboard runs both: a
//    mismatch against the spec model that the DUT model predicts is a KNOWN
//    defect (and is attributed to the knobs that fired); anything else is an
//    UNEXPLAINED mismatch.
//==============================================================================

typedef enum int { PH_HUNT, PH_GOT_LSB, PH_IN_FRAME } fa_phase_e;

// Causes of an alignment loss (for coverage and bug attribution).
typedef enum int {
  LOSS_NONE,
  LOSS_PLAIN_BYTE,       // 48th header-less byte was an ordinary byte
  LOSS_CANDIDATE_LSB,    // ... was a header LSB (header not complete yet)
  LOSS_REJECTED_MSB,     // ... was a wrong MSB
  LOSS_RESTART_LSB,      // ... was a wrong MSB that is itself an LSB
  LOSS_VALID_HEADER,     // DUT-02: the byte completed a VALID header
  LOSS_IN_FRAME          // DUT-02: the byte was payload of a validated frame
} fa_loss_e;

// Everything the model learned while consuming one byte.
typedef struct {
  byte unsigned data;
  fa_phase_e    prev_phase, new_phase;
  bit           fd_before, fd_after;
  bit [3:0]     pos_after;
  bit           header_validated;     // this byte completed a valid header
  int unsigned  hdr_type;             // 1 = HEAD_1, 2 = HEAD_2 (when validated)
  int unsigned  consec_frames;        // consecutive frames incl. this one (when validated)
  int unsigned  gap_before_header;    // header-less bytes before this header's LSB
  bit           header_rejected;      // this byte was a wrong MSB
  bit           restart;              // ... and it became the new LSB candidate (R2)
  byte unsigned rejected_lsb;         // LSB of the rejected candidate
  bit           payload_header_seen;  // a header pattern completed inside a payload
  bit           set_event;            // frame_detect 0 -> 1
  bit           loss_event;           // frame_detect 1 -> 0
  fa_loss_e     loss_cause;
  bit [FA_NUM_BUGS-1:0] bug_hits;     // knobs that changed the behaviour this byte
} fa_step_info_t;

class fa_ref_model;

  string name;
  bit    emulate[FA_NUM_BUGS];      // bug emulation knobs (see header)

  //---------------------------------------------------------------------------
  // Architectural state
  //---------------------------------------------------------------------------
  fa_phase_e    phase;
  byte unsigned cand_lsb;           // header LSB candidate (PH_GOT_LSB)
  int unsigned  cand_gap;           // header-less bytes before cand_lsb
  byte unsigned prev_byte;          // previous byte (payload-header detection)
  int unsigned  frame_idx;          // index of last consumed byte (PH_IN_FRAME)
  int unsigned  consec_frames;      // consecutive validated headers (saturating)
  int unsigned  hdrless;            // consecutive header-less bytes
  bit           sync_pending;       // frame_detect rises on the next byte (R4)

  // Registered outputs (what the DUT must show at the next monitor sample).
  bit [3:0]     pos;
  bit           fd;

  // Information about the most recent step (coverage, logs, attribution).
  fa_step_info_t last;

  function new(string name = "spec_model");
    this.name = name;
    foreach (emulate[i]) emulate[i] = 1'b0;
    reset();
  endfunction

  // Convenience presets.
  function void set_all_bugs(bit on);
    foreach (emulate[i]) emulate[i] = on;
  endfunction

  function string knobs2str();
    string s = "";
    foreach (emulate[i]) if (emulate[i]) s = {s, fa_sel(s == "", "", ","), $sformatf("DUT-%02d", i + 1)};
    return fa_sel(s == "", "none (pure spec)", s);
  endfunction

  // R7: asynchronous reset.
  function void reset();
    phase         = PH_HUNT;
    cand_lsb      = 8'h00;
    cand_gap      = 0;
    prev_byte     = 8'h00;
    frame_idx     = 0;
    consec_frames = 0;
    hdrless       = 0;
    sync_pending  = 1'b0;
    pos           = 4'd0;
    fd            = 1'b0;
    begin
      fa_step_info_t zero;          // automatic: every field at its default (0)
      last = zero;
    end
  endfunction

  //---------------------------------------------------------------------------
  // Count one header-less byte.  The spec counter saturates; with DUT-02
  // emulation it behaves like the 6-bit RTL counter (wraps at 64).
  //---------------------------------------------------------------------------
  local function void count_hdrless();
    if (emulate[BUG_DUT02]) hdrless = (hdrless + 1) % 64;
    else if (hdrless < 1_000_000) hdrless++;
  endfunction

  //---------------------------------------------------------------------------
  // Consume one byte.  After the call, pos/fd are the values the DUT must
  // present on its registered outputs.
  //---------------------------------------------------------------------------
  function void step(byte unsigned b);
    fa_step_info_t si;                    // automatic: all fields start at 0
    int unsigned   na_before = hdrless;   // counter value before this byte
    bit            counted   = 1'b0;      // byte counted as header-less
    bit            set_now   = sync_pending;
    bit            fd_next   = fd;

    si.data       = b;
    si.prev_phase = phase;
    si.fd_before  = fd;
    sync_pending  = 1'b0;

    case (phase)
      //-----------------------------------------------------------------------
      PH_IN_FRAME: begin                           // R3: payload bytes
        if (fa_is_lsb(prev_byte) && b == fa_msb_for(prev_byte) && frame_idx >= 2)
          si.payload_header_seen = 1'b1;           // pattern inside payload: ignored
        frame_idx++;
        pos = frame_idx[3:0];
        if (frame_idx == FRAME_LEN - 1) begin
          phase = PH_HUNT;                         // next byte = next header LSB
          if (emulate[BUG_DUT02]) hdrless = 0;     // RTL clears its counter here
        end
      end
      //-----------------------------------------------------------------------
      PH_HUNT: begin                               // R2: looking for an LSB
        pos     = 4'd0;
        counted = 1'b1;
        if (fa_is_lsb(b)) begin
          cand_lsb = b;
          cand_gap = hdrless;                      // bytes before this LSB
          phase    = PH_GOT_LSB;
        end else begin
          consec_frames = 0;
        end
        count_hdrless();
      end
      //-----------------------------------------------------------------------
      PH_GOT_LSB: begin                            // R1: check the MSB
        if (b == fa_msb_for(cand_lsb)) begin
          phase                = PH_IN_FRAME;
          frame_idx            = 1;
          pos                  = 4'd1;
          if (consec_frames < 1_000_000) consec_frames++;
          si.header_validated  = 1'b1;
          si.hdr_type          = (cand_lsb == HEAD1_LSB) ? 1 : 2;
          si.consec_frames     = consec_frames;
          si.gap_before_header = cand_gap;
          if (!emulate[BUG_DUT02]) hdrless = 0;    // R5: the LSB was part of a header
          if (consec_frames >= SYNC_FRAMES) sync_pending = 1'b1;   // R4
        end else begin
          si.header_rejected = 1'b1;
          si.rejected_lsb    = cand_lsb;
          consec_frames      = 0;
          counted            = 1'b1;
          if (fa_is_lsb(b) && !emulate[BUG_DUT01]) begin
            // R2: the wrong MSB is itself an LSB -> new candidate.
            si.restart = 1'b1;
            cand_gap   = hdrless;
            cand_lsb   = b;
            pos        = 4'd0;
          end else begin
            if (fa_is_lsb(b)) si.bug_hits[BUG_DUT01] = 1'b1;   // LSB thrown away
            phase = PH_HUNT;
            pos   = 4'd0;
            if (emulate[BUG_DUT03]) begin
              pos = 4'd1;                          // RTL reports "header MSB"
              si.bug_hits[BUG_DUT03] = 1'b1;
            end
          end
          count_hdrless();
        end
      end
    endcase

    //-------------------------------------------------------------------------
    // R5: loss of alignment
    //-------------------------------------------------------------------------
    if (emulate[BUG_DUT02]) begin
      // RTL: cleared whenever the counter showed 47 before this byte,
      // whatever the byte was.
      if (na_before == LOSS_BYTES - 1) begin
        fd_next = 1'b0;
        if (!counted && fd) si.bug_hits[BUG_DUT02] = 1'b1;
      end
    end else if (counted && hdrless >= LOSS_BYTES) begin
      fd_next = 1'b0;
    end

    // R4: the set has priority (as in the RTL; the two never coincide).
    if (set_now) fd_next = 1'b1;

    if (fd && !fd_next) begin
      si.loss_event = 1'b1;
      if (si.header_validated)           si.loss_cause = LOSS_VALID_HEADER;
      else if (!counted)                 si.loss_cause = LOSS_IN_FRAME;
      else if (si.prev_phase == PH_HUNT) si.loss_cause = fa_is_lsb(b) ? LOSS_CANDIDATE_LSB : LOSS_PLAIN_BYTE;
      else                               si.loss_cause = fa_is_lsb(b) ? LOSS_RESTART_LSB : LOSS_REJECTED_MSB;
    end
    si.set_event = !fd && fd_next;
    fd           = fd_next;

    prev_byte    = b;
    si.new_phase = phase;
    si.fd_after  = fd;
    si.pos_after = pos;
    last         = si;
  endfunction

  //---------------------------------------------------------------------------
  // State comparison / copy (used by the scoreboard to re-synchronise the spec
  // model onto the DUT's path after a known defect was observed).
  //---------------------------------------------------------------------------
  function bit same_state(fa_ref_model o);
    return phase == o.phase && cand_lsb == o.cand_lsb && frame_idx == o.frame_idx &&
           consec_frames == o.consec_frames && hdrless == o.hdrless &&
           sync_pending == o.sync_pending && pos == o.pos && fd == o.fd;
  endfunction

  function void copy_state(fa_ref_model o);
    phase         = o.phase;
    cand_lsb      = o.cand_lsb;
    cand_gap      = o.cand_gap;
    prev_byte     = o.prev_byte;
    frame_idx     = o.frame_idx;
    consec_frames = o.consec_frames;
    hdrless       = o.hdrless;
    sync_pending  = o.sync_pending;
    pos           = o.pos;
    fd            = o.fd;
  endfunction

  function string state2str();
    return $sformatf("%s phase=%s cand=%02h idx=%0d consec=%0d hdrless=%0d pend=%0b pos=%0d fd=%0b",
                     name, phase.name(), cand_lsb, frame_idx, consec_frames, hdrless,
                     sync_pending, pos, fd);
  endfunction

endclass
