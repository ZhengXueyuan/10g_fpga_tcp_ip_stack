#!/usr/bin/env python
"""P7B-BUILDG-RFC-SEQ 变异件生成器: mut_M1..M4 = 修复的表达式的四个对照臂。

变异 (设计件 v3r2 §5.3 臂表; 基线源 = 修复后的 rtl/tcp_rx.v):
  M1 (冗余项): seq_lt = seq_diff[31] && (seq_diff != 0) —— 与修复版**逐位恒等**
     (d==0 ⇒ d[31]==0; d!=0 ⇒ 两版都 = d[31]); 期望: 与 A 臂逐条相同 (含 resp 字节)。
  M2 (半成品: 只修 ackresp 站): seq_lt 保持旧式绝对比较, **另加** seq_lt_rfc 只给
     ackresp 用 —— 方案 B 的机器证明: 纯 ACK 链 (w6a) 未修 ⇒ 红点恰好 {F2}。
  M3 (边界反转): seq_lt = seq_diff[31] && (seq_diff != 32'h80000000) —— 把 §3.3 的
     边界裁定 "d==2^31 判旧段" 反转成"判未来"; 期望: 红点恰好 {F5}。
  M4 (信号钉零): seq_lt = 1'b0 —— 期望: 红点 ⊇ {F1,F2,F5} (证明"红"由这个信号驱动)。

锚点纪律 (本仓 #72/#75 类坑): 锚点必须**计数断言** —— 现读行内容不符/出现次数
≠1 时硬失败, 不许静默产出"没变异的变异件"。用法:
    python mk_mut_rfc.py <repo_root> [--out <dir>]

⚠️ 以**二进制**读写: rtl/tcp_rx.v 是 CRLF —— 文本模式会把行尾归一化成 LF,
   让"变异件"凭空多出整文件的行差异。CRLF 计数逐件断言。
"""
import hashlib
import os
import sys

ANCHOR = 'seq_lt   = seq_diff[31];'
ACK_ANCHOR = '(win_ok || seq_lt)'

# (名, 替换文本, 期望变更行数, 期望净增行数)
MUTS = [
    ('mut_M1', 'seq_lt   = seq_diff[31] && (seq_diff != 32\'d0);', 1, 0),
    ('mut_M2', 'seq_lt   = (seq32 < ra_rcv_nxt);', 2, 1),
    ('mut_M3', 'seq_lt   = seq_diff[31] && (seq_diff != 32\'h80000000);', 1, 0),
    ('mut_M4', 'seq_lt   = 1\'b0;', 1, 0),
]


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.dirname(os.path.abspath(__file__))))), '')
    outdir = None
    if len(sys.argv) > 3 and sys.argv[2] == '--out':
        outdir = sys.argv[3]
    srcpath = os.path.join(root, 'rtl', 'tcp_rx.v')
    outdir = outdir or os.path.dirname(os.path.abspath(__file__))

    raw = open(srcpath, 'rb').read()
    src = raw.decode('utf-8')
    crlf_src = src.count('\r\n')

    # ---- 锚点现读断言 (锚点不中 / 出现多次 ⇒ 硬失败, 不落盘任何件) ----
    n_anchor = src.count(ANCHOR)
    assert n_anchor == 1, ('seq_lt anchor count != 1 (RTL 未按 §3.6 修复?): %d' % n_anchor)
    n_ack = src.count(ACK_ANCHOR)
    assert n_ack == 1, ('ackresp anchor count != 1 (表达式漂移?): %d' % n_ack)

    print('MUTGEN OK src=%s sha256=%s anchor=%r x%d' %
          (srcpath, hashlib.sha256(raw).hexdigest()[:16], ANCHOR, n_anchor))
    print('MUTGEN OK ackresp_anchor=%r x%d' % (ACK_ANCHOR, n_ack))

    for name, repl, exp_changed, exp_ins in MUTS:
        mut = src
        if name == 'mut_M2':
            # ① seq_lt 退回旧式绝对比较 (同一行), ② 其前插入 seq_lt_rfc 工作线,
            # ③ ackresp 站改用 seq_lt_rfc (半成品 = 只修一条链)
            mut = mut.replace(ANCHOR, repl, 1)
            idx = mut.index(repl)
            ls = mut.rfind('\n', 0, idx) + 1
            mut = (mut[:ls] +
                   '    wire        seq_lt_rfc = seq_diff[31]; '
                   '  // M2: RFC 形式, 只给 ackresp 站用 (半成品对照)\r\n' +
                   mut[ls:])
            mut = mut.replace(ACK_ANCHOR, '(win_ok || seq_lt_rfc)', 1)
        else:
            mut = mut.replace(ANCHOR, repl, 1)
        # ---- 变更面断言 (恰好 = 期望, 且 CRLF 计数守恒/随插入同步) ----
        #   插入型编辑的比对法: 先从 ml 摘掉插入行, 再逐行比 —— 直接按位置比会把
        #   插入点之后的全部行都算成"变更"(假 FAIL)。
        sl, ml = src.splitlines(), mut.splitlines()
        assert len(ml) - len(sl) == exp_ins, (name, 'insert delta', len(ml) - len(sl))
        ml_cmp = ml
        if exp_ins:
            ins_idx = [i for i, l in enumerate(ml) if 'seq_lt_rfc' in l and 'wire' in l]
            assert len(ins_idx) == 1, (name, 'inserted line not found uniquely', ins_idx)
            ml_cmp = ml[:ins_idx[0]] + ml[ins_idx[0] + 1:]
        assert len(ml_cmp) == len(sl), name
        diffs = [i + 1 for i in range(len(sl)) if sl[i] != ml_cmp[i]]
        assert len(diffs) == exp_changed, (name, 'changed lines', diffs)
        assert mut.count(repl) == 1 and mut.count(ANCHOR) == 0, name
        if name == 'mut_M2':
            assert mut.count('(win_ok || seq_lt_rfc)') == 1 and mut.count(ACK_ANCHOR) == 0
            assert mut.count('seq_lt_rfc') == 2, mut.count('seq_lt_rfc')
        mraw = mut.encode('utf-8')
        assert mraw.count(b'\r\n') == crlf_src + exp_ins, (name, 'CRLF count')
        assert mraw.count(b'\n') == mraw.count(b'\r\n'), (name, 'lone LF introduced')
        out = os.path.join(outdir, name + '.v')
        with open(out, 'wb') as fh:
            fh.write(mraw)
        print('MUTGEN OUT %s sha256=%s changed_lines=%r ins=%d' %
              (out, hashlib.sha256(mraw).hexdigest()[:16], diffs, exp_ins))


if __name__ == '__main__':
    main()
