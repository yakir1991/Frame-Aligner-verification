#!/usr/bin/env python3
"""Mutation testing of the verification environment.

A verification environment is only as good as the bugs it can find.  This
script injects one small, realistic bug at a time into the CORRECTED RTL
(rtl/frame_aligner_fixed.sv), rebuilds the testbench with Verilator, runs the
directed and boundary tests, and records which oracle detects ("kills") each
mutant:
    SB  = scoreboard (reference-model mismatch, any kind)
    CP  = test-plan checkpoints
    SVA = black-box spec assertions (SPEC_*)
    WB  = white-box assertions (WB_*)
A mutant that no oracle detects "survives" and points at a hole in the checks.

Usage:  python3 scripts/mutation_test.py [--jobs 2] [--only M03,M07]
Needs Verilator >= 5.030 on PATH.  Writes sim/logs/mutation_summary.md.
"""
import argparse
import concurrent.futures as cf
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIM = os.path.join(ROOT, "sim")
FIXED = os.path.join(ROOT, "rtl", "frame_aligner_fixed.sv")

# (id, description, original text, mutated text) -- each original text must
# occur exactly once in rtl/frame_aligner_fixed.sv.
MUTANTS = [
    ("M01", "restart branch returns to IDLE (re-introduces DUT-01)",
     "               na_byte_count_inc       = 1'b1;\n               next_state              = FR_HLSB;",
     "               na_byte_count_inc       = 1'b1;\n               next_state              = FR_IDLE;"),
    ("M02", "unqualified sync-loss clear (re-introduces DUT-02)",
     "else if (na_byte_count_inc && (na_byte_counter == NA_LIMIT)) frame_detect <= 1'b0;",
     "else if (na_byte_counter == NA_LIMIT) frame_detect <= 1'b0;"),
    ("M03", "no position reset on reject (re-introduces DUT-03)",
     "               fr_byte_position_rst    = 1'b1;   // FIX DUT-03: no spurious \"1\"",
     "               fr_byte_position_rst    = 1'b0;"),
    ("M04", "legal counter wraps again (re-introduces DUT-04, latent)",
     "else if (legal_frame_counter_inc && (legal_frame_counter != 2'h3))",
     "else if (legal_frame_counter_inc)"),
    ("M05", "not-aligned counter wraps again (re-introduces DUT-05, latent)",
     "else if (na_byte_count_inc && (na_byte_counter != 6'h3F))",
     "else if (na_byte_count_inc)"),
    ("M06", "loss threshold 47 bytes instead of 48",
     "localparam [5:0] NA_LIMIT  = 6'd47;", "localparam [5:0] NA_LIMIT  = 6'd46;"),
    ("M07", "loss threshold 49 bytes instead of 48",
     "localparam [5:0] NA_LIMIT  = 6'd47;", "localparam [5:0] NA_LIMIT  = 6'd48;"),
    ("M08", "frame of 13 bytes (payload end one byte late)",
     "localparam [3:0] LAST_POS  = 4'd10;", "localparam [3:0] LAST_POS  = 4'd11;"),
    ("M09", "frame of 11 bytes (payload end one byte early)",
     "localparam [3:0] LAST_POS  = 4'd10;", "localparam [3:0] LAST_POS  = 4'd9;"),
    ("M10", "alignment after 2 frames instead of 3",
     "else if (legal_frame_counter == 2'h3)                     frame_detect <= 1'b1;",
     "else if (legal_frame_counter == 2'h2)                     frame_detect <= 1'b1;"),
    ("M11", "HEAD_2 MSB constant wrong (0xBB)",
     "localparam [7:0] HEAD2_LSB = 8'h55, HEAD2_MSB = 8'hBA;", "localparam [7:0] HEAD2_LSB = 8'h55, HEAD2_MSB = 8'hBB;"),
    ("M12", "only HEAD_1 LSB recognised",
     "assign header_lsb_valid = (rx_data == HEAD1_LSB) || (rx_data == HEAD2_LSB);",
     "assign header_lsb_valid = (rx_data == HEAD1_LSB);"),
    ("M13", "expected MSBs swapped between the header types",
     "wire [7:0] expected_header_msb = (header_lsb_samp == HEAD1_LSB) ? HEAD1_MSB :\n                                    (header_lsb_samp == HEAD2_LSB) ? HEAD2_MSB : 8'h00;",
     "wire [7:0] expected_header_msb = (header_lsb_samp == HEAD1_LSB) ? HEAD2_MSB :\n                                    (header_lsb_samp == HEAD2_LSB) ? HEAD1_MSB : 8'h00;"),
    ("M14", "alignment never lost (clear removed)",
     "else if (na_byte_count_inc && (na_byte_counter == NA_LIMIT)) frame_detect <= 1'b0;",
     "else if (1'b0) frame_detect <= 1'b0;"),
    ("M15", "not-aligned counter not cleared at the end of a frame",
     "               na_byte_count_rst = 1'b1;\n               next_state        = FR_IDLE;",
     "               na_byte_count_rst = 1'b0;\n               next_state        = FR_IDLE;"),
    ("M16", "consecutive-frame counter not cleared on a hunting byte",
     "               legal_frame_counter_rst = 1'b1;\n               next_state              = FR_IDLE;\n            end\n         end",
     "               legal_frame_counter_rst = 1'b0;\n               next_state              = FR_IDLE;\n            end\n         end"),
    ("M17", "fr_byte_position reset value 1",
     "if (reset)                     fr_byte_position <= 4'h0;", "if (reset)                     fr_byte_position <= 4'h1;"),
    ("M18", "header_lsb_samp never updated after reset",
     "else if (header_lsb_valid) header_lsb_samp <= rx_data;", "else if (1'b0) header_lsb_samp <= rx_data;"),
    ("M19", "FR_HMSB skipped (equivalent on the ports; FSM structure only)",
     "               legal_frame_counter_inc = 1'b1;\n               next_state              = FR_HMSB;",
     "               legal_frame_counter_inc = 1'b1;\n               next_state              = FR_DATA;"),
    ("M20", "restart does not reset the consecutive-frame counter",
     "               // starts a new header candidate instead of being thrown away.\n               legal_frame_counter_rst = 1'b1;",
     "               // starts a new header candidate instead of being thrown away.\n               legal_frame_counter_rst = 1'b0;"),
]

VLT = ["--binary", "--timing", "--assert", "-j", "2", "--top-module", "tb_top",
       "-Wno-fatal", "-Wno-COVERIGN", "-Wno-lint", "-Wno-style"]


def run_mutant(m, workroot):
    mid, desc, old, new = m
    src = open(FIXED).read()
    if src.count(old) != 1:
        return mid, desc, "SETUP-ERROR (pattern not unique)", {}
    wd = os.path.join(workroot, mid)
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(wd)
    rtl = os.path.join(wd, "frame_aligner.sv")
    open(rtl, "w").write(src.replace(old, new))
    b = subprocess.run(["verilator", *VLT, "--Mdir", os.path.join(wd, "obj"), rtl, "-f", "files_tb.f"],
                       cwd=SIM, capture_output=True, text=True)
    exe = os.path.join(wd, "obj", "Vtb_top")
    if b.returncode != 0 or not os.path.exists(exe):
        return mid, desc, "BUILD-ERROR", {}
    hits = {"SB": 0, "CP": 0, "SVA": 0, "WB": 0}
    for test in ("directed", "boundary"):
        out = subprocess.run([exe, f"+TEST={test}", "+SEED=1", "+VERBOSITY=0", f"+DUT_NAME={mid}"],
                             cwd=wd, capture_output=True, text=True).stdout
        r = re.search(r"^FA_RESULT (.*)$", out, re.M)
        if not r:
            hits["SB"] += 1       # crash / hang counts as detected by the bench
            continue
        f = dict(kv.split("=", 1) for kv in r.group(1).split())
        hits["SB"] += int(f["known"]) + int(f["unexplained"]) + int(f["x"]) + int(f.get("reset_err", 0))
        hits["CP"] += int(f["cp_fail"])
        hits["SVA"] += int(f["sva_spec"])
        hits["WB"] += int(f["sva_wb"])
    status = "KILLED" if any(hits.values()) else "SURVIVED"
    return mid, desc, status, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    if shutil.which("verilator") is None:
        sys.exit("verilator not found on PATH")
    todo = [m for m in MUTANTS if not args.only or m[0] in args.only.split(",")]
    workroot = os.path.join(SIM, "build", "mutants")
    os.makedirs(workroot, exist_ok=True)
    with cf.ThreadPoolExecutor(args.jobs) as ex:
        results = list(ex.map(lambda m: run_mutant(m, workroot), todo))
    lines = ["# Mutation testing summary", "",
             "Each mutant is one injected bug in rtl/frame_aligner_fixed.sv, run with +TEST=directed and +TEST=boundary.",
             "Numbers = detections per oracle (SB scoreboard, CP checkpoints, SVA spec assertions, WB white-box assertions).", "",
             "| mutant | injected bug | result | SB | CP | SVA | WB |", "|---|---|---|---|---|---|---|"]
    killed = 0
    for mid, desc, status, h in results:
        killed += status == "KILLED"
        lines.append(f"| {mid} | {desc} | {status} | {h.get('SB', '-')} | {h.get('CP', '-')} | {h.get('SVA', '-')} | {h.get('WB', '-')} |")
    lines += ["", f"**Mutation score: {killed}/{len(results)} killed**", ""]
    os.makedirs(os.path.join(SIM, "logs"), exist_ok=True)
    open(os.path.join(SIM, "logs", "mutation_summary.md"), "w").write("\n".join(lines))
    print("\n".join(lines))
    return 0 if killed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
