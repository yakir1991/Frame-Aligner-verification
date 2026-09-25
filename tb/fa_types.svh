//==============================================================================
// fa_types.svh -- shared constants, types and utilities (included by fa_pkg)
//==============================================================================

//------------------------------------------------------------------------------
// Protocol constants (from the specification)
//------------------------------------------------------------------------------
localparam byte unsigned HEAD1_LSB = 8'hAA;   // HEAD_1 = 0xAFAA, LSB first
localparam byte unsigned HEAD1_MSB = 8'hAF;
localparam byte unsigned HEAD2_LSB = 8'h55;   // HEAD_2 = 0xBA55, LSB first
localparam byte unsigned HEAD2_MSB = 8'hBA;
localparam int FRAME_LEN      = 12;           // 2 header + 10 payload bytes
localparam int PAYLOAD_LEN    = 10;
localparam int SYNC_FRAMES    = 3;            // consecutive valid frames to align
localparam int LOSS_BYTES     = 48;           // header-less bytes to lose alignment
localparam int MAX_ILLEGAL_PAYLOAD = 47;      // legacy definition of an illegal frame

// A byte stream (used by directed sequences and the driver).
typedef byte unsigned byte_q_t[$];

//------------------------------------------------------------------------------
// Known DUT defects that the reference model can emulate.
// Only defects that change the DUT *ports* need a model knob; the latent
// counter-wrap defects (DUT-04/05) are caught by white-box assertions.
//------------------------------------------------------------------------------
typedef enum int {
  BUG_DUT01 = 0,   // rejected MSB that is itself an LSB is thrown away
  BUG_DUT02 = 1,   // sync cleared by the 48th counted byte even if it completes a header
  BUG_DUT03 = 2    // fr_byte_position = 1 after a rejected header
} fa_bug_e;
localparam int FA_NUM_BUGS = 3;

function automatic string fa_bug_name(int b);
  case (b)
    BUG_DUT01: return "DUT-01 header LSB lost after a rejected MSB";
    BUG_DUT02: return "DUT-02 sync dropped on a byte that completes a valid header";
    BUG_DUT03: return "DUT-03 fr_byte_position=1 after a rejected header";
    default:   return $sformatf("BUG-%0d", b);
  endcase
endfunction

//------------------------------------------------------------------------------
// String select.  Use this instead of  cond ? "a" : "b"  : string literals in a
// conditional operator are packed bit vectors, so the shorter one is padded and
// prints with leading blanks (or as a number when used as a format string).
//------------------------------------------------------------------------------
function automatic string fa_sel(bit cond, string if_true, string if_false);
  if (cond) return if_true;
  return if_false;
endfunction

//------------------------------------------------------------------------------
// Header helpers
//------------------------------------------------------------------------------
function automatic bit fa_is_lsb(byte unsigned b);
  return (b == HEAD1_LSB) || (b == HEAD2_LSB);
endfunction

function automatic bit fa_is_msb(byte unsigned b);
  return (b == HEAD1_MSB) || (b == HEAD2_MSB);
endfunction

// MSB that must follow a given LSB (0x00 when the byte is not an LSB).
function automatic byte unsigned fa_msb_for(byte unsigned lsb);
  if (lsb == HEAD1_LSB) return HEAD1_MSB;
  if (lsb == HEAD2_LSB) return HEAD2_MSB;
  return 8'h00;
endfunction

// Coarse classification of a data byte (used for coverage and logs).
typedef enum int { RX_H1_LSB, RX_H2_LSB, RX_H1_MSB, RX_H2_MSB, RX_ZERO, RX_ONES, RX_OTHER } rx_class_e;
function automatic rx_class_e fa_rx_class(byte unsigned b);
  case (b)
    HEAD1_LSB: return RX_H1_LSB;
    HEAD2_LSB: return RX_H2_LSB;
    HEAD1_MSB: return RX_H1_MSB;
    HEAD2_MSB: return RX_H2_MSB;
    8'h00:     return RX_ZERO;
    8'hFF:     return RX_ONES;
    default:   return RX_OTHER;
  endcase
endfunction

function automatic string fa_bytes2str(const ref byte_q_t q, input int max_items = 64);
  string s = "";
  foreach (q[i]) begin
    if (i == max_items) begin s = {s, " ..."}; break; end
    s = {s, fa_sel(i == 0, "", " "), $sformatf("%02h", q[i])};
  end
  return s;
endfunction

//------------------------------------------------------------------------------
// Logging with verbosity control (+VERBOSITY=0..3, default 1)
//   0 : summary only          1 : + test/scenario banners and all errors
//   2 : + one line per item   3 : + one line per byte (cycle trace)
//------------------------------------------------------------------------------
int fa_verbosity = 1;
int unsigned fa_error_count = 0;

function automatic void fa_info(int level, string who, string msg);
  if (fa_verbosity >= level) $display("[%10t] %-11s %s", $time, who, msg);
endfunction

function automatic void fa_error(string who, string msg);
  fa_error_count++;
  $display("[%10t] %-11s ERROR: %s", $time, who, msg);
endfunction

//------------------------------------------------------------------------------
// Assertion failure registry.
// Every concurrent assertion calls fa_sva_fail() from its action block, so the
// final report can count failures per assertion and the test verdict can take
// them into account (the legacy environment printed assertion errors but its
// final "Total Errors" ignored them).
//------------------------------------------------------------------------------
int unsigned fa_sva_fail_count[string];
int unsigned fa_sva_print_limit = 5;     // messages printed per assertion

function automatic void fa_sva_fail(string name, string msg);
  if (!fa_sva_fail_count.exists(name)) fa_sva_fail_count[name] = 0;
  fa_sva_fail_count[name]++;
  if (fa_sva_fail_count[name] <= fa_sva_print_limit)
    $display("[%10t] %-11s ASSERTION %s failed: %s%s", $time, "SVA", name, msg,
             fa_sel(fa_sva_fail_count[name] == fa_sva_print_limit, " (further messages suppressed)", ""));
endfunction

function automatic int unsigned fa_sva_total(string prefix = "");
  int unsigned n = 0;
  foreach (fa_sva_fail_count[k])
    if (prefix == "" || k.substr(0, prefix.len() - 1) == prefix) n += fa_sva_fail_count[k];
  return n;
endfunction

// Cover-property hit registry (used to prove that assertion antecedents are
// actually exercised, i.e. the checks are not vacuous).
int unsigned fa_sva_cover_count[string];

function automatic void fa_sva_cover_register(string name);
  if (!fa_sva_cover_count.exists(name)) fa_sva_cover_count[name] = 0;
endfunction

function automatic void fa_sva_cover(string name);
  if (!fa_sva_cover_count.exists(name)) fa_sva_cover_count[name] = 0;
  fa_sva_cover_count[name]++;
endfunction
