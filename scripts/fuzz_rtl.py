#!/usr/bin/env python3
"""Differential fuzzing of the frame aligner RTL against the Python models.

For every generated stream the RTL (simulated with Icarus Verilog through
scripts/harness/tb_trace.sv) is compared with:

  * CausalModel()               -- the specification (exact match required)
  * offline_spec()              -- independent frame parser (don't-cares skipped)
  * CausalModel(all DUT bugs)   -- the delivered design, defects emulated

Expected results (the script exits non-zero otherwise):
  fixed RTL    : 0 mismatches against both specification models
  original RTL : mismatches against the specification, 0 against the
                 bug-emulating model (every deviation is a known defect)

Usage:  python3 scripts/fuzz_rtl.py [--streams 2000] [--seed 1] [--keep DIR]
"""
import argparse
import os
import random
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fa_model import BUGS, HEADER_MSB, CausalModel, offline_spec  # noqa: E402

RTL = {"orig": os.path.join(ROOT, "rtl", "frame_aligner.sv"),
       "fixed": os.path.join(ROOT, "rtl", "frame_aligner_fixed.sv")}
HARNESS = os.path.join(HERE, "harness", "tb_trace.sv")
HDR = [(0xAA, 0xAF), (0x55, 0xBA)]


# ------------------------------------------------------------------ stimulus
def clean(rng):
    while True:
        b = rng.randrange(256)
        if b not in (0xAA, 0x55, 0xAF, 0xBA):
            return b


def frame(rng, last=None):
    lsb, msb = rng.choice(HDR)
    p = [rng.randrange(256) for _ in range(10)]
    if last is not None:
        p[-1] = last
    return [lsb, msb] + p


def gen_stream(rng):
    """One random stream mixing all the corner cases found so far."""
    s = []
    if rng.random() < 0.5:                         # start mid-frame
        s += [rng.randrange(256) for _ in range(rng.randrange(12))]
    lsb_tail = rng.random() < 0.25                  # payloads ending in AA/55
    for _ in range(rng.randrange(4, 14)):
        r = rng.random()
        last = rng.choice((0xAA, 0x55)) if lsb_tail else None
        if r < 0.55:
            s += frame(rng, last)
        elif r < 0.70:                              # gap near the loss threshold
            s += [clean(rng) for _ in range(rng.choice((rng.randrange(60), rng.randrange(44, 50))))]
        elif r < 0.80:                              # stray LSB(s) + frame
            s += [rng.choice((0xAA, 0x55)) for _ in range(rng.randrange(1, 3))] + frame(rng, last)
        elif r < 0.90:                              # broken header
            lsb, msb = rng.choice(HDR)
            s += [lsb, rng.choice((0x00, 0x01, 0xAA, 0x55, 0xAF, 0xBA, msb ^ 1))] + [rng.randrange(256) for _ in range(10)]
        else:                                       # header soup
            s += [rng.choice((0xAA, 0xAF, 0x55, 0xBA, 0x00)) for _ in range(rng.randrange(5, 50))]
    words = [(0, b) for b in s]
    if rng.random() < 0.15 and len(words) > 10:     # asynchronous reset inside
        k = rng.randrange(len(words))
        words[k:k] = [(1, 0)] * rng.randrange(1, 3)
    return words


# ------------------------------------------------------------------ simulation
def simulate(variant, words, workdir):
    vvp = os.path.join(workdir, f"sim_{variant}.vvp")
    if not os.path.exists(vvp):
        subprocess.run(["iverilog", "-g2012", "-o", vvp, HARNESS, RTL[variant]], check=True)
    stim = os.path.join(workdir, f"stim_{variant}.hex")
    resp = os.path.join(workdir, f"resp_{variant}.txt")
    with open(stim, "w") as f:
        f.write("\n".join("%03x" % ((r << 8) | b) for r, b in words) + "\n")
    subprocess.run(["vvp", "-n", vvp, f"+N={len(words)}", f"+IN={stim}", f"+OUT={resp}"],
                   check=True, capture_output=True)
    if not os.path.exists(resp):
        sys.exit(f"simulation produced no response file: {resp}")
    rows = open(resp).read().split()
    assert len(rows) == len(words), (len(rows), len(words))
    return [(int(l[0], 16), int(l[1], 16)) for l in rows]


def mismatches(rtl, ref):
    return [t for t, (a, b) in enumerate(zip(rtl, ref))
            if (b[0] is not None and a[0] != b[0]) or (b[1] is not None and a[1] != b[1])]


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--streams", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keep", help="keep work files in this directory")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    streams = [gen_stream(rng) for _ in range(args.streams)]
    words, bounds = [], []
    for s in streams:                                # one reset between streams
        start = len(words)
        words.append((1, 0))
        words += s
        bounds.append((start, len(words)))

    workdir = args.keep or tempfile.mkdtemp(prefix="fa_fuzz_")
    os.makedirs(workdir, exist_ok=True)
    spec = CausalModel().run(words)
    dutm = CausalModel(BUGS).run(words)
    offl = offline_spec(words)                        # register-table reading
    look = offline_spec(words, lsb_counts=False)      # look-ahead reading

    ok = True
    print(f"{len(streams)} streams, {len(words)} cycles (seed {args.seed})")
    for variant in ("fixed", "orig"):
        rtl = simulate(variant, words, workdir)
        m_spec, m_offl, m_dut = mismatches(rtl, spec), mismatches(rtl, offl), mismatches(rtl, dutm)
        bad_streams = sum(1 for a, b in bounds if any(a <= t < b for t in m_spec[:100000]))
        print(f"  {variant:5s}: vs spec model {len(m_spec):6d} cycles ({bad_streams} streams) | "
              f"vs independent frame parser {len(m_offl):6d} | vs bug-emulating model {len(m_dut):6d}")
        if variant == "fixed":
            ok &= not m_spec and not m_offl
        else:
            ok &= bool(m_spec) and not m_dut
    # The two specification models must agree with each other as well.
    m_models = mismatches([(p, f) for p, f in spec], offl)
    print(f"  spec model vs independent frame parser: {len(m_models)} cycles differ")
    ok &= not m_models
    # Informational: how often the alternative (look-ahead) reading of R5 differs.
    print(f"  (look-ahead reading of R5 differs from the register-table reading on "
          f"{len(mismatches([(p, f) for p, f in spec], look))} cycles; "
          f"the original RTL violates it on {len(mismatches(simulate('orig', words, workdir), look))} cycles)")
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
