#!/usr/bin/env python3
"""Python reference models of the frame aligner.

Two models, written independently of each other and of the SystemVerilog
reference model (tb/fa_ref_model.sv), used to cross-check it:

* ``CausalModel``   -- byte-by-byte model of the specification rules R1..R7
                        (same rules as the SV model, different language and
                        code).  Optional bug knobs reproduce the delivered
                        RTL: {"DUT-01", "DUT-02", "DUT-03"}.
* ``offline_spec``  -- a non-causal "frame parser" written by an independent
                        reviewer: it first finds every frame in the whole
                        stream, then derives the outputs.  Values that the
                        spec leaves open are returned as None (don't care):
                        fr_byte_position outside a frame, and frame_detect on
                        a 48th header-less byte that could still start a header.

Interpretation switch (the only point where the two spec readings differ):
  lsb_counts=True  (default, register-table / FSM-slide reading, used by the
                   testbench): a header LSB is counted as a header-less byte
                   when it arrives ("na counter increments in FR_IDLE"), so if
                   it is the 48th such byte the counter "reaches 48" and
                   alignment drops, even if the next byte completes the header.
  lsb_counts=False (look-ahead reading of "48 bytes without a valid header"):
                   bytes that turn out to belong to a valid header never count,
                   so a header whose LSB is the 48th byte still keeps alignment.
  Both readings flag the delivered RTL (DUT-02 drops alignment after only 46
  header-less bytes followed by a valid header).

Row convention (both models): row t = registered outputs right after the
clock edge that samples byte t.
"""

HEADER_MSB = {0xAA: 0xAF, 0x55: 0xBA}     # LSB -> MSB (HEAD_1, HEAD_2)
FRAME_LEN, SYNC_FRAMES, LOSS_BYTES = 12, 3, 48
BUGS = ("DUT-01", "DUT-02", "DUT-03")


class CausalModel:
    """Byte-by-byte specification model with optional DUT bug emulation."""

    HUNT, GOT_LSB, IN_FRAME = "HUNT", "GOT_LSB", "IN_FRAME"

    def __init__(self, bugs=()):
        self.bugs = set(bugs)
        self.reset()

    def reset(self):
        self.phase, self.cand, self.idx = self.HUNT, None, 0
        self.consec, self.hdrless, self.pending = 0, 0, False
        self.pos, self.fd = 0, 0

    def _count(self):
        # Spec counter saturates; the RTL counter (DUT-02 emulation) wraps at 64.
        self.hdrless = (self.hdrless + 1) % 64 if "DUT-02" in self.bugs else min(self.hdrless + 1, 10**6)

    def step(self, b):
        """Consume one byte; returns (pos, fd) = the registered outputs.

        State: phase (HUNT / GOT_LSB / IN_FRAME), cand = the header LSB waiting
        for its MSB, idx = index of the current byte inside the frame,
        consec = consecutive valid frames, hdrless = header-less bytes counted
        since the last frame, pending = frame_detect rises on the next byte.
        """
        na_before, counted = self.hdrless, False     # counter before this byte
        set_now, self.pending = self.pending, False   # R4: rise decided last byte
        fd_next = self.fd
        if self.phase == self.IN_FRAME:                       # R3 payload
            self.idx += 1
            self.pos = self.idx
            if self.idx == FRAME_LEN - 1:
                self.phase = self.HUNT
                if "DUT-02" in self.bugs:
                    self.hdrless = 0
        elif self.phase == self.HUNT:                         # R2 hunting
            self.pos, counted = 0, True
            if b in HEADER_MSB:
                self.phase, self.cand = self.GOT_LSB, b
            else:
                self.consec = 0
            self._count()
        else:                                                 # R1 check MSB
            if b == HEADER_MSB[self.cand]:
                self.phase, self.idx, self.pos = self.IN_FRAME, 1, 1
                self.consec += 1
                if "DUT-02" not in self.bugs:
                    self.hdrless = 0
                if self.consec >= SYNC_FRAMES:
                    self.pending = True                       # R4: rise next byte
            else:
                self.consec, counted = 0, True
                if b in HEADER_MSB and "DUT-01" not in self.bugs:
                    self.cand, self.pos = b, 0                # R2 restart
                else:
                    self.phase = self.HUNT
                    self.pos = 1 if "DUT-03" in self.bugs else 0
                self._count()
        # R5 loss of alignment.  Spec: only a byte that is itself counted can
        # clear frame_detect, on the 48th count.  DUT-02 emulation: the RTL
        # clears whenever the registered counter already shows 47, whatever
        # the current byte is (even the MSB that completes a valid header).
        if "DUT-02" in self.bugs:
            if na_before == LOSS_BYTES - 1:
                fd_next = 0
        elif counted and self.hdrless >= LOSS_BYTES:
            fd_next = 0
        if set_now:                                           # set has priority
            fd_next = 1
        self.fd = fd_next
        return self.pos, self.fd

    def run(self, words):
        """words: iterable of (reset, byte).  Returns list of (pos, fd) rows."""
        rows = []
        for rst, b in words:
            if rst:
                self.reset()
                rows.append((0, 0))
            else:
                rows.append(self.step(b))
        return rows


def _offline_segment(s, lsb_counts=True):
    """Frame parser for one reset-free segment.  Returns (fd, pos) lists.

    Works on the whole segment at once (non-causal), in three passes:
      1. find every frame: scan byte by byte; a header (LSB + matching MSB)
         claims the next 12 bytes, anything else advances by one byte;
      2. mark the bytes covered by a frame and their positions 0..11, and find
         where frame_detect rises (payload byte 0 of the 3rd back-to-back frame);
      3. walk the bytes, counting header-less bytes, to find where it falls.
    """
    n = len(s)
    frames, i = [], 0
    while i < n:                                  # every frame in the stream
        if i + 1 < n and HEADER_MSB.get(s[i]) == s[i + 1]:
            frames.append(i)
            i += FRAME_LEN
        else:
            i += 1
    aligned, pos = [False] * n, [None] * n
    for p in frames:
        for k in range(FRAME_LEN):
            if p + k < n:
                aligned[p + k], pos[p + k] = True, k
    rise, run, prev = set(), 0, None
    for p in frames:                              # third consecutive frame
        run = run + 1 if prev is not None and p == prev + FRAME_LEN else 1
        prev = p
        if run >= SYNC_FRAMES and p + 2 < n:
            rise.add(p + 2)
    starts = set(frames)
    fd, cur, na = [None] * n, 0, 0
    for t in range(n):
        dont_care = False
        if t in starts and lsb_counts and na + 1 >= LOSS_BYTES:
            cur = 0                               # the LSB is the 48th counted byte
            na = 0
        else:
            na = 0 if aligned[t] else na + 1
            if t in rise:
                cur = 1
            elif na == LOSS_BYTES:
                cur = 0
                # A 48th byte that could still start a header: with look-ahead
                # its row is unknowable causally -> don't care.
                dont_care = (not lsb_counts) and s[t] in HEADER_MSB
        fd[t] = None if dont_care else cur
    return fd, pos


def offline_spec(words, lsb_counts=True):
    """words: list of (reset, byte).  Returns list of (pos, fd), None = don't care."""
    out, seg = [], []

    def flush():
        if seg:
            fd, pos = _offline_segment(seg, lsb_counts)
            out.extend(zip(pos, fd))

    for rst, b in words:
        if rst:
            flush()
            seg.clear()
            out.append((0, 0))
        else:
            seg.append(b)
    flush()
    return out
