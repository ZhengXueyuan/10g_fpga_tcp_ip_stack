#!/usr/bin/env python3
# RV2: B3 独立重解析 —— 只读 board/PROBE_STDOUT.txt, 自写解析器复算四判据。
import os, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                 "p9_mdio_board_20261015", "board", "PROBE_STDOUT.txt")

TXL = re.compile(r"^TX (\S+) phyad=(\d+) regad=(\d+) rd=([0-9A-Fa-f]+) done=(\d+) busy=(\d+) rstn=(\d+) mdio=(\d+) ssl=(\d+) pbad=(\d+)$")
ARML = re.compile(r"^ARM_J_(\w+)(.*)$")

def main():
    txt = open(P, encoding="utf-8", errors="replace").read()
    lines = txt.splitlines()
    tx = []
    for i, l in enumerate(lines, 1):
        m = TXL.match(l)
        if m:
            tx.append(dict(line=i, tag=m.group(1), phyad=int(m.group(2)), regad=int(m.group(3)),
                           rd=m.group(4).upper(), done=int(m.group(5)), busy=int(m.group(6)),
                           rstn=int(m.group(7)), mdio=int(m.group(8)), ssl=int(m.group(9)),
                           pbad=int(m.group(10))))
    print("== 复算 0: TX 记录总数 = %d" % len(tx))
    # 1) STATUS_WIDTH
    sw = [l for l in lines if l.startswith("STATUS_WIDTH=")]
    print("== 复算 1: %s" % sw)
    # 2) J-A: 32 地址 × {r2,r3}
    ja = [t for t in tx if t["tag"].startswith("A_r")]
    addrs_r2 = {t["phyad"]: t["rd"] for t in ja if t["regad"] == 2}
    addrs_r3 = {t["phyad"]: t["rd"] for t in ja if t["regad"] == 3}
    print("== 复算 2 (J-A): A_r2 记录 %d 条 / A_r3 记录 %d 条; 地址集(2) = %s" % (
        len(addrs_r2), len(addrs_r3), sorted(addrs_r2)))
    answered = [a for a, v in addrs_r2.items() if v != "FFFF"]
    print("   r2 非 FFFF 的地址 = %s" % sorted(answered))
    print("   addr0: r2=%s r3=%s ; addr1: r2=%s r3=%s" % (
        addrs_r2.get(0), addrs_r3.get(0), addrs_r2.get(1), addrs_r3.get(1)))
    bad = [(a, addrs_r2.get(a), addrs_r3.get(a)) for a in range(2, 32)
           if addrs_r2.get(a) != "FFFF" or addrs_r3.get(a) != "FFFF"]
    print("   addr2..31 任一非 FFFF 的 = %s" % (bad if bad else "无(30 个地址全 [FFFF,FFFF])"))
    nodone = [t["line"] for t in ja if t["done"] != 1]
    print("   J-A 事务 done!=1 的行号 = %s (共 %d 事务)" % (nodone if nodone else "无", len(ja)))
    # 3) J-B 新鲜性
    jb = [t for t in tx if t["tag"] in ("B_r2",)]
    print("== 复算 3 (J-B): 记录 %d 条 -> rd 序列 = %s" % (len(jb), [t["rd"] for t in jb]))
    jbm = re.search(r"ARM_J_B_RD(.*)$", txt, re.M)
    print("   件内 ARM_J_B_RD 行 = %s" % (jbm.group(1).strip() if jbm else "缺"))
    # 4) J-D: 新位
    ssl = [t for t in tx if t["ssl"] != 0]
    pbad = [t for t in tx if t["pbad"] != 0]
    print("== 复算 4 (J-D): ssl!=0 条数=%d pbad!=0 条数=%d" % (len(ssl), len(pbad)))
    for pat in ("ARM_J_A_SSL_SUM", "ARM_J_A_PBAD_SUM", "ARM_J_A_ANSWERED", "ARM_J_A_NO_RESPONSE"):
        for l in lines:
            if l.startswith(pat):
                print("   %s" % l)
    # 5) 其余 ARM 行全量
    print("== 复算 5: 全部 ARM_ 行 ==")
    for l in lines:
        if l.startswith("ARM_"):
            print("   %s" % l)
    # 6) W 系列
    for pat in ("WRITE_CHECK", "IDLE_STATUS", "PROBE_WIDTH", "VIO"):
        for l in lines:
            if pat in l and not l.startswith("#"):
                print("   [%s] %s" % (pat, l.strip()))

if __name__ == "__main__":
    main()
