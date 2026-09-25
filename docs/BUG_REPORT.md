# Frame Aligner – Bug Report

This report covers three things:
- defects in the delivered RTL (`rtl/frame_aligner.sv`, logic unchanged from the original `dut.sv`);
- inconsistencies in the specification;
- defects in the original (legacy) verification environment, kept unchanged in `legacy/`.

Every DUT defect is:
- reproduced by a directed scenario (`make -C sim sim DUT=orig TEST=<scenario>`);
- attributed automatically by the scoreboard, or caught by a named assertion.

DUT-01..DUT-06 are repaired in `rtl/frame_aligner_fixed.sv` (tag `FIX DUT-0x`),
which passes the whole regression. DUT-07 is an architecture change that needs a
specification decision, and DUT-08 is guarded by the testbench assertion
`TB_IN_KNOWN`; both are intentionally left unchanged.

Severity scale: **Critical** = legal traffic is not aligned, or alignment is lost
permanently. **High** = a wrong alignment decision on legal or near-legal traffic.
**Medium** = wrong output value without an alignment error. **Low** = latent or
robustness issue. **Info** = coding quality.

"Status" says whether the original project already knew about the issue.
- **New**: found in this review.
- **Extended**: the symptom was known, but its root cause, scope or severity was not.
- **Reclassified**: the original project recorded it as a "gap in the spec" and made
  the scoreboard copy the DUT.

---

## 1. Summary

### 1.1 DUT defects

| ID | Title | Severity | Status | Detected by |
|---|---|---|---|---|
| [DUT-01](#dut-01--header-lsb-thrown-away-after-a-rejected-msb) | Header LSB thrown away after a rejected MSB. A header that follows an odd-length run of `0xAA`/`0x55` is missed: legal streams whose payloads end in a single `0xAA`/`0x55` are **never aligned** from a mid-stream start, and one bit error can lose alignment **permanently** | **Critical** | Extended (student saw `AA AA AF` only) | scoreboard, `SPEC_SYNC_AFTER_3_FRAMES`, `WB_DUT01_NO_LOST_LSB`, TP09/TP23/TP25/TP26 |
| [DUT-02](#dut-02--alignment-dropped-on-the-byte-that-completes-a-valid-header) | Alignment dropped on the byte that completes a **valid** header (46 header-less bytes + header). `frame_detect` is low for 25 cycles although every later header is valid | **High** | Reclassified (student: "last chance is byte 45") | scoreboard, `SPEC_FD_FALL_WHILE_HUNTING`, `WB_DUT02_NO_CLEAR_IN_FRAME`, TP10/TP23 |
| [DUT-03](#dut-03--fr_byte_position--1-after-a-rejected-header) | `fr_byte_position` = 1 ("header MSB") after a **rejected** header | Medium | Reclassified | scoreboard, `SPEC_POS1_AFTER_HEADER`, `SPEC_POS_INCREMENT`, `WB_DUT03_…`, TP05 |
| [DUT-04](#dut-04--legal_frame_counter-wraps-3--0) | `legal_frame_counter` wraps 3 → 0 on the 4th consecutive frame | Low (latent) | New | `WB_DUT04_LEGAL_NO_WRAP`, TP16 |
| [DUT-05](#dut-05--na_byte_counter-wraps-63--0) | `na_byte_counter` wraps 63 → 0 on long header-less streams | Low (latent) | New | `WB_DUT05_NA_NO_WRAP`, TP17 |
| [DUT-06](#dut-06--coding-issues) | Coding issues: no `next_state` default, 4-bit vs 8-bit compare, misleading comments | Info | New | `verilator -Wall` (lint), review |
| [DUT-07](#dut-07--no-fly-wheel-alignment-is-never-lost-on-slipped-or-mis-sized-frames) | No fly-wheel: after alignment, slipped or mis-sized frames never cause loss of alignment, and a single header error stops position tracking | High (architecture) | Extended (student saw false headers in payloads) | analysis; demonstrated by TP19 and TP27 |
| [DUT-08](#dut-08--x-optimistic-header-decode) | X-optimistic header decode: X/Z on `rx_data` is silently treated as "not a header" in RTL simulation, but not in gates | Low | New | review, gate-level check (yosys); `TB_IN_KNOWN` keeps X/Z off the input |

### 1.2 Specification issues

| ID | Title |
|---|---|
| [SPEC-01](#spec-01--output-data-interface-not-implemented) | Output data interface (header + payload forwarding) is specified but not implemented (student finding) |
| [SPEC-02](#spec-02--text-versus-design-slides-frames-versus-bytes) | Text ("four frames without the *expected* header") vs. design slides (48 hunting bytes): leads to DUT-07 |
| [SPEC-03](#spec-03--waveform-2-and-waveform-1-are-inconsistent) | Waveform 2 is off by one clock against the FSM slide and the DUT. The first column of waveform 1 is unreachable |
| [SPEC-04](#spec-04--fr_byte_position-is-undefined-outside-a-frame) | `fr_byte_position` has no definition (and no valid qualifier) outside a frame |
| [SPEC-05](#spec-05--naming-mismatches) | Name mismatches: `fr_is_aligned` / `frame_detect`, `na_frame_counter` / `na_byte_counter`, `Valid_h2` does not exist |
| [SPEC-06](#spec-06--the-48th-byte-is-a-header-lsb) | The 48th header-less byte being a header LSB: two defensible readings |

### 1.3 Legacy testbench defects

| ID | Area | Title | Severity |
|---|---|---|---|
| [TB-01](#tb-01--the-reference-model-was-copied-from-the-rtl) | checker | Reference model copied from the RTL: the scoreboard cannot find design bugs; mismatches were "fixed" in the scoreboard | Critical |
| [TB-02](#tb-02--the-reference-model-updates-frame_detect-one-byte-early) | checker | That model is also not a faithful copy: `frame_detect` rises and falls one byte early | Medium |
| [TB-03](#tb-03--end-of-test-stops-before-the-stimulus-is-driven) | flow | End of test compares driven transactions with `repeat_count`: **117 of 917 queued transactions (12.8 %) are never driven** | High |
| [TB-04](#tb-04--x-driven-into-the-dut) | stimulus | Directed tests drive X: `frame = new[N]` on a 4-state array, plus `8'hxA` | High |
| [TB-05](#tb-05--directed-tests-do-not-test-what-they-claim) | stimulus | Directed tests are shuffled, so their preconditions (e.g. "while aligned") do not hold. Several tests spill into the next test, and some cannot produce their planned outcome | High |
| [TB-06](#tb-06--assertions-are-vacuous-or-wrong) | assertions | 3 of 3 assertions are vacuous or fail on legal behaviour. A cover property is off by one. Assertion failures are not counted in the result | High |
| [TB-07](#tb-07--coverage-model-cannot-close-and-measures-no-spec-feature) | coverage | Reachable `illegal_bins`, unreachable bins, a wrong `ignore_bins`, crosses that cannot see a frame start, no temporal features | Medium |
| [TB-08](#tb-08--simulator-dependent-monitor-alignment-and-races) | timing | Monitor/scoreboard alignment depends on program-block scheduling; reset is released on a clock edge | Medium |
| [TB-09](#tb-09--x-masked-by-2-state-scoreboard-variables) | checker | 2-state scoreboard variables turn X/Z into 0 | Medium |
| [TB-10](#tb-10--build-and-elaboration-problems) | build | `build.list` compiles the scoreboard before the model it uses; `bind` by instance name with upward references is not elaborated by every tool | Medium |
| [TB-11](#tb-11--smaller-issues) | misc | Out-of-bounds writes, "illegal" frames that contain valid headers, no seed control, 100k-line logs, fragile `event.triggered` | Low |

---

## 2. DUT defects

Reproduce any of them with:

```bash
cd sim
make sim DUT=orig  TEST=<scenario> VERBOSITY=2   # shows the violation and its attribution
make sim DUT=fixed TEST=<scenario>               # same scenario passes on the repaired RTL
```

Waveform figures (original RTL vs. repaired RTL vs. specification, from real
simulations) are in `docs/images/` and are regenerated by `scripts/plot_waves.py`.

### DUT-01 – Header LSB thrown away after a rejected MSB

| | |
|---|---|
| Severity | **Critical** |
| Location | `rtl/frame_aligner.sv:157-169` (FR_HLSB, `else` branch, tag `DUT-01`) |
| Spec | Text p.3 ("constantly monitoring the incoming data stream for a specific header pattern"), p.6 ("in-frame alignment when three consecutive frames with the correct header pattern are detected"); rule R2 |
| Scenarios | `restart_header` (TP09), `boundary` (TP23), `loss_cause` (TP24), `midstream_entry` (TP25), `error_then_lsb_payloads` (TP26), `header_soup` (TP14) |
| Figures | `wave_dut01_restart.png`, `wave_dut01_midstream.png` |

**Root cause.** In `FR_HLSB` the FSM checks whether the current byte is the MSB
that matches the stored LSB. If it is not, it always returns to `FR_IDLE`. If the
rejected byte is itself a header LSB (`0xAA`/`0x55`), it is never examined as the
start of a new header. That header is lost, and the frame that follows is missed.

**Exact trigger (verified by simulation).** While the DUT is hunting, a header
is missed exactly when it follows an **odd-length run** of `0xAA`/`0x55` bytes.
With an even-length run, the pairs cancel out and the header is found.

**Minimal reproductions.**

| Stream | Expected (spec) | Original RTL |
|---|---|---|
| `AA AA AF …` (student finding K6) | header at byte 1 | missed |
| `55 55 BA …`, `AA 55 BA …`, `55 AA AF …` | header at byte 1 | missed (**new**: all four combinations) |

**System-level impact (new).** The trigger does not need a malformed stream. The
last payload byte (Pay_9) of a legal frame is `0xAA` or `0x55` with probability 2/256
for random data, and always for a frame format whose last payload byte is a fixed
`0x55`/`0xAA` trailer. (A payload made only of `0x55` gives an even-length run: it
delays acquisition by at most one frame.) In such frames, while the aligner is hunting:
- Pay_9 is taken as a header LSB;
- the real header LSB then fails the MSB check and is thrown away;
- the real MSB is seen as garbage.

Consequences, measured on the RTL:
1. **A legal stream is never aligned.** Start-up in the middle of a stream whose
   payloads end in a single `0x55`: `frame_detect` stays 0 **forever** (TP25: all 20
   checkpoints fail on the original RTL and pass on the repaired one). The repaired RTL aligns after 3 frames.
2. **One bit error loses alignment permanently.** While aligned, a single corrupted
   header byte followed by legal frames ending in `0x55`: the aligner can never find
   a header again, and `frame_detect` drops 48 bytes later and never returns (TP26).
3. **Premature loss after only three bad frames.** If the last payload byte of the
   3rd bad frame is an LSB value, the valid 4th header is swallowed and alignment is
   lost ("four consecutive frames" violated). With random payload the byte before
   the 4th header is `0xAA`/`0x55` in 2 of 256 cases, i.e. about 1 in 128 such sequences.
4. **Tolerated gap shrinks from 45 to 32 bytes** when one stray LSB precedes the
   header (TP23 with prefix).
5. With random traffic, acquisition is late by one frame (rarely two) in 0.8 % of
   start-ups inside a frame (Python model, 100 000 random streams).

**Fix** (`rtl/frame_aligner_fixed.sv:109-115`, tag `FIX DUT-01`): when the MSB check fails and the byte
is a header LSB, stay in `FR_HLSB`. `header_lsb_samp` already captures the new LSB.

```verilog
end else if (header_lsb_valid) begin   // FIX DUT-01
   legal_frame_counter_rst = 1'b1;
   fr_byte_position_rst    = 1'b1;
   na_byte_count_inc       = 1'b1;
   next_state              = FR_HLSB;
end
```

---

### DUT-02 – Alignment dropped on the byte that completes a valid header

| | |
|---|---|
| Severity | **High** |
| Location | `rtl/frame_aligner.sv:283-284` (unqualified clear `na_byte_counter == 6'd47`, tag `DUT-02`); it interacts with the LSB count in FR_IDLE at `:135-140`, which is itself correct |
| Spec | Text p.6 ("out-of-frame … when four consecutive frames have incorrect headers"); register table ("when this counter **reaches 48**, frame_detect is reset"); rule R5 |
| Scenarios | `loss_boundary` (TP10, G = 46), `boundary` (TP23) |
| Figure | `wave_dut02_sync_drop.png` |

**Root cause.** `frame_detect` is cleared whenever the *registered* counter
shows 47, on **any** following byte and in **any** state. The clear is not
qualified by `na_byte_count_inc`, so it also fires on bytes that are not counted.

After 46 header-less bytes, a valid header's LSB brings the counter to 47. Counting
the LSB is correct: the register table counts it when it arrives, and the repaired
RTL keeps it. The valid MSB is not counted, so the counter never reaches 48. But
the unqualified clear fires anyway, and the DUT receives the whole valid frame
(state `FR_DATA`, `legal_frame_counter = 1`) with `frame_detect = 0`.

**Observed vs. expected.** After alignment, G header-less bytes, then a valid header:

| G | Expected (register table) | Original RTL |
|---|---|---|
| ≤ 45 | aligned | aligned |
| **46** | aligned (the counter never reaches 48) | **lost** on the valid MSB, re-aligned only after 3 more frames (outage 25 cycles) |
| 47 | lost on the LSB (the counter reaches 48) | lost |
| ≥ 48 | lost | lost |

The student recorded the symptom ("last opportunity to remain aligned is a header at
byte 45") as a gap in the spec and changed the scoreboard to accept it. It is a
defect: alignment is declared lost at the very moment a valid header is recognised,
and it is inconsistent with "reaches 48". Under the look-ahead reading
([SPEC-06](#spec-06--the-48th-byte-is-a-header-lsb)) G = 47 would also have to be
kept, so the DUT is wrong under both readings.

**Fix** (`rtl/frame_aligner_fixed.sv:185-193`, tag `FIX DUT-02`): clear only when the byte being
consumed is itself counted:

```verilog
else if (na_byte_count_inc && (na_byte_counter == NA_LIMIT)) frame_detect <= 1'b0;  // FIX DUT-02
```

---

### DUT-03 – `fr_byte_position` = 1 after a rejected header

| | |
|---|---|
| Severity | Medium |
| Location | `rtl/frame_aligner.sv:157-169` (no `fr_byte_position_rst` on the HLSB → IDLE arc, tag `DUT-03`) |
| Spec | Port table ("position of the current byte in the header or the payload"), rule R6 |
| Scenarios | `lsb_ok_msb_bad` (TP05), `corrupted_frames` (TP11), `swapped_header` (TP03) |
| Figure | `wave_dut03_pos.png` |

After `AA 01` (or any rejected header) the DUT reports `fr_byte_position = 1`, i.e.
"header MSB", for one cycle, then 0. No frame exists. Every other hunting byte
reports 0, so a consumer using `fr_byte_position` to extract header/payload bytes
sees a phantom header. The student recorded it as a spec gap (slide 23). The spec's
FSM slide also omits the reset on that arc, so the slide should be corrected too.

**Fix** (`rtl/frame_aligner_fixed.sv:118`, tag `FIX DUT-03`): `fr_byte_position_rst = 1'b1` on the
reject arc.

---

### DUT-04 – `legal_frame_counter` wraps 3 → 0

| | |
|---|---|
| Severity | Low (latent) |
| Location | `rtl/frame_aligner.sv:242-253` (tag `DUT-04`) |
| Scenario | `long_valid_run` (TP16) |
| Figure | `wave_dut04_counters.png` |

The 2-bit counter increments on every valid header, so the 4th consecutive frame
brings it back to 0 (the spec's waveform 2 even draws the wrapped value). Today this
is invisible on the ports, because `frame_detect` is sticky and the set/clear
conflict is unreachable. That was shown by case analysis and by ~910k fuzzed
cycles in which the original RTL matches the bug-emulating Python model exactly. Any change that makes the set condition
level-sensitive (for example a fly-wheel for DUT-07) would expose it.
`WB_DUT04_LEGAL_NO_WRAP` catches it at its root cause.
**Fix:** saturate at 3.

### DUT-05 – `na_byte_counter` wraps 63 → 0

| | |
|---|---|
| Severity | Low (latent) |
| Location | `rtl/frame_aligner.sv:255-268` (tag `DUT-05`) |
| Scenario | `long_garbage` (TP17) |

After 64 header-less bytes the counter wraps and passes 47 again (harmless today,
because `frame_detect` is already 0). `WB_DUT05_NA_NO_WRAP` catches it.
**Fix:** saturate at 63.

### DUT-06 – Coding issues

| Item | Location |
|---|---|
| `next_state` has no default assignment and the `case` has no `default`. It is complete today only because all four encodings are listed; adding a state infers a latch | `rtl/frame_aligner.sv:118-191` |
| `fr_byte_position == 8'd10` compares a 4-bit value with an 8-bit constant (`verilator -Wall`: WIDTHEXPAND) | `:180` |
| Comment "expected lsb header pattern" describes the MSB | `:214` |
| Comment on `na_byte_counter` says it counts "illegal frames"; it counts bytes | `:255` |

The repaired RTL is clean under plain `verilator -Wall` (checked by `make -C sim lint-fixed` and by CI). One justified `lint_off DECLFILENAME` is needed, because both RTL files define `module frame_aligner`.
No functional lint, latch or reset defect was found (async reset of every flop
verified).

### DUT-07 – No fly-wheel: alignment is never lost on slipped or mis-sized frames

| | |
|---|---|
| Severity | High (architectural; depends on [SPEC-02](#spec-02--text-versus-design-slides-frames-versus-bytes)) |
| Location | FSM architecture (`FR_IDLE` hunts byte by byte even while aligned) |
| Spec | Text p.3: "if four consecutive frames do not match the **expected** header, it declares the stream out of alignment" |
| Scenarios | `slip_in_sync` (TP27), `false_lock_in_sync` (TP19) |
| Figure | `wave_dut07_slip.png` |

Once aligned, the DUT does not check the header at the *expected* 12-byte boundary.
After any bad header it hunts byte by byte, and any header found within 45 bytes
re-bases the frame and clears the loss counter.

**Consequences:**
- **Slips and length errors never cause loss of alignment.** With 13-byte frames
  after alignment, every header arrives one byte late, and `frame_detect` stays 1
  forever. The same stream can never be aligned from reset (hysteresis).
- **Position tracking stops while `frame_detect = 1`.** After a single bad header,
  `fr_byte_position` reads 0 for the whole frame. A downstream demultiplexer keyed on
  it collapses a whole payload onto position 0.
- **False lock.** A header pattern inside the payload of a corrupted frame becomes
  the new frame boundary without any out-of-frame indication. The next real header
  is then treated as payload (student finding K7).

The reference model follows the design slides (hunting), so these scenarios are
*demonstrations*: they pass on both RTLs, and the behaviour is documented here.

**Proposed fix (not applied, architecture change):**
- While aligned, keep `fr_byte_position` counting 0..11, check the header only at
  the expected position, and count consecutive bad **frames** (declare
  out-of-frame at 4).
- Hunt byte by byte only while not aligned.
- If the byte-count architecture is kept, add a `position_valid` output (see SPEC-04).

### DUT-08 – X-optimistic header decode

| | |
|---|---|
| Severity | Low |
| Location | `rtl/frame_aligner.sv:201` and `:220` (decode, tag `DUT-08`), used by the FSM at `:118-191` |

`header_lsb_valid` and `header_msb_valid` become X when `rx_data` is X/Z. `if (X)`
takes the `else` branch, so in RTL simulation an unknown byte is silently decoded as
"not a header". The gate-level netlist propagates X into the FSM instead (confirmed
with a yosys netlist). RTL and gates therefore disagree, and the legacy tests that
drove X ([TB-04](#tb-04--x-driven-into-the-dut)) could never notice.

**Fix:**
- The new environment asserts `TB_IN_KNOWN` (no X/Z on `rx_data` outside reset) and
  never drives X.
- Optionally decode with `unique case` or add an input X-check in the RTL.

---

## 3. Specification issues

### SPEC-01 – Output data interface not implemented
The block description (p.5) says the aligner "outputs the 16-bit header followed by
the 80-bit payload". The design has no data output (student finding, confirmed).

### SPEC-02 – Text versus design slides: frames versus bytes
The text defines loss of alignment in **frames** without the *expected* header. The
design slides implement **48 hunting bytes**, with headers accepted at any offset.
The two differ as soon as frames slip or headers appear inside payloads (DUT-07). The
verification model follows the slides. The difference is reported as DUT-07.

### SPEC-03 – Waveform 2 and waveform 1 are inconsistent
- **Waveform 2** draws an `na_byte_count_rst` pulse in the first `fr_idle` cycle,
  so its counter lags the garbage index by one. It shows `frame_detect` falling one
  clock later than the FSM slide and the DUT (after 49 header-less bytes instead of
  48), and shows the counter returning to 0 after 47. The hand-written corrections
  on the slide only fix the start of the waveform.
- **Waveform 2** also draws `legal_frame_count = 2` with `frame_detect = 1`. That
  state is only reachable through the DUT-04 wrap.
- **Waveform 1** starts with `fr_idle`, position 11, legal 0, `frame_detect` 0. That
  combination is unreachable.

### SPEC-04 – `fr_byte_position` is undefined outside a frame
The port table defines the position "in the header or the payload". Nothing defines
the value while hunting, and there is no valid qualifier. So 0 means both "header
LSB" and "not aligned". Recommendation: define it as 0 while hunting (rule R6, what
the repaired RTL does), or add a `position_valid` output.

### SPEC-05 – Naming mismatches
- Port table: `fr_is_aligned`; RTL: `frame_detect`.
- Register table: `na_frame_counter[5:0]`; RTL: `na_byte_counter` (it counts bytes).
- `Valid_h2` is listed in the register table but does not exist.

### SPEC-06 – The 48th byte is a header LSB
If the 48th header-less byte is the LSB of a header that is completed by the next
byte, there are two readings:
- **Register-table reading:** the LSB is counted when it arrives, so the counter
  "reaches 48" and alignment drops. The verification model uses this reading.
- **Look-ahead reading:** bytes that belong to a valid header never count, so
  alignment is kept.

`scripts/fa_model.py` implements both. The delivered RTL violates both (DUT-02). The
spec should state which one is intended.

---

## 4. Legacy testbench defects

Evidence for each defect is either:
- a run of the unmodified legacy environment on Verilator 5.048, with only the
  shims listed under TB-10; or
- an exact analysis of the code.

Where Verilator could not reproduce the legacy stimulus faithfully (it does not
honour the legacy inline size constraints), only structural numbers are quoted.

### TB-01 – The reference model was copied from the RTL
`legacy/frame_aligner_model.sv` re-implements the RTL line by line. The presentation
states the method: "whenever there was a mismatch between the scoreboard results
and the DUT, I corrected the scoreboard". A checker built this way can only confirm
that the RTL does what the RTL does. With the legacy random stimulus, DUT-01 and
DUT-02 are triggered in most runs (thousands of spec-deviating cycles over 200 seeds)
and produce **zero** scoreboard errors.
**New environment:** a SystemVerilog specification model (rules R1–R7), with the DUT
behaviour kept only as a triage model. Two independent Python models (a causal model
and an offline frame parser) agree with the repaired RTL on ~910k fuzzed cycles, and
the SystemVerilog model agrees with it on the same kind of fuzz traffic replayed
through the bench (`+TEST=file`) and on the whole regression.

### TB-02 – The reference model updates `frame_detect` one byte early
`frame_aligner_model::step()` updates the counters first and then evaluates the
`frame_detect` set/clear conditions on the *new* values. The RTL flop uses the
*old* values. The model therefore raises `frame_detect` on the 3rd header MSB
instead of payload byte 0, and clears it on the 47th header-less byte instead of the
48th. With any monitor pairing the legacy scoreboard reports a mismatch at every
alignment change, or tens of thousands of position mismatches. So "the model is a
copy of the RTL" is not even true, and the checker cannot have produced a clean run.

### TB-03 – End of test stops before the stimulus is driven
`environment::post_test` waits for `drv.num_transactions == gen.repeat_count`
(800). The directed tests send several transactions each, so the generator queues
**917** transactions. The simulation ends after 800, with **116 still in the mailbox**
and one partially driven. This was identical for every seed. The test cases at the
end of the shuffled queue are therefore silently not run.
**New environment:** waits until every queued item has been driven and the pipeline
has drained. It checks that the mailboxes are empty and that every checkpoint was
evaluated.

### TB-04 – X driven into the DUT
`trans.frame = new[N]` on a `logic [7:0]` dynamic array creates X elements. Five
directed tests set only a few bytes and drive the rest as X:
- `test_correct_lsb_invalid_msb`;
- `test_correct_msb_invalid_lsb`, which also uses `8'hxA`;
- `test_header_swapped__lsb_msb`;
- `test_reversed_bit_headers`;
- `test_msb_and_lsb_and_valid_header_in_middle_frame`.

Because of DUT-08 and the 2-state scoreboard (TB-09), nothing reported it.
**New environment:** 2-state bytes and the `TB_IN_KNOWN` assertion.

### TB-05 – Directed tests do not test what they claim
- All directed tests are shuffled together with random transactions. A test's
  precondition (e.g. "when frame_detect is high") holds only by chance: most
  directed instances run without it and check nothing.
- `test_45/46/47/48_bytes` and `test_illegal_headers_with_a_valid_header_in_the_middle_frame`
  end in the middle of the frame they start. Their payload consumes the first 4–10
  bytes of the next, randomly chosen test.
- `…_middle_frame_10_clock` sends one extra byte, so its planned outcome
  (frame_detect = 1) can never happen.
- `test_47_bytes` starts with `AA AA AF`, so its result depends on DUT-01. With
  DUT-01 fixed, the outcome flips.
- `test_4_illegal_header` does not send "4 frames with incorrect headers" (random
  lengths 2–49 bytes). It cannot check the 4-frame rule.
- `test_reversed_bit_headers` sends the bitwise **complement**, not a bit reversal.
  Both map AA↔55, so it only repeats "valid LSB + wrong MSB".
- The test-plan byte numbering (presentation p.14) is off by one from the code.
- Only the reference model checked results. The test plan's "expected outcome"
  column was never checked.

**New environment:**
- every scenario starts from reset;
- expected outcomes are executable checkpoints at exact byte positions;
- every legacy test has a corrected successor (VERIFICATION_PLAN §4).

### TB-06 – Assertions are vacuous or wrong
| Legacy property | Problem | Measured |
|---|---|---|
| `check_frame_detect_after_3_headers` | `##0` fuses the sequences (frame 2 would have to start on the last byte of frame 1), so it never matches legal traffic. It matches only 11-byte pseudo-frames, where it then fails; the consequent timing is wrong too | 7 false failures (seed 1) |
| `fr_byte_position_not_reset_when_above_2` | fails on every pair of back-to-back frames (11 → 0 is the normal boundary) | 102 false failures (seed 1) |
| `check_frame_detect_reset` | requires position ≤ 2 for 56 cycles after alignment (false as soon as the payload continues), and the window is one cycle short even for its target scenario | fails on every alignment |
| cover `check_fr_byte_position_reset_on_header` | off by one: it never covers a real header | – |

In addition:
- assertion failures were not included in "Total Errors Detected";
- the `bind` was not elaborated by Verilator (TB-10), so the assertions may never
  have run at all.

**New environment:**
- 14 black-box and 11 white-box assertions, each tied to a spec rule;
- failures are counted in the verdict;
- cover counters show that the key assertion antecedents are exercised (not vacuous).

### TB-07 – Coverage model cannot close and measures no spec feature
- `illegal_bins` on `na_byte_position` values 48..63 are **reachable** (e.g. by
  `test_48_bytes`), which produces false errors.
- `legal_frame_counter_cp` has unreachable bins (4..15 on a 2-bit variable) and no bin for 0.
- `ignore_bins` removes the main in-sync combination (`frame_detect` = 1 with 3 frames).
- The 4-way header crosses exclude the `default` bins. They therefore cannot see a
  normal frame start (header after a payload byte): 98 % of real frame starts are
  invisible to them.
- The crosses are huge (up to 2 400 bins, mostly unreachable), and the reachable
  maximum is 27 %.
- No temporal feature is measured. A stream that exposes DUT-02 adds zero bins over
  a benign stream.
- `monitor_out_cg` has no bin for position 11 (the spec range is 0–11), and it
  crosses hierarchical references.

**New environment:** 14 spec-feature coverpoints (VERIFICATION_PLAN §5), 100 % closed.

### TB-08 – Simulator-dependent monitor alignment and races
- The monitors sample with `@(posedge clk)` inside a `program`. The pairing of
  input and output samples is only correct under reactive-region scheduling. On a
  simulator without it, the legacy scoreboard reports thousands of mismatches.
- Reset is released with `#15`, exactly on a rising clock edge (a race).

**New environment:**
- clocking blocks for the driver (1 ns output skew), for reset (falling edge) and
  for the monitors (`#1step`);
- explicit one-cycle alignment in the scoreboard;
- lock-step cycle counters.

Also documented (`tb/frame_inf.sv`): a process must not mix `@(posedge clk)` and
`@(cb)`. It can resume twice in the same time step, which was observed to shift the
stream by one byte.

### TB-09 – X masked by 2-state scoreboard variables
The scoreboard copies the DUT outputs into `bit` variables, which turns X/Z into 0,
so an X output could "match". **New environment:** 4-state monitor items, `===`
comparisons, and an explicit X/Z check.

### TB-10 – Build and elaboration problems
- `build.list` compiles `scoreboard.sv` before `frame_aligner_model.sv`: "reference
  before declaration" (IEEE 1800 §6.18).
- `bind a1 frame_assertions … (.clk(i_inf.clk) …)` binds by instance name with
  upward references into the testbench. Verilator silently does not elaborate it.
- Untyped `mailbox` and an `inside {transaction::HEAD_1, …}` inline constraint
  needed shims on Verilator (tool limitations, not legacy bugs).

**New environment:** a package with an explicit order, `bind` by module type with the
module's own port names, and typed `std::mailbox`.

### TB-11 – Smaller issues
- `for (int i = 0; i < 50; i++) frame[i] = …` on 49-element arrays (4 tests):
  out-of-bounds writes.
- "ILLEGAL" transactions can contain valid headers (across the header/payload
  boundary or inside the payload), so their label is misleading. The new
  transaction can generate strictly illegal frames (`embed_headers = 0`).
- No seed control or seed reporting. Test IDs are printed as numbers.
- About 9 log lines per byte (more than 100 000 lines per run). The new environment
  has 4 verbosity levels.
- `wait (gen.ended.triggered)` only works because the generator finishes in the
  same time step. It would hang with a bounded mailbox.
- A stale comment in `test_3_valid_frames_in_the_invalid_frame` ("valid LSB at byte 47").

---

## 5. Reclassification of the original findings

| Original finding (presentation) | Classification here |
|---|---|
| Output interface missing (slide 18) | SPEC-01, confirmed |
| Byte count starts at the header MSB (slide 20) | Not a defect: the output is registered and describes the previous byte (waveform 1). Documented in rule R6 |
| `frame_detect` rises one cycle after 3 headers (slide 21) | Not a defect: matches waveform 1 (R4) |
| 48 bytes without header ends alignment (slide 22) | Correct in general, **but** see DUT-02 |
| Position goes to 1 after a rejected header (slide 23) | **DUT-03** |
| Counter reset/increment timing (slide 24) | Part of DUT-02 (the clear is unqualified); counting the header LSB itself follows the register table |
| "Last opportunity is a header at byte 45" (slides 25–27) | **DUT-02** |
| LSB twice then MSB is not recognised (slides 28–29) | **DUT-01**, with much larger impact than recorded (legal traffic, permanent loss) |
| Header inside an illegal payload skips a real header (slide 30) | Consistent with the hunting architecture (TP12); part of DUT-07 |
| Headers every ≤ 45 bytes keep alignment forever (slide 31) | **DUT-07** |
