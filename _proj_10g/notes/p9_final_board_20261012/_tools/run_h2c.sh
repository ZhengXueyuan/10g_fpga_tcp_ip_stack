#!/bin/bash
# run_h2c.sh -- T1: H2C 写通道**首次激励** (位流 0x23 / AXIS 下 H2C = m_axis_h2c + 恒 tready=1 吞噬器)
#   档: 4096 / 65536 / 1048576 B 各一跑 (每配置 ≤3 跑)。
#   判据: 返回/退出码正常 + 无 dmesg 报错/超时 + 其它通道不受影响 (前后触发式快照 W11/W13/W70/
#         W53/W54/W5/W43/W20 与 MIR_CTRL 不动 / MIR_STATUS 无异常位 / SCRATCH_0x08 不动)。
#   数据 = /dev/urandom 现生成 (内容故意丢弃 —— 本档只判"吞噬器没卡死", 不外推内容正确性)。
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_final_board_20261012
OUT_W=D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_final_board_20261012  # Windows 路径: peer_ssh.py 是本机 Windows Python, --put 的 local 参数不吃 /d/… 形式
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
D=/tmp/p9_final
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }

LOG=$OUT/runs/T1_H2C_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== T1_DEPLOY $(date +%s.%N)"
$SSH "mkdir -p $D && cp /tmp/p9_board_0x23/p7b_snap.sh $D/ && ls -la $D; echo '--- snap md5 (对照: 仓库 _proj_pcie/p7b_biz/p7b_snap.sh = 6325658a… 权威现役; /tmp/p7b_biz 冻结件 ba2faf79… 是旧修订、W70 无标签) ---'; md5sum $D/p7b_snap.sh /tmp/p9_board_0x23/p7b_snap.sh /tmp/p7b_biz/p7b_snap.sh"
echo "--- put t1_remote_step.sh ---"
$SSH --put "$OUT_W/_tools/t1_remote_step.sh" "$D/t1_remote_step.sh"
echo "--- H2C 数据件 (/dev/urandom; 已存在则复用 ⇒ 两跑写同一份数据) + 指纹 ---"
$SSH "cd $D && { [ -f h2c_4096.bin ] || head -c 4096 /dev/urandom > h2c_4096.bin; } && { [ -f h2c_65536.bin ] || head -c 65536 /dev/urandom > h2c_65536.bin; } && { [ -f h2c_1048576.bin ] || head -c 1048576 /dev/urandom > h2c_1048576.bin; } && ls -la h2c_*.bin && sha256sum h2c_*.bin && md5sum t1_remote_step.sh"

for S in 4096 65536 1048576; do
  echo ""
  echo "############ T1 档 size=$S ############"
  $SSH --sudo "bash $D/t1_remote_step.sh $S ${PFX:-t1}_$S"
  echo "LOCAL_STEP_RC=$? (size=$S)"
done

echo ""
echo "=== T1_DONE $(date +%s.%N)"
