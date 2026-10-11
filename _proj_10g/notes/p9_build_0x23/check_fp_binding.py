#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""D 项口径核对: 矩阵指纹里的 257 件**逐件**与盘上现读 / 与 `git show HEAD:<path>` 对比。

判据:
  ① 指纹里的 SHA256 == 盘上现读 (指纹没飘);
  ② 盘上现读 == HEAD 版本 (被指纹绑定的文件集里, 谁 ≠ HEAD ⇒ 逐个点名);
  ③ edge: 未跟踪文件 (HEAD 里没有) 单独列 (= 指纹集里的"新增件")。
用法: python check_fp_binding.py <fingerprint_before.txt>
"""
import hashlib
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
fp = sys.argv[1]
rx = re.compile(r"^SHA256 ([0-9a-f]{64})  (\S+)  (\d+)  (\d+)$")

n = ok_disk = tracked = same_head = untracked = 0
diff_disk, diff_head = [], []
for line in open(fp, encoding="utf-8", errors="replace"):
    m = rx.match(line.strip())
    if not m:
        continue
    h_fp, rel, size, mtime = m.group(1), m.group(2), int(m.group(3)), m.group(4)
    n += 1
    p = os.path.join(REPO, rel.replace("/", os.sep))
    if not os.path.exists(p):
        diff_disk.append((rel, "MISSING-ON-DISK"))
        continue
    hm = hashlib.sha256(open(p, "rb").read()).hexdigest()
    if hm == h_fp:
        ok_disk += 1
    else:
        diff_disk.append((rel, "%s != 指纹 %s" % (hm[:16], h_fp[:16])))
    # 与 HEAD 版本比 (tracked 才有)。
    #   ⚠️ **必须走 git 的规范化比较** (`git diff --quiet HEAD -- <p>`), ⛔ 不能拿
    #      `git show HEAD:<p>` 的原始字节与盘上原始字节直接比哈希 —— 本仓
    #      `core.autocrlf=true` (实测 `git ls-files --eol` = `i/lf w/crlf`) ⇒ 原始字节
    #      比对会给**整族假阳性** (2026-10-12 实测: 首版本脚本报 40 件"≠HEAD", 全属此坑;
    #      git 自己的 `MODIFIED vs HEAD` 面只列 1 件 = wrapper_p4.v)。
    r = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", rel], cwd=REPO,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode == 128:            # 不认识的路径 / 非 tracked
        untracked += 1
        continue
    tracked += 1
    if r.returncode == 0:
        same_head += 1
    else:
        diff_head.append(rel)

print("指纹件数               = %d" % n)
print("① 指纹 == 盘上现读     : %d / %d  (不一致 %d)" % (ok_disk, n, len(diff_disk)))
for rel, why in diff_disk:
    print("   FAIL %-70s %s" % (rel, why))
print("② HEAD 里可查 (tracked) = %d ; 逐字 == HEAD : %d ; **≠ HEAD : %d**"
      % (tracked, same_head, len(diff_head)))
for rel in diff_head:
    print("   ≠HEAD %s" % rel)
print("③ 未跟踪 (HEAD 无此件) = %d" % untracked)
