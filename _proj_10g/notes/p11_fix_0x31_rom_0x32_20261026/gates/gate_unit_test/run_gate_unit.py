#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit-test the two Tcl gates extracted verbatim from board/build_p7b_ku5p.tcl.

No Vivado.  The real gate blocks are extracted by marker and sourced under
stubs, so this tests the actual Tcl syntax/logic, not a copy.  It does NOT
validate the Vivado pin regexes against a real DCP (that was done by
p11_sta_tcb_probe.tcl on the 0x32 routed DCP).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
BUILD = REPO / "board" / "build_p7b_ku5p.tcl"
OUT = HERE / "RESULTS.txt"


def extract(start, stop):
    lines = BUILD.read_text(encoding="utf-8", errors="replace").splitlines()
    out, on = [], False
    for ln in lines:
        if re.match(start, ln):
            on = True
        if on and re.match(stop, ln):
            break
        if on:
            out.append(ln)
    if not out:
        raise SystemExit("extract failed: %s" % start)
    return "\n".join(out) + "\n"


def find_tclsh():
    for name in ("tclsh", "tclsh86", "tclsh9.0"):
        p = shutil.which(name)
        if p:
            return p
    for p in (r"C:\msys64\mingw64\bin\tclsh.exe",
              r"C:\Program Files\Git\mingw64\bin\tclsh.exe",
              r"C:\msys64\usr\bin\tclsh.exe"):
        if Path(p).exists():
            return p
    raise SystemExit("tclsh not found; set TCLSH")


def run(tclsh, script, env, cwd):
    e = os.environ.copy()
    e.update(env)
    p = subprocess.run([tclsh, str(script)], cwd=str(cwd), env=e,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=60)
    return p.returncode, p.stdout + p.stderr


def check(name, rc, out, want_rc, needles, results):
    ok = (rc == want_rc) and all(n in out for n in needles)
    results.append((name, ok, rc, want_rc, needles, out))
    print("%-28s %s rc=%s want=%s" % (name, "OK" if ok else "FAIL", rc, want_rc))
    for n in needles:
        if n not in out:
            print("   MISSING: %s" % n)
    return ok


def main():
    tclsh = find_tclsh()
    tmp = Path(tempfile.mkdtemp(prefix="p11_gate_unit_"))
    rom_block = tmp / "rom_block.tcl"
    tcb_block = tmp / "tcb_block.tcl"
    rom_block.write_text(extract(r'^sec "P7B_HLS_ROM_LOG_GATE"',
                                 r'^# ---- P11 P2-甲'), encoding="utf-8")
    tcb_block.write_text(extract(r'^sec "P11_STA_TCB_GATE"',
                                 r'^puts "P7B_BIT = '), encoding="utf-8")
    rom_test = HERE / "rom_gate_test.tcl"
    tcb_test = HERE / "tcb_gate_test.tcl"
    results = []
    ok_all = True

    # ---- ROM gate ----
    good = tmp / "good.log"
    good.write_text(
        "INFO: [Synth 8-3876] $readmem data file './a.dat' is read successfully\n"
        "INFO: [Synth 8-3876] $readmem data file './b.dat' is read successfully\n"
        "INFO: [Synth 8-3876] $readmem data file './c.dat' is read successfully\n",
        encoding="utf-8")
    uninit = tmp / "uninit.log"
    uninit.write_text(
        "CRITICAL WARNING: [Synth 8-4445] could not open $readmem data file './a.dat'\n"
        "INFO: [Synth 8-3876] $readmem data file './b.dat' is read successfully\n",
        encoding="utf-8")
    missing = tmp / "missing.log"
    missing.write_text(
        "INFO: [Synth 8-3876] $readmem data file './a.dat' is read successfully\n"
        "INFO: [Synth 8-3876] $readmem data file './b.dat' is read successfully\n",
        encoding="utf-8")
    nolog = tmp / "does_not_exist.log"

    for name, log, dat, want_rc, needles in [
        ("rom_good", good, "3", 0, ["P7B_HLS_ROM_LOG_HITS = 0", "HARNESS_END"]),
        ("rom_uninit", uninit, "3", 1, ["P7B_VERDICT = HLS_ROM_UNINIT"]),
        ("rom_read_missing", missing, "3", 1, ["P7B_VERDICT = HLS_ROM_READ_MISSING"]),
        ("rom_log_missing", nolog, "3", 1, ["P7B_VERDICT = HLS_ROM_LOG_MISSING"]),
    ]:
        rc, out = run(tclsh, rom_test, {
            "BLOCK_FILE": str(rom_block),
            "SYNTH_LOG": str(log),
            "HLS_DAT_COPIED": dat,
        }, tmp)
        ok_all &= check(name, rc, out, want_rc, needles, results)

    # ---- TCB gate ----
    bit = tmp / "vivado_prj" / "p7b_ku5p_prj.runs" / "impl_1" / "wrapper_p4.bit"
    bit.parent.mkdir(parents=True, exist_ok=True)

    def tcb_case(name, cfg, missing, force, want_rc, needles, expect_rename):
        bit.write_bytes(b"dummy")
        env = {"BLOCK_FILE": str(tcb_block), "P11_CFG": cfg,
               "ROOT_DIR": str(tmp)}
        if missing:
            env["MISSING_SUBSTR"] = missing
        if force:
            env["FORCE_SLACK"] = force
        rc, out = run(tclsh, tcb_test, env, tmp)
        ok = check(name, rc, out, want_rc, needles, results)
        renamed = (bit.parent / "wrapper_p4.bit.STA_FAMILY_FAIL").exists()
        if renamed != expect_rename:
            ok = False
            print("   RENAME mismatch: got %s want %s" % (renamed, expect_rename))
        if renamed:
            (bit.parent / "wrapper_p4.bit.STA_FAMILY_FAIL").unlink()
        return ok

    ok_all &= tcb_case("tcb_pass", "c4", None, None, 0,
                       ["P11_STA_TCB_MIN = 0.019", "P11_STA_TCB_GATE = PASS",
                        "HARNESS_END"], False)
    ok_all &= tcb_case("tcb_missing_pin", "c4", "u_tcp_tx2/u_fifo_a/rptr", None, 1,
                       ["P11_STA_TCB_GATE = FAIL (family pins missing)"], True)
    ok_all &= tcb_case("tcb_negative_slack", "c4", None, "-0.01", 1,
                       ["P11_STA_TCB_GATE = FAIL (min=-0.01 < 0.0)"], True)
    ok_all &= tcb_case("tcb_non_c4_skip", "c3", None, None, 0,
                       ["P11_STA_TCB_GATE = SKIP (non-c4)", "HARNESS_END"], False)

    with OUT.open("w", encoding="utf-8") as f:
        f.write("P11 GATE UNIT TEST (real Tcl blocks extracted from board/build_p7b_ku5p.tcl)\n")
        f.write("tclsh = %s\n" % tclsh)
        f.write("build = %s\n\n" % BUILD)
        for name, ok, rc, want_rc, needles, out in results:
            f.write("=== %s : %s (rc=%s want=%s)\n" % (name, "OK" if ok else "FAIL", rc, want_rc))
            for n in needles:
                f.write("  needle %-45s %s\n" % (n, "found" if n in out else "MISSING"))
            f.write(out)
            f.write("\n")
        f.write("GATE_UNIT_TEST = %s\n" % ("PASS" if ok_all else "FAIL"))
    print("GATE_UNIT_TEST = %s" % ("PASS" if ok_all else "FAIL"))
    print("RESULTS = %s" % OUT)
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
