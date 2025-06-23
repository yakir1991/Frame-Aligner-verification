import os
import sys
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from frame_aligner_model import FrameAlignerModel, create_frame


def run_sequence(seq, reset=False):
    fa = FrameAlignerModel()
    outputs = []
    for byte in seq:
        fr_pos, detect = fa.step(byte, reset=reset)
        outputs.append((fr_pos, detect))
    return outputs


def test_frame_detect_after_three_valid_frames():
    fa = FrameAlignerModel()
    seq = create_frame('HEAD_1') + create_frame('HEAD_2') + create_frame('HEAD_1')
    detect_values = []
    for b in seq:
        _, d = fa.step(b)
        detect_values.append(d)
    assert detect_values[-1] == 1


def test_frame_detect_resets_after_invalid_sequence():
    fa = FrameAlignerModel()
    seq = create_frame('HEAD_1') + create_frame('HEAD_1') + create_frame('HEAD_1')
    for b in seq:
        fa.step(b)
    assert fa.frame_detect == 1
    for _ in range(48):
        fa.step(0x00)
    assert fa.frame_detect == 0


def test_fr_byte_position_counts_data_bytes():
    fa = FrameAlignerModel()
    frame = create_frame('HEAD_1')
    positions = []
    for b in frame:
        pos, _ = fa.step(b)
        positions.append(pos)
    # LSB resets counter
    assert positions[0] == 0
    # MSB increments
    assert positions[1] == 1
    # After last payload byte counter is 11
    assert positions[-1] == 11
    # Next byte causes reset
    pos, _ = fa.step(0x00)
    assert pos == 0
