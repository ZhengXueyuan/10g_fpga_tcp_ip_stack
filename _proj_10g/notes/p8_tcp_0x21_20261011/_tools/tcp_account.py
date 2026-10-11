#!/usr/bin/env python3
"""tcp_account.py -- 从本轮 runs/*_raw.txt 里抽读数, 生成字节账表 (逐字原文, 不做推断)。"""
import re, glob, os, sys

def get_snaps(txt):
    """返回 [(tag, {W: val})] 按出现顺序 (触发式快照)"""
    out = []
    cur = None
    for line in txt.splitlines():
        m = re.match(r"SNAP_BEGIN (\S+) gen=(\d+)", line)
        if m:
            cur = (m.group(1), {})
            out.append(cur); continue
        m = re.match(r"W(\d+)\s+0x[0-9A-Fa-f]+\s+(\S+)\s+(0x[0-9a-fA-F]+)", line)
        if m and cur is not None:
            cur[1]["W" + m.group(1)] = int(m.group(3), 16)
    return out

def one(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    name = os.path.basename(path).replace("_raw.txt", "")
    K = None
    m = re.search(r"K=(\d+)", txt)
    if m: K = int(m.group(1))
    m = re.search(r"KSRC=(\d+) KTOOL=(\d+)", txt)
    if m: K = int(m.group(2))   # 中流: 工具 K
    snaps = get_snaps(txt)
    d = {}
    for tag, w in snaps:
        if tag.endswith("_pre"):  d["pre"] = w
        if tag.endswith("_post"): d["post"] = w
    res = {"name": name, "K": K, "pre": d.get("pre", {}), "post": d.get("post", {})}
    # 工具行
    m = re.search(r"MIR_DMA_DONE bytes=(\d+) words=(\d+) secs=([\d.]+)", txt)
    res["dma_done"] = m.groups() if m else None
    m = re.search(r"MIR_DONE bytes=(\d+) words=(\d+) secs=([\d.]+)", txt)   # user-BAR 路径
    res["bar_done"] = m.groups() if m else None
    m = re.search(r"MIR_VERIFY rc=(\d+) first_mismatch=(-?\d+) of (\d+)\s*$", txt, re.M)  # BAR 路径: 行尾无 poff
    res["verify_bar"] = m.groups() if (m and not res.get("verify")) else None
    m = re.search(r"MIR_DMA_ACCT cnt0=(\d+) cnt1=(\d+) lag_max=(\d+) clobber=(\d+) short_reads=(\d+)", txt)
    res["acct"] = m.groups() if m else None
    m = re.search(r"MIR_VERIFY rc=(\d+) first_mismatch=(-?\d+) of (\d+) \(pat_off_eff=(\d+)\)", txt)
    res["verify"] = m.groups() if m else None
    m = re.search(r"FATAL: 计数器跳变 (\d+) 字", txt)
    res["fatal"] = m.group(1) if m else None
    m = re.search(r"SRC_SUM tx_bytes=(\d+) .*dur_s=([\d.]+)", txt)
    res["src"] = m.groups() if m else None
    return res

rows = [one(p) for p in sorted(glob.glob("runs/*_raw.txt"))]
print(f"{'run':10} {'K':>9} {'pc':>8} {'dW53':>9} {'dW70':>7} {'dW54':>5} {'残余':>7}  工具行")
for r in rows:
    pre, post = r["pre"], r["post"]
    d53 = (post.get("W53", 0) - pre.get("W53", 0)) & 0xFFFFFFFF
    d70 = (post.get("W70", 0) - pre.get("W70", 0)) & 0xFFFFFFFF
    d54 = (post.get("W54", 0) - pre.get("W54", 0)) & 0xFFFFFFFF
    pc = int(r["dma_done"][0]) if r["dma_done"] else (int(r["bar_done"][0]) if r.get("bar_done") else 0)
    resid = d53 - pc - d70
    tool = ("DMA bytes=%s words=%s" % (r["dma_done"][0], r["dma_done"][1])) if r["dma_done"] else \
           (("FATAL jump=%s 字" % r["fatal"]) if r["fatal"] else (("BAR bytes=%s words=%s secs=%s" % r["bar_done"]) if r.get("bar_done") else "PC1: 工具未用 (主机不读 MIR_DATA)"))
    if r["acct"]:
        tool += " | cnt0=%s cnt1=%s lag=%s clob=%s short=%s" % r["acct"]
    if r["verify"]:
        tool += " | VERIFY rc=%s fm=%s of %s (poff=%s)" % r["verify"]
    if r.get("verify_bar"):
        tool += " | VERIFY rc=%s fm=%s of %s (BAR)" % r["verify_bar"]
    print(f"{r['name']:10} {r['K']:>9} {pc:>8} {d53:>9} {d70:>7} {d54:>5} {resid:>7}  {tool}")
print()
print("注: '残余' = dW53 - pc - dW70; 判据式 pc + dW70 + (acc_cnt_r+stg_cnt) == dW53, "
      "正常态残余 ∈ [0,24] 且 K%8==0+无丢 ⇒ 期望 0。")
print("    FATAL 跑 ('pc'=0) 的差额 = 数据留在环里/被环回绕覆盖 —— **工具侧**量, 不是镜像丢字。")
