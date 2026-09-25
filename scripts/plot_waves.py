#!/usr/bin/env python3
"""Render timing diagrams of each DUT defect from real RTL simulations.

For every scenario a minimal byte stream is simulated on the ORIGINAL and the
FIXED RTL (Icarus Verilog, scripts/harness/tb_trace.sv).  The figure shows,
per clock, the byte consumed and the registered response of each design, so
that the defect and its repair can be seen side by side.  The expected
(specification) values come from scripts/fa_model.py.

Output: docs/images/wave_<name>.png

Usage:  python3 scripts/plot_waves.py
"""
import os
import subprocess
import sys
import tempfile
import textwrap

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fa_model import CausalModel  # noqa: E402

OUT = os.path.join(ROOT, "docs", "images")
RTL = {"orig": os.path.join(ROOT, "rtl", "frame_aligner.sv"),
       "fixed": os.path.join(ROOT, "rtl", "frame_aligner_fixed.sv")}
HARNESS = os.path.join(HERE, "harness", "tb_trace.sv")
STATE = {0: "IDLE", 1: "HLSB", 2: "HMSB", 3: "DATA"}

# Colour palette (colour-blind safe, readable on white and on slides)
C_BG, C_GRID, C_TXT = "#ffffff", "#e3e6ea", "#1f2933"
C_ORIG, C_FIX, C_SPEC, C_HI = "#c2410c", "#1d4ed8", "#0f766e", "#fde68a"


def simulate(variant, words, work):
    vvp = os.path.join(work, f"{variant}.vvp")
    if not os.path.exists(vvp):
        subprocess.run(["iverilog", "-g2012", "-o", vvp, HARNESS, RTL[variant]], check=True)
    stim, resp = os.path.join(work, "stim.hex"), os.path.join(work, "resp.txt")
    with open(stim, "w") as f:
        f.write("\n".join("%03x" % ((r << 8) | b) for r, b in words) + "\n")
    subprocess.run(["vvp", "-n", vvp, f"+N={len(words)}", f"+IN={stim}", f"+OUT={resp}"],
                   check=True, capture_output=True)
    rows = []
    for l in open(resp).read().split():
        rows.append(dict(pos=int(l[0], 16), fd=int(l[1], 16), st=int(l[2], 16),
                         legal=int(l[3], 16), na=int(l[4:6], 16)))
    return rows


FS = 1.0   # font scale (larger for the slide variants)


def bus(ax, y, vals, x0, color, fmt=str, hl=None, hl_color=None, h=0.34, merge=True):
    """Draw a bus lane: one box per cycle with its value; merges equal values.
    hl(k) -> True paints the segment containing cycle k with hl_color."""
    hl_color = hl_color or C_HI
    n = len(vals)
    i = 0
    while i < n:
        j = i
        while merge and j + 1 < n and vals[j + 1] == vals[i]:
            j += 1
        xa, xb = x0 + i, x0 + j + 1
        ax.fill([xa + .08, xb - .08, xb, xb - .08, xa + .08, xa], [y + h, y + h, y, y - h, y - h, y],
                facecolor=(hl_color if hl and any(hl(k) for k in range(i, j + 1)) else "white"),
                edgecolor=color, lw=1.2)
        ax.text((xa + xb) / 2, y, fmt(vals[i]), ha="center", va="center", fontsize=8.5 * FS, color=C_TXT,
                family="DejaVu Sans Mono")
        i = j + 1


def bit(ax, y, vals, x0, color, h=0.34):
    xs, ys = [], []
    for i, v in enumerate(vals):
        xs += [x0 + i, x0 + i + 1]
        ys += [y - h + 2 * h * v] * 2
    ax.plot(xs, ys, color=color, lw=2)


def figure(name, title, words, window, notes, show_counters=False, compact=False, cwin=None):
    """compact=True: slide version (no state/spec lanes, larger text, no title,
    optional shorter window cwin)."""
    global FS
    FS = 1.6 if compact else 1.0
    if compact and cwin:
        window = cwin
    work = tempfile.mkdtemp(prefix="fa_wave_")
    sim = {v: simulate(v, words, work) for v in ("orig", "fixed")}
    spec = CausalModel().run(words)
    a, b = window[0], min(window[1], len(words))
    rx = [w[1] for w in words[a:b]]
    lanes = [("rx_data (byte consumed)", "rx")]
    if not compact:
        lanes += [("ORIGINAL  state (after byte)", "orig.st")]
    lanes += [("ORIGINAL  fr_byte_position", "orig.pos"), ("ORIGINAL  frame_detect", "orig.fd")]
    if show_counters:
        lanes += [("ORIGINAL  legal_frame_counter", "orig.legal"), ("ORIGINAL  na_byte_counter", "orig.na")]
    lanes += [("FIXED  fr_byte_position", "fixed.pos"), ("FIXED  frame_detect", "fixed.fd")]
    if show_counters and not compact:
        lanes += [("FIXED  legal_frame_counter", "fixed.legal"), ("FIXED  na_byte_counter", "fixed.na")]
    if not compact:
        lanes += [("SPEC  fr_byte_position", "spec.pos"), ("SPEC  frame_detect", "spec.fd")]

    n = b - a
    fig_h = 0.62 * len(lanes) + 1.6
    fig, ax = plt.subplots(figsize=(max(10, (0.62 if compact else 0.42) * n + (4.6 if compact else 3.2)),
                                    fig_h * (1.25 if compact else 1.0)), dpi=150)
    fig.patch.set_facecolor(C_BG)
    ax.set_facecolor(C_BG)
    for k in range(n + 1):
        ax.axvline(k, color=C_GRID, lw=0.6, zorder=0)
    for li, (label, key) in enumerate(lanes):
        y = len(lanes) - li
        ax.text(-0.3, y, label, ha="right", va="center", fontsize=9 * FS, color=C_TXT)
        if key == "rx":
            bus(ax, y, rx, 0, "#475569", lambda v: f"{v:02X}",
                hl=lambda k: rx[k] in (0xAA, 0x55, 0xAF, 0xBA), hl_color="#dbeafe", merge=False)
            continue
        src, field = key.split(".")
        if src == "spec":
            vals = [spec[t][0] if field == "pos" else spec[t][1] for t in range(a, b)]
            ref = vals
        else:
            vals = [sim[src][t][field] for t in range(a, b)]
            ref = [spec[t][0] if field == "pos" else spec[t][1] for t in range(a, b)] if field in ("pos", "fd") else None
        color = {"orig": C_ORIG, "fixed": C_FIX, "spec": C_SPEC}[src]
        if field == "fd":
            bit(ax, y, vals, 0, color)
            if src == "orig":
                for k, (v, r) in enumerate(zip(vals, ref)):
                    if v != r:
                        ax.add_patch(plt.Rectangle((k, y - .45), 1, .9, color=C_HI, zorder=0))
        elif field == "st":
            bus(ax, y, vals, 0, color, lambda v: STATE[v])
        else:
            hl = (lambda k, vals=vals, ref=ref: ref is not None and src == "orig" and vals[k] != ref[k])
            bus(ax, y, vals, 0, color, str, hl=hl)
    for k in range(0, n, 5):
        ax.text(k + .5, 0.25, str(a + k), ha="center", va="center", fontsize=7 * FS, color="#64748b")
    ax.text(n / 2, 0.25 - 0.45, "byte index in stream", ha="center", fontsize=8 * FS, color="#64748b")
    ax.set_xlim(-0.2, n + 0.2)
    ax.set_ylim(-0.6, len(lanes) + 0.9)
    ax.axis("off")
    width_in = fig.get_size_inches()[0]
    if not compact:
        ax.set_title(textwrap.fill(title, int(width_in * 7.5)), loc="left", fontsize=11.5, color=C_TXT,
                     pad=10, fontweight="bold")
        fig.text(0.01, 0.01, textwrap.fill(notes + "  Yellow = original RTL differs from the specification.",
                                           int(width_in * 13)), fontsize=8.5, color="#334155")
    fig.tight_layout(rect=(0.0, 0.0 if compact else 0.05, 1, 1))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{'slide' if compact else 'wave'}_{name}.png")
    fig.savefig(path, facecolor=C_BG)
    plt.close(fig)
    print("wrote", os.path.relpath(path, ROOT))


def frame(h, pay=None, last=None):
    p = list(pay or [0x11, 0x22, 0x33, 0x44, 0x66, 0x77, 0x88, 0x99, 0x10, 0x20])
    if last is not None:
        p[-1] = last
    return ([0xAA, 0xAF] if h == 1 else [0x55, 0xBA]) + p


def W(bs):
    return [(0, b) for b in bs]


def main():
    for compact in (False, True):
        scenarios(compact)


def scenarios(compact):
    def figure_(*a, **k):
        figure(*a, compact=compact, **k)

    sync = frame(1) + frame(2) + frame(1)
    # Normal operation: alignment after three frames (spec waveform 1)
    figure_("normal_sync", "Normal operation: alignment one byte after the 3rd header (R4)",
           W([0x00, 0x00] + sync + frame(2)[:4]), (0, 42),
           "Both designs agree with the specification here.", cwin=(12, 38))
    # DUT-01: stray LSB before a header
    figure_("dut01_restart", "DUT-01: header LSB lost after a rejected MSB  (55 | AA AF ...)",
           W([0x00, 0x55] + frame(1) + frame(2)[:6]), (0, 20),
           "The 0xAA that rejects the pending 0x55 is itself a header LSB; the original FSM drops it and misses the frame.",
           cwin=(0, 19))
    # DUT-01 at system level: payloads ending in 0x55, start-up mid-stream
    s = [0x11, 0x22, 0x55] + sum([frame(1 + (i % 2), last=0x55) for i in range(4)], [])
    figure_("dut01_midstream", "DUT-01 with legal traffic: payloads ending in 0x55, start-up mid-stream -> never aligns",
           W(s), (0, 51),
           "Pay_9 = 0x55 is taken as a header LSB; the real LSB rejects it and is thrown away, for every frame.",
           cwin=(10, 38))
    # DUT-02: 46 header-less bytes then a valid header
    s = [0x00] + sync + [0x00] * 46 + frame(1)
    figure_("dut02_sync_drop", "DUT-02: alignment dropped on the byte that completes a VALID header (46 header-less bytes)",
           W(s), (78, 100),
           "The header LSB is counted as non-aligned (47) and the clear is not qualified, so the valid MSB clears frame_detect.",
           show_counters=True, cwin=(79, 95))
    # DUT-03: rejected header reports position 1
    figure_("dut03_pos", "DUT-03: fr_byte_position = 1 after a REJECTED header (AA 01)",
           W([0x00, 0x00, 0xAA, 0x01, 0x02, 0x03, 0x55, 0x00, 0x04, 0x05, 0x06]), (0, 11),
           "No frame exists, yet the original design reports 'header MSB' (position 1) for one cycle.")
    # DUT-04/05: counters wrap (not visible on the ports)
    s = [0x00] + sum([frame(1 + (i % 2)) for i in range(5)], []) + [0x00] * 30
    figure_("dut04_counters", "DUT-04: legal_frame_counter wraps 3 -> 0 on the 4th consecutive frame (latent)",
           W(s), (22, 52),
           "Invisible on the ports today (frame_detect is sticky) -- found by the white-box assertion WB_DUT04_LEGAL_NO_WRAP.",
           show_counters=True, cwin=(26, 50))
    # DUT-07: slipped frames keep alignment forever
    s = [0x00] + sync + sum([[0x00] + frame(1 + (i % 2)) for i in range(4)], [])
    figure_("dut07_slip", "DUT-07 (architecture): 13-byte frames after alignment -- frame_detect never drops",
           W(s), (34, 80),
           "Each header arrives one byte late; the hunting aligner re-locks every time instead of counting 4 bad frames.",
           cwin=(34, 62))


if __name__ == "__main__":
    main()
