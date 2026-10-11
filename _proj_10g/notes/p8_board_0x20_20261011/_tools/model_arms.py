#!/usr/bin/env python3
"""model_arms.py -- 两臂精确参数的模型预测 (调用 mir_packer_model.run2 的逐帧版)。"""
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", "mir_packer_model.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def frames_for(K, paylen):
    n, r = divmod(K, paylen)
    return [paylen]*n + ([r] if r else [])

def run_frames(frames):
    acc=[]; pend=None; out=[]; drop=0; pos=0; per=[]
    def step(nbt, dense=True):
        nonlocal acc, pend, drop, pos
        beat = list(range(pos, pos+nbt)); pos += nbt
        n_cur = len(pend) if pend is not None else 0
        room = 8 - len(acc); kk = min(n_cur, room); drain_all = (kk == n_cur)
        pend_after = (pend is not None) and (not drain_all)
        moved = pend[:kk] if (pend is not None and kk>0) else []
        have = (len(acc)+kk)==8
        if not pend_after: pend = list(beat)
        elif pend is not None: pend = None if drain_all else pend[kk:]
        if have: out.extend(acc+moved); acc=[]
        elif kk>0: acc = acc+moved
        if pend_after: drop += nbt
    for L in frames:
        d0=drop
        for i in range(L//8): step(8)
        if L%8: step(L%8)
        g=0
        while pend is not None and g<32:      # 帧间空闲
            g+=1
            n_cur=len(pend); room=8-len(acc); kk=min(n_cur,room); drain_all=(kk==n_cur)
            moved=pend[:kk]; have=(len(acc)+kk)==8
            pend = None if drain_all else pend[kk:]
            if have: out.extend(acc+moved); acc=[]
            elif kk>0: acc=acc+moved
        per.append((len(per), drop-d0, len(acc), len(out)))
    fm=-1
    for i,b in enumerate(out):
        if b!=i: fm=i; break
    return dict(offered=sum(frames), drop=drop, out_bytes=len(out), acc_end=len(acc), fm=fm)

for tag, K, pl in (("ARM-A", 1048576, 1472), ("ARM-B", 1505280, 1470)):
    fr = frames_for(K, pl)
    r = run_frames(fr)
    print(f"{tag}: K={K} paylen={pl} frames={len(fr)} (末帧={fr[-1]})")
    print(f"   预测: drop={r['drop']} ({100.0*r['drop']/r['offered']:.3f}%) out_bytes={r['out_bytes']} "
          f"acc_end={r['acc_end']} first_mismatch={r['fm']}  账={(r['out_bytes']+r['drop']+r['acc_end'])==r['offered']}")
