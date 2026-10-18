#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""replay_check.py — 0x2D backstop-2 读侧重放证据.

做法:
  1. 从 `apply_readside_bid1c.py` 导入 **EDITS_2D**（已 extend 的最后 70 笔 = 本轮增量）；
     与生成的 `BACKSTOP2_EDITS.frag` 逐项比对（证明插入的就是生成的那份）。
  2. 把这份增量应用到 **0x88/0x2D 基线副本**（= 本目录 baseline_0x88_0x2D/，
     即本轮开工前的磁盘状态），按 apply 引擎同一套行尾规则（old/new 的 `\n`
     换成文件自身的 CRLF/LF）。
  3. 把重放结果与**现磁盘**逐文件比较（sha256 + 字节数 + `cmp` 语义）。
退出码: 0 = 全部逐字节相同 / 1 = 有差异。
"""
import hashlib
import importlib.util
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE = os.path.join(HERE, "baseline_0x88_0x2D")
APPLY = os.path.join(REPO, "_proj_10g", "notes", "p7b_readside_bid1c_20261011",
                     "apply_readside_bid1c.py")


def load_module(path):
    spec = importlib.util.spec_from_file_location("apply_readside_bid1c_mod", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    mod = load_module(APPLY)
    frag_path = os.path.join(HERE, "BACKSTOP2_EDITS.frag")
    frag = []
    ns = {}
    exec(compile("FRAG=[\n" + io.open(frag_path, encoding="utf-8").read() + "\n]\n",
                 "<frag>", "exec"), ns)
    frag = ns["FRAG"]
    tail = mod.EDITS_2D[-len(frag):]
    if tail != frag:
        print("FAIL: EDITS_2D 尾部 != 生成的 frag (插入块与生成器不一致)")
        return 1
    print("OK  EDITS_2D 尾部 == BACKSTOP2_EDITS.frag (%d 笔)" % len(frag))

    # 只在**基线副本**上应用（仓内文件一个字节都不动）
    out = {}
    for rel in sorted(set(e[0] for e in frag)):
        p = os.path.join(BASE, rel.replace("/", os.sep))
        b = io.open(p, "rb").read()
        nl = "\r\n" if b"\r\n" in b else "\n"
        txt = b.decode("utf-8")
        for r2, old, new, n in tail:
            if r2 != rel:
                continue
            old2 = old.replace("\n", nl)
            new2 = new.replace("\n", nl)
            k = txt.count(old2)
            if k != n:
                print("FAIL %-64s hits=%d/%d  %r" % (rel, k, n, old2.split(nl)[0][:60]))
                return 1
            txt = txt.replace(old2, new2)
        out[rel] = txt.encode("utf-8")

    bad = 0
    for rel in sorted(out):
        disk = io.open(os.path.join(REPO, rel.replace("/", os.sep)), "rb").read()
        same = out[rel] == disk
        print("%s %-64s replay=%d B sha=%s / disk=%d B sha=%s"
              % ("OK  " if same else "FAIL", rel, len(out[rel]), sha(out[rel])[:16],
                 len(disk), sha(disk)[:16]))
        if not same:
            bad += 1
    print("REPLAY %s (%d 文件; %d 差异)" % ("BYTE-IDENTICAL" if bad == 0 else "MISMATCH",
                                            len(out), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
