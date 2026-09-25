# Frame Aligner Verification

A SystemVerilog verification environment for a byte-stream **frame aligner**. The
environment is checked against the specification, not against the RTL. It found
**8 defects in the delivered design** (three of them critical or high severity; the system-level impact of the worst one was previously unknown),
**6 specification issues** and **11 classes of defects in the original testbench**.
A corrected RTL passes the full regression with 100 % functional coverage.

| | |
|---|---|
| 📄 Bug report | [docs/BUG_REPORT.md](docs/BUG_REPORT.md) |
| 📋 Verification plan and results | [docs/VERIFICATION_PLAN.md](docs/VERIFICATION_PLAN.md) |
| 🖥️ Presentation | [docs/Frame_Aligner_Verification.pptx](docs/Frame_Aligner_Verification.pptx) / [.pdf](docs/Frame_Aligner_Verification.pdf) |
| 📐 Specification | [docs/spec/Frame_Aligner_Spec_10.24.pdf](docs/spec/Frame_Aligner_Spec_10.24.pdf) |

## The design in one paragraph

The aligner receives one byte per clock and looks for the 16-bit header `0xAFAA`
(`AA AF` on the wire) or `0xBA55` (`55 BA`). A frame is the header plus 10 payload
bytes.
- After **three consecutive** valid frames it raises `frame_detect`.
- After **48 bytes without a header** it drops `frame_detect`.
- `fr_byte_position` gives the index (0..11) of the last byte inside its frame.

## Headline findings

| ID | Defect | Severity |
|---|---|---|
| DUT-01 | A rejected header MSB that is itself a header LSB is thrown away. **Legal streams whose payloads end in `0xAA`/`0x55` are never aligned**, and one bit error can make the loss of alignment permanent | Critical |
| DUT-02 | Alignment is dropped on the byte that **completes a valid header** (after 46 header-less bytes) | High |
| DUT-03 | `fr_byte_position` reports "header MSB" after a **rejected** header | Medium |
| DUT-04/05 | Frame and byte counters wrap around (latent, found by white-box assertions) | Low |
| DUT-06 | Coding issues (missing default, width mismatch, wrong comments) | Info |
| DUT-07 | No fly-wheel: slipped or mis-sized frames never lose alignment | High (architecture) |
| DUT-08 | X-optimistic header decode (RTL vs. gate-level mismatch) | Low |

On the delivered RTL the regression reports every spec violation **attributed to
one of these defects, with zero unexplained mismatches**. On the corrected RTL
(`rtl/frame_aligner_fixed.sv`) it reports zero violations.

## Repository layout

```
rtl/
  frame_aligner.sv        delivered DUT (logic untouched, fully annotated; proof: scripts/check_rtl_untouched.py)
  frame_aligner_fixed.sv  corrected reference implementation (every change tagged FIX DUT-0x)
tb/
  frame_inf.sv            interface with clocking blocks (race-free drive/sample)
  fa_pkg.sv               package: all classes below
  fa_types.svh            constants, bug IDs, logging, assertion registry
  transaction.sv          stimulus item ("frame_item"): valid/illegal/restart/gap/reset
  generator.sv            test selection, stream building, checkpoints
  sequence_lib.sv         27 directed scenarios = the executable test plan
  driver.sv, monitor_in.sv, monitor_out.sv
  fa_ref_model.sv         specification reference model with bug-emulation knobs
  scoreboard.sv           cycle-accurate checker with defect triage
  fa_checkpoint.sv        monitor item + test-plan checkpoints
  fa_coverage.sv          functional coverage (portable collector + covergroups)
  environment.sv, fa_test.sv, tb_top.sv
  fa_spec_sva.sv          black-box assertions (spec rules on the ports)
  fa_whitebox_sva.sv      white-box assertions (FSM / counters)
  fa_cover.svh            portable cover-property macro
sim/
  Makefile, files_tb.f    build and run (Verilator; commands for Questa/VCS/Xcelium included)
  regress.py              regression matrix with expected outcomes
scripts/
  fa_model.py             two independent Python models of the specification
  fuzz_rtl.py             differential fuzzing of both RTL versions (Icarus Verilog)
  plot_waves.py           waveform figures of every defect from real simulations
  check_rtl_untouched.py  proves rtl/frame_aligner.sv == delivered DUT
  harness/tb_trace.sv     minimal RTL trace harness used by the scripts
docs/
  BUG_REPORT.md, VERIFICATION_PLAN.md, presentation, images/, spec/, legacy/ (original presentation)
legacy/                   the original verification environment, unchanged, for reference
```

## Quick start

Requirements:
- **Verilator ≥ 5.030** with z3 (tested with 5.048);
- Python 3;
- for `scripts/`: Icarus Verilog ≥ 12 and matplotlib.

```bash
cd sim
make sim DUT=fixed                  # corrected RTL, full regression test  -> TEST PASSED
make sim DUT=orig                   # delivered RTL                         -> TEST FAILED, defects listed
make sim DUT=orig MODEL=dut         # regression mode: only NEW behaviour fails -> TEST PASSED
make sim DUT=orig TEST=restart_header VERBOSITY=2    # a single scenario with details
make regress                        # the whole matrix, each run against its expected outcome
python3 ../scripts/fuzz_rtl.py      # differential fuzzing of both RTL versions
```

The end of a run on the delivered RTL (abridged):

```
 SCOREBOARD (primary model: SPECIFICATION)
  compared cycles      : 20398
  spec violations      : 269  (explained by known DUT defects)
      DUT-01 header LSB lost after a rejected MSB                  137
      DUT-02 sync dropped on a byte that completes a valid header     3
      DUT-03 fr_byte_position=1 after a rejected header             266
  UNEXPLAINED mismatch : 0
  checkpoints          : 3341 passed, 214 failed
 ASSERTIONS  (spec black-box: 519 failures, white-box: 418, testbench: 0)
  WB_DUT04_LEGAL_NO_WRAP ...  WB_DUT05_NA_NO_WRAP ...
FA_RESULT verdict=FAIL ... unexplained=0 ... bugs=DUT-01:137,DUT-02:3,DUT-03:266 cov=100.0
```

## How the environment works

- **Specification model, not an RTL copy.** `tb/fa_ref_model.sv` implements rules
  R1–R7 derived from the spec (VERIFICATION_PLAN §2). Two independent Python models
  agree with it on every cycle of 900k fuzzed cycles.
- **Defect triage.** The scoreboard runs the model twice: as the specification, and
  as the delivered design (bug knobs on). Every deviation is either a *known defect*
  (automatically attributed, after which checking continues on the DUT's real path)
  or an *unexplained* mismatch.
- **Three independent oracles.**
  - the cycle-accurate model;
  - test-plan checkpoints ("after byte N, frame_detect must be 1") at exact byte positions;
  - 25 assertions (14 black-box spec rules and 11 white-box micro-architecture checks).
- **Race-free timing.** Clocking blocks for driving (1 ns skew), reset (falling
  edge) and sampling (`#1step`), and a stream index on a testbench side band.
- **Coverage of spec features.** 14 coverpoints, including the loss threshold
  (gaps of 45, 46 and 47 bytes), every restart combination, every cause of loss and
  reset in every phase. Closed at 100 %.

## Author

Yakir Aqua. The original DUT RTL is by Ilan Rachmanov (course material).
MIT License, see [LICENSE](LICENSE).
