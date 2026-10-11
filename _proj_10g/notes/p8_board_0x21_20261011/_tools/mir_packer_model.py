#!/usr/bin/env python3
"""mir_packer_model.py -- rtl/app_rx_mirror.v 写侧打包器的逐拍模型 (读 RTL 的复算; 不改 RTL)。

逐条对 `rtl/app_rx_mirror.v` 的写侧逻辑 (:150-250):
  n_cur     = popcount(pend_keep) if pend_valid else 0 ;  room = 8 - acc_cnt
  kk        = min(n_cur, room) ;  drain_all = (kk == n_cur)
  pend_after= pend_valid and not drain_all
  load      = src_beat and not pend_after     # 收进暂存 (暂存 = 单槽 8B)
  drop_now  = src_beat and pend_after         # 拒收整拍 (按 popcount 计字节)
  have      = (acc_cnt + kk) == 8 ;  wr_en = have and !full and cap_on
  load -> pend<=beat ; elif pend_valid: drain_all ? pend<=None : pend<=pend[kk:]
  wr_en -> acc<=None(写一字) ; elif kk: acc<=acc+pend[:kk]
源模型: 每帧 = paylen//8 个满 8B 拍 + (paylen%8 ? 1 部分拍); 帧内背靠背 8B/拍 (密集);
        帧间 gap 空闲拍。⚠️ "帧内密集"是上轮 0x1F 板级 50% 丢幅反推的旁证 (旧版 4B/拍:
        稀疏源不丢; 实测恒丢一半 ⇒ 源必为帧内密集)。
判据输出: 丢字节 / 写出字节 / first_mismatch (写出流 vs 连续流 0,1,2,... 的首个不等处)。
"""
import sys

def run(paylen, nframes, verbose=3):
    acc = []                     # 当前累加字节 (list of 标签)
    pend = None                  # 单槽暂存 (None 或 list)
    out = []                     # 写出字节流
    drop = 0
    pos = 0                      # 源连续字节流位置
    per_frame = []
    for fi in range(nframes):
        d0, o0 = drop, len(out)
        beats = [tuple(range(pos + 8*i, pos + 8*i + 8)) for i in range(paylen//8)]
        pos += paylen - (paylen % 8)
        if paylen % 8:
            beats.append(tuple(range(pos, pos + paylen % 8)))
            pos += paylen % 8
        for beat in beats:
            n_cur = len(pend) if pend is not None else 0
            room = 8 - len(acc)
            kk = min(n_cur, room)
            drain_all = (kk == n_cur)
            pend_after = (pend is not None) and (not drain_all)
            if not pend_after:
                pend = list(beat)                     # load
            elif pend is not None:                    # 搬 kk 个 (drain_all 为假)
                pend = pend[kk:]
            if (len(acc) + kk) == 8:
                out.extend(acc + list(beats_prev_head)) # placeholder (不会走到)
            # ↑ 上面写法不可靠, 下面统一处理
        # (见下方 v2 实现)
    return None

def run2(paylen, nframes, verbose=3):
    """v2: 单遍、显式 content 记账。"""
    acc = []                     # 累加器 (字节标签列表, 0..8)
    pend = None
    out = []
    drop = 0
    pos = 0
    per_frame = []
    for fi in range(nframes):
        d0, o0 = drop, len(out)
        seq = []
        for i in range(paylen // 8):
            seq.append(("full", 8))
        if paylen % 8:
            seq.append(("tail", paylen % 8))
        for kind, nbt in seq:
            beat = list(range(pos, pos + nbt)); pos += nbt
            n_cur = len(pend) if pend is not None else 0
            room = 8 - len(acc)
            kk = min(n_cur, room)
            drain_all = (kk == n_cur)
            pend_after = (pend is not None) and (not drain_all)
            drop_now = pend_after
            # move kk bytes from pend into acc (若 pend 存在)
            moved = []
            if pend is not None and kk > 0:
                moved = pend[:kk]
            have = (len(acc) + kk) == 8
            # --- 更新 (顺序与 RTL 一致: 先 pend 后 acc) ---
            if not pend_after:
                pend = list(beat)
            elif pend is not None:
                pend = None if drain_all else pend[kk:]
            if have:
                out.extend(acc + moved)      # 写出一个 64 位字
                acc = []
            elif kk > 0:
                acc = acc + moved
            if drop_now:
                drop += nbt
        # 帧间空闲: pend 排空
        guard = 0
        while pend is not None and guard < 32:
            guard += 1
            n_cur = len(pend); room = 8 - len(acc); kk = min(n_cur, room)
            drain_all = (kk == n_cur)
            moved = pend[:kk]
            have = (len(acc) + kk) == 8
            pend = None if drain_all else pend[kk:]
            if have:
                out.extend(acc + moved); acc = []
            elif kk > 0:
                acc = acc + moved
        per_frame.append((fi, drop - d0, len(acc), len(out) - o0))
        if fi < verbose:
            print(f"  frame {fi}: drop={drop-d0:6d} acc_out={len(acc)} words_in_frame={len(out)-o0}")
    fm = -1
    for i, b in enumerate(out):
        if b != i:
            fm = i; break
    return dict(offered=nframes*paylen, drop=drop, out_bytes=len(out), acc_end=len(acc),
                first_mismatch=fm, per_frame=per_frame, out_idx=out)

def run_frames(frame_list, verbose=0):
    """对显式帧长表跑逐拍模型 (支持末帧变长; 与 run2 同一套逻辑)。返回含 out_idx。"""
    acc = []; pend = None; out = []; drop = 0; pos = 0; per = []
    for fi, L in enumerate(frame_list):
        d0 = drop; o0 = len(out)
        seq = [8] * (L // 8) + ([L % 8] if L % 8 else [])
        for nbt in seq:
            beat = list(range(pos, pos + nbt)); pos += nbt
            n_cur = len(pend) if pend is not None else 0
            room = 8 - len(acc); kk = min(n_cur, room)
            drain_all = (kk == n_cur)
            pend_after = (pend is not None) and (not drain_all)
            moved = pend[:kk] if (pend is not None and kk > 0) else []
            have = (len(acc) + kk) == 8
            if not pend_after: pend = list(beat)
            elif pend is not None: pend = None if drain_all else pend[kk:]
            if have: out.extend(acc + moved); acc = []
            elif kk > 0: acc = acc + moved
            if pend_after: drop += nbt
        g = 0
        while pend is not None and g < 32:      # 帧间空闲: 排空
            g += 1
            n_cur = len(pend); room = 8 - len(acc); kk = min(n_cur, room); drain_all = (kk == n_cur)
            moved = pend[:kk]; have = (len(acc) + kk) == 8
            pend = None if drain_all else pend[kk:]
            if have: out.extend(acc + moved); acc = []
            elif kk > 0: acc = acc + moved
        per.append((fi, drop - d0, len(acc), len(out) - o0))
        if fi < verbose:
            print(f"  frame {fi}: drop={drop-d0} acc_out={len(acc)} words={len(out)-o0}")
    fm = -1
    for i, b in enumerate(out):
        if b != i: fm = i; break
    return dict(offered=sum(frame_list), drop=drop, out_bytes=len(out), acc_end=len(acc),
                first_mismatch=fm, per_frame=per, out_idx=out)


def frames_for(K, paylen):
    n, r = divmod(K, paylen)
    return [paylen]*n + ([r] if r else [])


if __name__ == "__main__":
    pl = int(sys.argv[1]) if len(sys.argv) > 1 else 1472
    nf = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    print(f"--- paylen={pl} nframes={nf} (模型: 帧内密集 8B/拍, 帧间空闲, 单槽暂存+累加器) ---")
    r = run2(pl, nf)
    print(f"offered={r['offered']} drop={r['drop']} ({100.0*r['drop']/r['offered']:.3f}%) "
          f"out_bytes={r['out_bytes']} acc_end={r['acc_end']} first_mismatch={r['first_mismatch']}")
    print(f"账: out + drop + acc_end = {r['out_bytes']+r['drop']+r['acc_end']}  (== offered ? "
          f"{r['out_bytes']+r['drop']+r['acc_end'] == r['offered']})")
