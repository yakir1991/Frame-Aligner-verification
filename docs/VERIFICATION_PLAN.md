# Frame Aligner – Verification Plan and Report

| | |
|---|---|
| Design under test | `frame_aligner` (`rtl/frame_aligner.sv`, delivered RTL, logic unchanged) |
| Reference repair | `rtl/frame_aligner_fixed.sv` (DUT-01..06 from [BUG_REPORT.md](BUG_REPORT.md) repaired; DUT-07/08 intentionally unchanged) |
| Specification | `docs/spec/Frame_Aligner_Spec_10.24.pdf` |
| Environment | SystemVerilog, class-based, `tb/` (runs on Verilator ≥ 5.030; standard IEEE 1800 for commercial tools) |
| Author | Yakir Aqua |

Contents
1. [Design summary](#1-design-summary)
2. [Specification interpretation](#2-specification-interpretation-rules-r1r7)
3. [Verification environment](#3-verification-environment)
4. [Test plan](#4-test-plan)
5. [Coverage plan](#5-coverage-plan)
6. [Assertion plan](#6-assertion-plan)
7. [Regression and sign-off criteria](#7-regression-and-sign-off-criteria)
8. [Results](#8-results)
9. [How to run](#9-how-to-run)

---

## 1. Design summary

The frame aligner receives one byte per clock (`rx_data[7:0]`) and looks for a 16-bit
header, sent LSB first:

| Header | Value | Byte order on `rx_data` |
|---|---|---|
| HEAD_1 | `0xAFAA` | `AA` then `AF` |
| HEAD_2 | `0xBA55` | `55` then `BA` |

A frame is 12 bytes (2 header bytes and 10 payload bytes), and frames arrive back to back.

| Port | Dir | Description |
|---|---|---|
| `clk` | in | byte clock |
| `reset` | in | asynchronous, active high |
| `rx_data[7:0]` | in | byte stream |
| `fr_byte_position[3:0]` | out | registered: index 0..11 of the byte sampled on the previous edge |
| `frame_detect` | out | registered: frame alignment declared |

The micro-architecture comes from the spec's design slides: a four-state FSM
(`FR_IDLE → FR_HLSB → FR_HMSB → FR_DATA`), a 2-bit consecutive-frame counter and a
6-bit "not aligned" byte counter.

## 2. Specification interpretation (rules R1–R7)

The specification text, the design slides (FSM, register table, waveforms) and the
DUT disagree in several places ([BUG_REPORT.md §3](BUG_REPORT.md#3-specification-issues)).
The verification team fixed the interpretation below. It is implemented
independently three times:
- the SystemVerilog reference model (`tb/fa_ref_model.sv`);
- a causal Python model (`scripts/fa_model.py: CausalModel`);
- an independent, non-causal Python frame parser (`offline_spec`).

The two Python models agree with each other and with the repaired RTL on every one
of ~910k fuzzed cycles (`scripts/fuzz_rtl.py`, seeds 1 and 7). The SystemVerilog
model agrees with the repaired RTL on the whole regression and on fuzz traffic
replayed through the bench (`+TEST=file`, §7).

| Rule | Statement | Source |
|---|---|---|
| **R1** | A header is an LSB followed immediately by its MSB: `AA AF` or `55 BA`. | spec text p.3, p.5 |
| **R2** | While hunting, every byte is examined. If a candidate's MSB is wrong and that byte is itself a header LSB, it becomes the new candidate, so no header that is fully present in the stream is ever missed. | spec text ("constantly monitoring the incoming data stream"); a header missed because of the byte before it breaks R4 |
| **R3** | After a validated header, the next 10 bytes are payload and are not examined, so header patterns inside a payload are ignored. The byte after the payload is expected to be the next header LSB. | design slides (FSM) |
| **R4** | `frame_detect` rises one byte after the 3rd consecutive header is validated, i.e. on payload byte 0 of the 3rd frame. "Consecutive" means no hunting byte between the frames. | text p.6, waveform 1 |
| **R5** | `frame_detect` falls on the 48th consecutive *counted* byte (4 frames × 12 bytes). Every hunting byte is counted when it arrives, a header LSB included (register table: "counter reaches 48"). The byte that completes a header (MSB) and the payload bytes are never counted, so they can never clear alignment. A header completed before the count reaches 48 keeps alignment. | text p.6, register table, FSM |
| **R6** | `fr_byte_position` (registered) is the index of the byte just consumed within its frame: LSB 0, MSB 1, payload 2..11. It is 0 while hunting. | port table ("range 0–11"), waveform 1 |
| **R7** | Asynchronous reset clears everything; the outputs are 0 while reset is high. | port table |

**Documented interpretation choices**
- *R5, 48th byte is a header LSB:* the model follows the register table (the LSB is
  counted, so the counter "reaches 48" and alignment drops even if the next byte
  completes the header). A look-ahead reading would keep alignment.
  `scripts/fa_model.py` implements both readings, and the delivered RTL violates
  both (DUT-02).
- *Fly-wheel:* the spec text says alignment is lost after "four consecutive frames"
  without the *expected* header. The design slides implement byte-wise hunting
  instead. The model follows the design slides. The difference is reported as an
  architectural defect (DUT-07) and demonstrated by TP19/TP27.
- *`fr_byte_position` outside a frame:* the spec does not define it. R6 requires 0
  (the value the FSM produces everywhere except after a rejected header, DUT-03).

## 3. Verification environment

```
          +-----------+  gen2drv   +--------+   frame_inf      +-------------------+
          | generator |----------->| driver |=================>| DUT frame_aligner |
          | + seq lib |            +--------+  drv_cb / rst_cb |  + fa_spec_sva    |
          +-----------+                                        |  + fa_whitebox_sva|
                |  checkpoints                                 +-------------------+
                v                   +------------+  mon_cb           |      |
          +---------------+  <------| monitor_in |<------------------+      |
          |  scoreboard   |         +------------+                          |
          |  spec model   |         +-------------+ mon_cb                  |
          |  DUT model    |  <------| monitor_out |<------------------------+
          |  coverage     |         +-------------+
          +---------------+
```

| File | Role |
|---|---|
| `tb/frame_inf.sv` | Interface. The clocking blocks `drv_cb` (drive 1 ns after the edge), `rst_cb` (reset on the falling edge) and `mon_cb` (`#1step` sampling) remove every race. The side band `tb_byte_idx`/`tb_byte_valid` tags each byte with its stream index. |
| `tb/transaction.sv` | Stimulus item (the spec's *frame_item*). Kinds: valid, illegal (5 ways to break a header), stray-LSB restart, gap near the loss threshold, reset, raw. The bytes are 2-state. |
| `tb/generator.sv` | Builds the whole stream for the selected test. Tracks byte indices and registers checkpoints. |
| `tb/sequence_lib.sv` | 27 directed scenarios (the test plan in executable form). Each starts from reset and states its expected outcome. |
| `tb/driver.sv` | Drives one byte per clock back to back. Mid-stream asynchronous reset. Idle bytes after the stream. |
| `tb/monitor_in.sv`, `tb/monitor_out.sv` | Passive monitors. Samples are numbered so the scoreboard can prove lock-step. |
| `tb/fa_ref_model.sv` | Specification model (R1–R7) with bug-emulation knobs `DUT-01..03`. |
| `tb/scoreboard.sv` | Cycle-accurate comparison against two model instances: spec (knobs off) and DUT (knobs on). Every mismatch is classified as **known defect** (and attributed to the knob that fired) or **unexplained**. Also X/Z, reset values, checkpoints. |
| `tb/fa_coverage.sv` | Functional coverage: a portable collector (the reference metric) plus native covergroups for the per-byte points. |
| `tb/fa_spec_sva.sv` | Black-box assertions (ports only). Every property is one of the rules R1–R7. |
| `tb/fa_whitebox_sva.sv` | White-box assertions on the FSM and counters. Catches latent defects (DUT-04/05) that never reach the ports. |
| `tb/environment.sv`, `tb/fa_test.sv`, `tb/tb_top.sv` | Build and connect everything, handle plusargs, write the final report and the machine-readable `FA_RESULT` line. |

**Why two models.** The legacy model was a copy of the RTL, and the legacy rule was
"when the scoreboard disagrees with the DUT, fix the scoreboard", so it could never
find a design bug. The new scoreboard compares against the *specification*. The
second model (the delivered design with its known defects) is only used to triage:
it proves that every deviation is a known defect, and it lets checking continue on
the DUT's real path after a defect occurs (one report per occurrence, no cascades).
With `+MODEL=dut` the same environment becomes a regression bench for the delivered
design, which only fails on *new* behaviour.

**Three independent oracles per cycle.**
- The reference model checks every byte.
- The checkpoints check the test plan's expected outcome at exact bytes.
- The SVA check the spec rules on the ports and the micro-architecture inside.

## 4. Test plan

Every directed scenario starts from reset, so its preconditions hold by construction.
The "legacy" column names the original test it replaces; the reasons are listed in
BUG_REPORT §4.

| ID | Scenario (`+TEST=`) | Purpose | Stimulus | Expected outcome (spec) | Exposes | Legacy |
|---|---|---|---|---|---|---|
| TP01 | `spec_suggested` | Test suggested by the spec (p.23) | 5×HEAD_1, 4 illegal frames, 5×HEAD_2 | aligned on payload[0] of frame 3; aligned after 47 header-less bytes, lost on the 48th; re-aligned on HEAD_2 #3 | – | test_5_head1, test_4_illegal_header, test_5_head2 |
| TP02 | `mixed_headers` | Header types can be mixed | H1 H2 H1 / H2 H1 H2 H1 | aligned after the 3rd frame | – | test_3_random_valid_headers |
| TP03 | `swapped_header` | MSB before LSB is not a header | `AF AA …`, `BA 55 …`; 4 of them while aligned | never aligns; loss exactly on the 48th byte | DUT-03 | test_header_swapped__lsb_msb |
| TP04 | `inverted_header` | Bit-inverted and bit-reversed headers | `55 50`, `AA 45`, `55 F5`, `AA 5D` | never aligns (the LSBs are valid LSBs of the other type) | DUT-03 | test_reversed_bit_headers |
| TP05 | `lsb_ok_msb_bad` | Wrong MSB is rejected, no position | `AA 01`, `55 01`, `AA 00`, `55 00`, `AA BA`, `55 AF` | position 0 after the rejected MSB | DUT-03 | test_correct_lsb_invalid_msb |
| TP06 | `lsb_bad_msb_ok` | Wrong LSB | `0A AF`, `05 BA` | position 0, never aligns | – | test_correct_msb_invalid_lsb |
| TP07 | `msb_in_payload` | MSB values inside payloads are ignored | AF/BA in payloads while aligned | frame boundaries and alignment unchanged | – | test_msb_and_lsb_… |
| TP08 | `header_in_payload` | Complete headers inside payloads are ignored | header at every payload offset | same | – | test_msb_and_lsb_… |
| TP09 | `restart_header` | A stray LSB before a header must not hide it | `AA\|AA AF`, `55\|55 BA`, `AA\|55 BA`, `55\|AA AF`, `AA AA\|AA AF`, `55 AA\|55 BA` + 2 frames | header recognised; aligned after 3 frames | **DUT-01** | test_47_bytes (part) |
| TP10 | `loss_boundary` | Loss threshold | aligned, G = 44..48 header-less bytes, header | kept for G ≤ 46, lost for G ≥ 47 | **DUT-02** | test_45/46/47/48_bytes |
| TP11 | `corrupted_frames` | "4 incorrect frames" rule | aligned, N = 1..4 corrupted frames | kept for N ≤ 3; lost on the 48th byte for N = 4 | DUT-03 | – |
| TP12 | `header_in_illegal` | Header inside an illegal frame is a header | legacy 12/16-byte illegal frames | frame at byte 4 recognised; the real header inside it is hidden | – | test_illegal_headers_…_middle_frame(_10_clock) |
| TP13 | `frames_in_illegal` | 3 frames inside an illegal frame | 49×00 with headers at 3, 15, 27 | aligned exactly on byte 29 | – | test_3_valid_frames_in_the_invalid_frame |
| TP14 | `header_soup` | Random header bytes | `DE 00` + 47 bytes from {AA,AF,55,BA} | checked by the model | DUT-01, DUT-03 | …_middle_frame_random |
| TP15 | `lsb_at_payload_end` | LSB/MSB values as the last payload bytes, while aligned | payload ends `AA`, `55`, `AA AF` | next header found normally | – | – |
| TP16 | `long_valid_run` | 10 consecutive frames | – | stays aligned; counter must not wrap | DUT-04 (white-box) | – |
| TP17 | `long_garbage` | 80 header-less bytes, then re-align | – | lost on the 48th byte; counter must not wrap; re-align | DUT-05 (white-box) | – |
| TP18 | `reset_every_phase` | Asynchronous reset while hunting / after an LSB / inside a frame, aligned or not | – | outputs 0; no header across a reset | – | – |
| TP19 | `false_lock_in_sync` | Corrupted header + header pattern in its payload while aligned | – | locks onto the false frame (hunting architecture) | DUT-07 (demo) | – |
| TP20 | `consecutive_rule` | One hunting byte breaks the chain | V, 1 byte, V, V, V; V, V, stray `AA`/`55`, V, V, V | aligned only on the 3rd frame after the break (a stray LSB restarts the chain too) | – | – |
| TP21 | `header_across_items` | Header split across two stimulus items | `… AA \| AF …` | recognised | – | – |
| TP22 | `illegal_lengths` | Illegal frames of different lengths while aligned | 2 + 12 + 36 header-less bytes; one 49-byte illegal frame | lost on exactly the 48th header-less byte | – | – |
| TP23 | `boundary` | Sweep of R5 | aligned, G = 0..60 header-less bytes, with or without a stray LSB | kept iff G + prefix ≤ 46 | **DUT-01, DUT-02** | – |
| TP24 | `loss_cause` | Every kind of 48th byte; restart while aligned | 46 bytes + `AA 01`, 46 + `AA 55`, `AA 55 BA` | lost on the rejected MSB / restart LSB; restart keeps alignment | DUT-01 | – |
| TP25 | `midstream_entry` | Start-up in the middle of a legal stream whose payloads end in a single `55`/`AA` | – | aligned after 3 frames | **DUT-01 (never aligns)** | – |
| TP26 | `error_then_lsb_payloads` | One header error while aligned, then legal frames ending in `55` | – | alignment kept (12 header-less bytes) | **DUT-01 (permanent loss)** | – |
| TP27 | `slip_in_sync` | 13-byte frames before and after alignment | – | never aligns from reset; hunting keeps alignment | DUT-07 (demo) | – |
| TPR | `random` | Constrained random: 60% valid, 18% illegal, 8% restart, 12% gap, 2% reset (+`NUM_ITEMS`) | – | checked by the model and the SVA | all | random_test |

## 5. Coverage plan

The functional coverage is sampled from the reference model's per-byte step
information, so it measures **specification features**, not raw signal values.

| ID | Coverpoint | Bins | Why |
|---|---|---|---|
| CP01 | rx_class | AA, 55, AF, BA, 00, FF, other | all byte classes seen |
| CP02 | arc | hunt→hunt, hunt→lsb, lsb→frame, lsb→reject, lsb→restart, frame→frame, frame→end | every transition of R1–R3 |
| CP03 | arc × frame_detect | 14 | every transition while aligned and not aligned |
| CP04 | header type × frame_detect | 4 | both headers in both modes |
| CP05 | consecutive frames at validation | 1, 2, 3, 4+ | R4 counting |
| CP06 | byte after a rejected LSB | {AA,55} × {same LSB, other LSB, other MSB, 00, other} | R2 restart cases |
| CP07 | gap before a header while aligned | 0, 1–11, 12–23, 24–35, 36–44, **45**, **46 (last chance)** | R5 threshold |
| CP08 | loss cause | plain byte, candidate LSB, rejected MSB, restart LSB | R5: every kind of 48th byte |
| CP09 | fr_byte_position × frame_detect | 24 | R6 full range |
| CP10 | sync events | gained, lost | R4/R5 |
| CP11 | reset phase | {hunt, lsb, frame} × aligned | R7 |
| CP12 | header inside payload | not aligned, aligned | R3 |
| CP13 | illegal payload length (stimulus) | 0, 1–9, 10, 11–46, 47 | legacy illegal definition |
| CP14 | item kinds (stimulus) | 6 | stimulus mix |

Coverage target: 100% of all bins in the regression. Reached with `+TEST=regression`
(see §8). The white-box and spec cover properties (`C_*`) must all be hit, which
shows that the key assertion antecedents are exercised (the checks are not vacuous).

## 6. Assertion plan

| Assertion | Rule | Fails on the original DUT because of |
|---|---|---|
| `SPEC_OUT_KNOWN`, `TB_IN_KNOWN` | no X/Z on outputs; the TB never drives X | – |
| `SPEC_RESET_VALUES` | R7 | – |
| `SPEC_POS_RANGE`, `SPEC_POS_AFTER_FRAME`, `SPEC_POS_FROM_ZERO` | R6 | – |
| `SPEC_POS_INCREMENT` | R3/R6: positions 1..10 advance by one | DUT-03 |
| `SPEC_POS1_AFTER_HEADER` | R6: position 1 only after a real header | DUT-03 |
| `SPEC_FD_RISE_POSITION`, `SPEC_FD_RISE_3_FRAMES` | R4: rise on payload[0] after 3 consecutive frames | – |
| `SPEC_SYNC_AFTER_3_FRAMES` | R2+R4: three consecutive frames always align | DUT-01 |
| `SPEC_FD_FALL_WHILE_HUNTING`, `SPEC_FD_FALL_AFTER_48`, `SPEC_FD_HOLD_IN_FRAME` | R5: never lost early, never inside a validated frame | DUT-02 (and DUT-03) |
| `SPEC_FD_LOST_AFTER_48` | R5: always lost once 48 consecutive hunting bytes were consumed (added after mutation testing, §8.1) | – |
| `WB_DUT01_NO_LOST_LSB` | FSM stays in HLSB on a restart LSB | DUT-01 |
| `WB_DUT02_NO_CLEAR_IN_FRAME` | frame_detect is never cleared by a valid header or payload | DUT-02 |
| `WB_DUT03_POS_RESET_ON_REJECT` | position 0 after a rejected header | DUT-03 |
| `WB_DUT04_LEGAL_NO_WRAP`, `WB_DUT05_NA_NO_WRAP` | counters saturate | DUT-04, DUT-05 |
| `WB_HMSB_TO_DATA`, `WB_HLSB_ENTRY`, `WB_DATA_POSITION`, `WB_TRIGGERS_EXCLUSIVE`, `WB_LSB_SAMP_LEGAL`, `WB_STATE_KNOWN` | FSM structure from the design slides | – |

Tool note: Verilator 5.048 silently mis-evaluates `[*n]` repetition in a property
*consequent* and ignores cover-property pass statements. The assertions therefore use
repetition only in antecedents, and the `FA_COVER` macro counts cover hits portably.

## 7. Regression and sign-off criteria

`make -C sim regress` (`sim/regress.py`, default 3 seeds × 400 random items) runs the
matrix below. It passes only if **every** run matches its expectation, and it writes
`sim/logs/regression_summary.md`.

| Run | Expectation |
|---|---|
| `rtl/frame_aligner.sv` untouched | logically identical to the delivered `dut.sv`: SHA-256 of the comment-stripped token stream (`scripts/check_rtl_untouched.py`) |
| lint of the fixed RTL (`verilator -Wall`) | clean |
| fuzz replay, fixed RTL: 3 000 fuzzed streams (`fuzz_rtl.py --write-stim`) driven through the bench with `+TEST=file` | **PASS**: the SystemVerilog spec model matches the RTL on every cycle |
| fuzz replay, original RTL | **FAIL** with 0 *unexplained* mismatches and no X/Z |
| fixed RTL × {directed, boundary, random} × seeds, spec model | **PASS**: 0 mismatches, all checkpoints, 0 assertion failures |
| fixed RTL, `regression` × seeds, spec model | **PASS**, and 100 % functional coverage, and every cover property hit |
| original RTL, `regression` × seeds, `+MODEL=dut` | **PASS**: no behaviour beyond the documented defects |
| original RTL, `regression` × seeds, spec model | **FAIL** with 0 *unexplained* mismatches; DUT-01, 02 and 03 attributed by the scoreboard; `WB_DUT04_LEGAL_NO_WRAP` and `WB_DUT05_NA_NO_WRAP` fired |

CI (`.github/workflows/ci.yml`) runs on every push with stock Ubuntu packages only
(Ubuntu's Verilator is too old for the class-based bench):

| Step | Expectation |
|---|---|
| RTL untouched | as above |
| lint of the fixed RTL | clean |
| `scripts/fuzz_rtl.py --streams 1500` (Icarus) | fixed RTL = causal Python model = offline frame parser (0 differences); original RTL = bug-emulating model (0 differences) |

Run by hand (not part of the regression): `scripts/mutation_test.py` (§8.1).

## 8. Results

Numbers from the final regression (`make -C sim regress`, seed 1; seeds 2 and 3 give
the same picture, see `sim/logs/regression_summary.md`):

| Run | Cycles compared | Checkpoints | Spec deviations (all attributed) | Unexplained | Assertion failures | Coverage |
|---|---|---|---|---|---|---|
| fixed RTL, regression | 21 079 | 3 605 / 3 605 | 0 | 0 | 0 | **100 %**, 12/12 covers hit |
| original RTL, regression | 21 079 | 3 383 / 3 605 | 253 (DUT-01: 151, DUT-02: 3, DUT-03: 250)¹ | **0** | spec 561, white-box 477 | 100 % |
| fixed RTL, fuzz replay | 452 212 | – | 0 | 0 | 0 | 89.2 %² |
| original RTL, fuzz replay | 452 212 | – | 16 222 (DUT-01: 9 033, DUT-02: 35, DUT-03: 16 187)¹ | **0** | spec 32 918, white-box 27 032 | 89.2 %² |
| Python fuzzing (Icarus), 3 000 streams × seeds 1 and 7 | 909 673 | – | original RTL: 120 753 cycles (13.3 %), in 5 442 of 6 000 streams³ | 0 against the bug model | – | – |

¹ One deviation can be attributed to more than one defect.
² Replayed traffic has no stimulus items and no checkpoints, so the two stimulus coverpoints (CP13, CP14) stay empty.
³ Every differing cycle is counted. The scoreboard instead reports one deviation per defect occurrence and then re-synchronises, so its counts are lower.

With `+MODEL=dut` the original RTL passes the same regression: every deviation is
one of the documented defects.

### 8.1 Mutation testing

`scripts/mutation_test.py` measures how good the checkers are. It injects 20 single
faults (mutants) into the repaired RTL, one at a time, rebuilds the bench and runs
`+TEST=directed` and `+TEST=boundary` on each mutant. A mutant is *killed* when at
least one oracle detects it: the scoreboard (SB), the checkpoints (CP), the black-box
assertions (SVA) or the white-box assertions (WB). A surviving mutant points at a
hole in the checks.

| Mutant | Injected bug | Result | SB | CP | SVA | WB |
|---|---|---|---|---|---|---|
| M01 | restart branch returns to IDLE (re-introduces DUT-01) | KILLED | 100 | 201 | 22 | 114 |
| M02 | unqualified sync-loss clear (re-introduces DUT-02) | KILLED | 13 | 12 | 6 | 3 |
| M03 | no position reset on reject (re-introduces DUT-03) | KILLED | 59 | 10 | 121 | 59 |
| M04 | legal counter wraps again (re-introduces DUT-04, latent) | KILLED | 0 | 0 | 0 | 17 |
| M05 | not-aligned counter wraps again (re-introduces DUT-05, latent) | KILLED | 0 | 0 | 0 | 5 |
| M06 | loss threshold 47 bytes instead of 48 | KILLED | 55 | 23 | 42 | 0 |
| M07 | loss threshold 49 bytes instead of 48 | KILLED | 95 | 23 | 39 | 0 |
| M08 | frame of 13 bytes (payload end one byte late) | KILLED | 9811 | 1244 | 993 | 537 |
| M09 | frame of 11 bytes (payload end one byte early) | KILLED | 8111 | 1537 | 963 | 0 |
| M10 | alignment after 2 frames instead of 3 | KILLED | 2372 | 530 | 177 | 0 |
| M11 | HEAD_2 MSB constant wrong (0xBB) | KILLED | 8890 | 1407 | 176 | 0 |
| M12 | only HEAD_1 LSB recognised | KILLED | 8890 | 1407 | 176 | 0 |
| M13 | expected MSBs swapped between the header types | KILLED | 12236 | 2233 | 238 | 0 |
| M14 | alignment never lost (clear removed) | KILLED | 727 | 156 | 274 | 0 |
| M15 | not-aligned counter not cleared at the end of a frame | KILLED | 312 | 65 | 50 | 0 |
| M16 | consecutive-frame counter not cleared on a hunting byte | KILLED | 1031 | 154 | 275 | 0 |
| M17 | fr_byte_position reset value 1 | KILLED | 252 | 0 | 616 | 0 |
| M18 | header_lsb_samp never updated after reset | KILLED | 12145 | 2233 | 223 | 0 |
| M19 | FR_HMSB skipped (equivalent on the ports; FSM structure only) | KILLED | 0 | 0 | 0 | 746 |
| M20 | restart does not reset the consecutive-frame counter | KILLED | 48 | 12 | 2 | 0 |

**Mutation score: 20/20 killed.** Numbers are detections per oracle
(`sim/logs/mutation_summary.md`, regenerated by the script).

- Every mutant that is visible on the ports is caught by at least two independent
  oracles (always the scoreboard and the black-box assertions).
- M04, M05 and M19 are invisible on the ports (the latent counter wraps DUT-04/05 and
  an equivalent FSM shortcut). Only the white-box assertions catch them, which is why
  they exist.
- Mutation testing improved the environment twice:
  - the first run left **M20 alive**: no scenario put a stray header LSB between two
    frames. TP20 (`consecutive_rule`) now covers it;
  - the per-oracle numbers showed that **M07 and M14 escaped every black-box
    assertion**. The assertions only forbade an *early* loss of alignment.
    `SPEC_FD_LOST_AFTER_48` now also requires the loss after 48 hunting bytes.

## 9. How to run

```bash
# prerequisites: Verilator >= 5.030 with z3 (constrained randomisation), Python 3,
# Icarus Verilog >= 12 (only for scripts/), matplotlib (only for figures)
cd sim
make sim DUT=fixed TEST=regression            # corrected design: PASS
make sim DUT=orig  TEST=regression            # delivered design: FAIL, defects listed
make sim DUT=orig  TEST=regression MODEL=dut  # regression mode for the delivered design
make sim DUT=orig  TEST=restart_header VERBOSITY=2   # one scenario, detailed log
make sim DUT=orig  TEST=loss_boundary WAVES=1        # waves.vcd
make regress                                  # full matrix with expected outcomes
python3 ../scripts/fuzz_rtl.py --streams 3000 # differential fuzzing (Icarus)
python3 ../scripts/plot_waves.py              # regenerate docs/images/wave_*.png, slide_*.png
python3 ../scripts/mutation_test.py --jobs 1  # mutation score of the checkers (§8.1)
```

Plusargs: `+TEST`, `+MODEL=spec|dut`, `+SEED`, `+NUM_ITEMS`, `+VERBOSITY=0..3`,
`+DUT_NAME`, `+TIMEOUT_CYCLES`, `+COV_BINS`, `+DUMP`.
