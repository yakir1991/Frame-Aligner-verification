#!/usr/bin/env python3
"""Prove that rtl/frame_aligner.sv is logically identical to the delivered DUT.

The verification team only added comments to the original RTL.  This script
removes all comments and whitespace from the file and compares a SHA-256 hash
of the remaining token stream with the hash of the delivered dut.sv
(git commit 31b1c5e).  Any change to the logic -- even a single character --
changes the hash and makes the check fail.

Usage:  python3 scripts/check_rtl_untouched.py [path/to/frame_aligner.sv]
"""
import hashlib
import re
import sys

# SHA-256 of the normalised token stream of the delivered dut.sv.
GOLDEN_SHA256 = "45214c83b755f7390de2b6f25863db98d27478430b081e2f4101bfb9c5601206"


def normalise(text: str) -> str:
    """Strip // and /* */ comments, then collapse all whitespace."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return " ".join(text.split())


def digest(text: str) -> str:
    return hashlib.sha256(normalise(text).encode()).hexdigest()


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "rtl/frame_aligner.sv"
    got = digest(open(path, encoding="utf-8").read())
    if got == GOLDEN_SHA256:
        print(f"PASS: {path} is logically identical to the delivered DUT ({got[:16]}...)")
        return 0
    print(f"FAIL: {path} differs from the delivered DUT\n  expected {GOLDEN_SHA256}\n  got      {got}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
