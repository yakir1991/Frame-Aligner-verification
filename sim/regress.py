#!/usr/bin/env python3
"""Regression matrix for the frame aligner verification environment.

Each run has an EXPECTED outcome; the regression passes only when every run
behaves as expected:

  fixed RTL + spec model    : must PASS (the corrected design meets the spec)
  original RTL + DUT model  : must PASS (no behaviour beyond the documented
                              defects DUT-01..03 -- regression mode)
  original RTL + spec model : must FAIL, with 0 unexplained mismatches, every
                              port-visible defect (DUT-01..03) detected and the
                              white-box assertions for DUT-04/05 firing
  rtl/frame_aligner.sv      : logically identical to the delivered DUT

Usage:  python3 regress.py [--seeds 3] [--items 400] [--quick]
Writes a Markdown summary to logs/regression_summary.md.
"""
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)


def sh(cmd, log=None):
    """Run a shell command, optionally tee-ing stdout to a log file."""
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if log:
        with open(log, "w") as f:
            f.write(res.stdout)
            f.write(res.stderr)
    return res


def parse_result(text):
    m = re.search(r"^FA_RESULT (.*)$", text, re.M)
    if not m:
        return None
    return dict(kv.split("=", 1) for kv in m.group(1).split())


def sva_counts(text):
    return {m.group(1): int(m.group(2))
            for m in re.finditer(r"^\s+((?:SPEC|WB|TB)_\w+)\s+(\d+)\s+failures", text, re.M)}


def build(dut):
    print(f"[build] DUT={dut}", flush=True)
    res = sh(f"make build DUT={dut}")
    if res.returncode != 0:
        print(res.stdout[-3000:], res.stderr[-3000:])
        sys.exit(f"build failed for DUT={dut}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--items", type=int, default=400)
    ap.add_argument("--quick", action="store_true", help="1 seed, 200 random items")
    args = ap.parse_args()
    if args.quick:
        args.seeds, args.items = 1, 200

    os.makedirs("logs", exist_ok=True)
    rows, ok_all = [], True

    # Static checks
    for name, cmd in [("rtl untouched", "python3 ../scripts/check_rtl_untouched.py ../rtl/frame_aligner.sv"),
                      ("lint fixed RTL", "make -s lint-fixed")]:
        r = sh(cmd)
        ok = r.returncode == 0
        ok_all &= ok
        rows.append((name, "-", "-", "-", "PASS" if ok else "FAIL", "expected PASS", ok))

    build("fixed")
    build("orig")

    runs = []
    for seed in range(1, args.seeds + 1):
        for test in ("directed", "boundary", "random"):
            runs.append(("fixed", "spec", test, seed, "PASS"))
        runs.append(("orig", "dut", "regression", seed, "PASS"))
        runs.append(("orig", "spec", "regression", seed, "FAIL-KNOWN"))

    for dut, model, test, seed, expect in runs:
        log = f"logs/{dut}_{model}_{test}_s{seed}.log"
        t0 = time.time()
        res = sh(f"./build/{dut}/Vtb_top +TEST={test} +MODEL={model} +SEED={seed} "
                 f"+NUM_ITEMS={args.items} +DUT_NAME={dut} +verilator+seed+{seed}", log)
        out = res.stdout
        r = parse_result(out)
        dt = time.time() - t0
        if r is None:
            ok, note = False, "no FA_RESULT line (crash?)"
        elif expect == "PASS":
            ok = r["verdict"] == "PASS"
            note = f"compared={r['compared']} cp={r['cp_pass']}/{int(r['cp_pass']) + int(r['cp_fail'])} cov={r['cov']}%"
        else:
            sva = sva_counts(out)
            bugs = dict(b.split(":") for b in r["bugs"].split(","))
            checks = {
                "verdict FAIL": r["verdict"] == "FAIL",
                "0 unexplained": r["unexplained"] == "0",
                "DUT-01 seen": int(bugs.get("DUT-01", 0)) > 0,
                "DUT-02 seen": int(bugs.get("DUT-02", 0)) > 0,
                "DUT-03 seen": int(bugs.get("DUT-03", 0)) > 0,
                "WB DUT-04 fired": sva.get("WB_DUT04_LEGAL_NO_WRAP", 0) > 0,
                "WB DUT-05 fired": sva.get("WB_DUT05_NA_NO_WRAP", 0) > 0,
            }
            ok = all(checks.values())
            failed = [k for k, v in checks.items() if not v]
            note = (f"known={r['known']} ({r['bugs']}) cp_fail={r['cp_fail']}"
                    + ("" if ok else f"  MISSING: {failed}"))
        ok_all &= ok
        rows.append((f"{dut}/{model}", test, str(seed), f"{dt:.1f}s",
                     r["verdict"] if r else "?", f"expected {expect}; {note}", ok))
        print(f"[{'ok ' if ok else 'BAD'}] {dut:5s} {model:4s} {test:10s} seed={seed} -> "
              f"{r['verdict'] if r else '?'} ({note})", flush=True)

    lines = ["# Regression summary", "",
             "| run | test | seed | time | verdict | expectation / details | ok |",
             "|---|---|---|---|---|---|---|"]
    for row in rows:
        lines.append("| " + " | ".join(row[:6]) + f" | {'yes' if row[6] else '**NO**'} |")
    lines += ["", f"**Overall: {'PASS' if ok_all else 'FAIL'}**", ""]
    with open("logs/regression_summary.md", "w") as f:
        f.write("\n".join(lines))
    print("\n".join(lines))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
