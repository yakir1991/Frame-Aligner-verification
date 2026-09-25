# Legacy verification environment (original, unchanged)

These are the original testbench files, kept **unchanged** for reference and for
before/after comparison.
- The DUT they were written for is now `rtl/frame_aligner.sv`. It is logically
  identical to the former `dut.sv`, with comments added.
- The replacement environment is in `tb/`.

The defects found in these files are described in
[docs/BUG_REPORT.md §4](../docs/BUG_REPORT.md#4-legacy-testbench-defects).
The table below maps each original test to its corrected successor in
`tb/sequence_lib.sv`.

| Legacy file | Replaced by (`+TEST=`) |
|---|---|
| `test_5_head1.sv`, `test_4_illegal_header.sv`, `test_5_head2.sv` | `spec_suggested` (TP01) |
| `test_3_random_valid_headers.sv` | `mixed_headers` (TP02) |
| `test_header_swapped__lsb_msb.sv` | `swapped_header` (TP03) |
| `test_reversed_bit_headers.sv` | `inverted_header` (TP04) |
| `test_correct_lsb_invalid_msb.sv` | `lsb_ok_msb_bad` (TP05) |
| `test_correct_msb_invalid_lsb.sv` | `lsb_bad_msb_ok` (TP06) |
| `test_msb_and_lsb_and_valid_header_in_middle_frame.sv` | `msb_in_payload`, `header_in_payload` (TP07, TP08) |
| `test_45_bytes.sv` … `test_48_bytes.sv` | `loss_boundary` (TP10), `boundary` (TP23) |
| `test_47_bytes.sv` (`AA AA AF` part) | `restart_header` (TP09) |
| `test_illegal_headers_with_a_valid_header_in_the_middle_frame(_10_clock).sv` | `header_in_illegal` (TP12) |
| `test_3_valid_frames_in_the_invalid_frame.sv` | `frames_in_illegal` (TP13) |
| `test_illegal_headers_with_a_valid_header_in_the_middle_frame_random.sv` | `header_soup` (TP14) |
| `random_test.sv` (800 transactions) | `random` / `regression` |
| `frame_aligner_model.sv` (RTL copy) | `tb/fa_ref_model.sv` (specification model) |
| `assertions.sv` | `tb/fa_spec_sva.sv`, `tb/fa_whitebox_sva.sv` |
