#!/usr/bin/env python3
# win_stats.py -- 0x24 主臂逐窗统计 + 缓冲占用 O 曲线 (口径声明见输出行)
#   主读数 = MIR_STREAM_ACCT 的 dW70 字段 (= 快照差分口径, 免疫 kimi B-1 的 READLOG 行级竞态)
#   O_i (辅助) = Σ(ddma*4 + dw70) - dma_i  (镜像已交付 - 成形器已取; 含在飞; kimi B-1 竞态可能污染个别行)
#   用法: python win_stats.py runs/WIN_*.txt
import glob
import re
import sys

RL = re.compile(r"READLOG i=(\d+) t=([\d.]+) gap_us=([-\d.]+) mmio_us=([-\d.]+) read_us=([-\d.]+) "
                r"got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)")
ACC = re.compile(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)")
IDA = re.compile(r"MIR_STREAM_IDA .*-> (-?\d+)\s+band=\[0,32\] closed_a=(\d)")
IDB = re.compile(r"MIR_STREAM_IDB .*-> (-?\d+)\s+band=\[0,24\] closed_b=(\d)")
VER = re.compile(r"MIR_VERIFY rc=(\d+) first_mismatch=(-?\d+)")
DONE = re.compile(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+) .*short=(\d+) .*read_error=(\d+) secs=([\d.]+)")
STS = re.compile(r"SRC_RC=(\d+) TE=([\d.]+)")
WIN = re.compile(r"=== WIN (\S+) .* T0=([\d.]+)")


def parse_win(chunk, tag):
    recs = [m.groups() for m in RL.finditer(chunk)]
    o = None
    omax = None
    ol = None
    if recs:
        cum = 0
        series = []
        for g in recs:
            ddma = int(g[10])
            dw70 = int(g[8])
            dma = int(g[9])
            cum += ddma * 4 + dw70
            series.append(cum - dma * 4)   # ⛔ 自伤登记: 首版漏 *4 (dma 是字) ⇒ O 假大 4×
        omax = max(series)
        omed = sorted(series)[len(series) // 2]
        o = omed
        ol = series[-1]
        tlast = float(recs[-1][1])
        tfirst = float(recs[0][1])
    else:
        tlast = tfirst = None
    acc = ACC.search(chunk)
    ida = IDA.search(chunk)
    idb = IDB.search(chunk)
    ver = VER.search(chunk)
    done = DONE.search(chunk)
    sts = STS.search(chunk)
    ts = re.search(r"起发端.*TS=([\d.]+)", chunk)
    out = {
        "tag": tag,
        "dw70": int(acc.group(3)) if acc else None,
        "pc": int(acc.group(1)) if acc else None,
        "taken": int(acc.group(2)) if acc else None,
        "idb": (int(idb.group(1)), int(idb.group(2))) if idb else None,
        "ida": (int(ida.group(1)), int(ida.group(2))) if ida else None,
        "ver": (int(ver.group(1)), int(ver.group(2))) if ver else None,
        "reads": int(done.group(2)) if done else None,
        "secs": float(done.group(5)) if done else None,
        "w_read": tlast,
        "n_rl": len(recs),
        "o_max": omax, "o_med": o, "o_last": ol,
    }
    if sts and ts:
        out["w_src"] = float(sts.group(2)) - float(ts.group(1))
    else:
        out["w_src"] = None
    return out


def main():
    rows = []
    for path in sys.argv[1:]:
        txt = open(path, encoding="utf-8", errors="replace").read()
        parts = re.split(r"(?m)^=== WIN ", txt)
        for p in parts[1:]:
            tag = p.split()[0]
            rows.append(parse_win(p, tag))
    print("tag      dW70(B)      dW70(MB)  pc(MB)   taken(MB) 式B(res/closed) 式A(res) reads  w_read(s) w_src(s)  O_max   O_med   O_last  file-order")
    sd = 0
    st_read = 0.0
    st_src = 0.0
    for r in rows:
        sd += r["dw70"] or 0
        st_read += r["w_read"] or 0
        st_src += r["w_src"] or 0
        print("%-8s %11d  %8.2f  %7.2f  %8.2f   %-14s %-8s %5s  %8.3f %7.3f  %7s %7s %7s" % (
            r["tag"], r["dw70"], (r["dw70"] or 0) / 1048576, (r["pc"] or 0) / 1048576,
            (r["taken"] or 0) / 1048576,
            f"{r['idb'][0]}/{r['idb'][1]}" if r["idb"] else "?",
            f"{r['ida'][0]}/{r['ida'][1]}" if r["ida"] else "?",
            r["reads"], r["w_read"] or -1, r["w_src"] or -1,
            r["o_max"], r["o_med"], r["o_last"]))
    print(f"== n={len(rows)}  ΣdW70={sd} ({sd/1048576:.2f} MB)  Σw_read={st_read:.2f}s  Σw_src={st_src:.2f}s")


if __name__ == "__main__":
    main()
