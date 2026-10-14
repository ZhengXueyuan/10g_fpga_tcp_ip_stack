#!/usr/bin/env python
"""P7B-BUILDG-RFC-SEQ 施工: 对 rtl/tcp_rx.v 施加 §3.6 的 1 行表达式 + 注释订正。

做法 = **从设计件 v3r2 的 §3.6 代码块逐字提取替换文本** (不手抄, 消除转录风险);
匹配按"含唯一特征串的整行"定位; 全部断言不成立即硬失败、不落盘。
输出: 修改后的文件 + sha256 / 行数 / CRLF 计数 / 变更 hunk 清单 (stdout)。
CRLF 纪律: 原文件纯 CRLF (929 CRLF / 0 孤立 LF) ⇒ 新块逐行以 \r\n 拼接。
"""
import hashlib
import re
import sys

RTL = r'D:\repo\XCKU5PMini\udp_hls_10g\rtl\tcp_rx.v'
MD = (r'D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_fix_rfcseq_design_20261014'
      r'\P7B_BUILDG_RFC_SEQ_DESIGN_v3r2.md')


def block_after(md, marker):
    m = re.search(re.escape(marker) + r'.*?```verilog\r?\n(.*?)```', md, re.S)
    assert m, ('design block not found', marker)
    body = m.group(1)
    lines = body.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    return lines


def main():
    md = open(MD, encoding='utf-8').read()
    new1 = block_after(md, '**① `:320`')
    new2 = block_after(md, '**② `:356`')
    assert len(new1) == 8, ('block1 line count', len(new1))
    assert len(new2) == 1, ('block2 line count', len(new2))
    assert new1[-1].lstrip().startswith('wire'), new1[-1]
    assert 'seq_diff[31];' in new1[-1]
    assert new2[0].lstrip().startswith('//'), new2[0]

    raw = open(RTL, 'rb').read()
    src = raw.decode('utf-8')
    crlf0 = src.count('\r\n')
    assert crlf0 == 929 and src.count('\n') == crlf0, ('CRLF discipline', crlf0)
    lines = src.split('\r\n')
    assert lines[-1] == '', 'file must end with CRLF'

    def find_unique(frag, exclude=None):
        hits = [i for i, l in enumerate(lines) if frag in l]
        if exclude:
            hits = [i for i in hits if not exclude(l := lines[i])]
        assert len(hits) == 1, ('anchor not unique', frag, hits)
        return hits[0]

    i1 = find_unique('wire        seq_lt   = (seq32 < ra_rcv_nxt);')
    assert '(回绕安全' in lines[i1], lines[i1]
    i2 = find_unique('// 窗口内乱序 (seq > rcv_nxt) 与重复 (seq < rcv_nxt)')
    assert '(快速重传' in lines[i2], lines[i2]

    # 变更面 = 恰好这两行 (非注释行变更面: 第 i1 行)
    print('OLD1[%d]: %s' % (i1 + 1, lines[i1]))
    print('OLD2[%d]: %s' % (i2 + 1, lines[i2]))

    new_lines = lines[:i1] + new1 + lines[i1 + 1:i2] + new2 + lines[i2 + 1:]
    out = '\r\n'.join(new_lines)
    assert out.count('\r\n') == crlf0 + len(new1) - 1, out.count('\r\n')
    assert len(new_lines) == len(lines) + len(new1) - 1, len(new_lines)
    # 旧表达式彻底消失 (活动行与注释都不得再有旧绝对比较的字面)
    assert '(seq32 < ra_rcv_nxt)' not in out, 'old expression still present'
    assert '(seq > rcv_nxt) 与重复 (seq < rcv_nxt)' not in out
    assert out.count('wire        seq_lt   = seq_diff[31];') == 1
    assert 'RFC 793 SEQ_LT' in out and 'seq_diff[31]' in out
    oraw = out.encode('utf-8')
    with open(RTL, 'wb') as fh:
        fh.write(oraw)
    print('APPLIED %d -> %d lines (CRLF %d -> %d)' %
          (len(lines) - 1, len(new_lines) - 1, crlf0, out.count('\r\n')))
    print('NEW sha256=%s' % hashlib.sha256(oraw).hexdigest())
    print('NEW blob would-be git-hash per git hash-object (see bat/README)')
    print('--- new block 1 (lines %d..%d) ---' % (i1 + 1, i1 + len(new1)))
    for l in new1:
        print(l)
    print('--- new block 2 (line %d) ---' % (i1 + len(new1) + (i2 - i1 - 1) + 1))
    for l in new2:
        print(l)


if __name__ == '__main__':
    sys.exit(main())
