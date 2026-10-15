#!/bin/bash
# burn_0x28.sh -- B4 轮: 烧 0x28 (F-3 + RFC seq + 换流门 R5 + E12 四观测计数器; BID 0x28 / 75 字 / 0x15C)
#   配方 = B1 轮 burn_0x27.sh 同构 (P7B_LOOP_HANDOFF §6 + P7B_PCIE_RESCAN_RECOVERY §7 场景C)
#   纪律: 只走 JTAG 易失烧录 (绝不写 QSPI); 烧前 sha256 双核 (归档件 + impl_1 原件交叉核);
#         跑 bat 正确式 = `MSYS_NO_PATHCONV=1 ... cmd /c ...` (env + `cmd //c` 会互相抵消)
#   用法: PEER_PW=<pw> bash burn_0x28.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x28_k0_20261016
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
KO=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/xdma.ko
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/burn/BURN_0x28_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== BURN_BEGIN $(date +%s.%N) $(date)"
WANT=79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8
SRC=$ROOT/_proj_10g/notes/p9_build_0x28/wrapper_p4.bit
IMPL=$ROOT/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4.bit

echo "--- 1) 位流 sha256 核 (归档件 + impl_1 原件交叉) + 复制到本轮 burn/ ---"
sha256sum "$SRC"
GOT=$(sha256sum "$SRC" | cut -d' ' -f1)
echo "SHA_WANT=$WANT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH (归档件) => 拒绝烧"; exit 1; }
IMPH=$(sha256sum "$IMPL" | cut -d' ' -f1)
echo "IMPL1_ORIG_SHA=$IMPH"
[ "$IMPH" = "$WANT" ] || { echo "SHA_MISMATCH (impl_1 原件 != 归档件) => 拒绝烧"; exit 1; }
echo "SHA_OK (归档件 == impl_1 原件 == 期望值)"
mkdir -p "$OUT/burn"
cp -n "$SRC" "$OUT/burn/wrapper_p4_0x28.bit" 2>/dev/null || true
sha256sum "$OUT/burn/wrapper_p4_0x28.bit"
stat -c 'LOCAL_BIT %n size=%s mtime=%y' "$OUT/burn/wrapper_p4_0x28.bit"
BIT_WIN='D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_board_0x28_k0_20261016\burn\wrapper_p4_0x28.bit'

echo "--- 2) 烧前现态 (QSPI 厂商设计, 场景C) + hw_server + xdma 驱动 insmod ---"
$SSH --sudo "systemctl is-active hw_server; echo '--- lspci before ---'; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'; lspci -vvv -s 00:1c.0 2>/dev/null | grep -E 'Memory behind bridge'; echo '--- lsmod ---'; lsmod | grep -w xdma || echo XDMA_NOT_LOADED"
$SSH --sudo "if ! lsmod | grep -qw xdma; then insmod $KO; echo INSMOD_RC=\$?; fi; sleep 3; lsmod | grep -w xdma; echo '--- /dev ---'; ls /dev/xdma0_control /dev/xdma0_user 2>&1"
$SSH --sudo "echo '--- dmesg insmod 后 ---'; dmesg | grep -i xdma | tail -4"

echo "--- 3) 烧录 (JTAG via 192.168.0.38:3121, 1MHz) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
echo "--- burn stdout 关键行 (逐字) ---"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (无 HIGH) => 停止"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (无 DONE) => 停止"; exit 1; }
grep -q "wrapper_p4_0x28.bit" "$F" || { echo "BURN_FAIL (位流路径不匹配) => 停止"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (出现 TCPREG-ABORT) => 停止"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stdout 陈旧: 本次没跑) => 停止"; exit 1; }
echo "BURN_OK (HIGH+DONE+路径+新鲜度+无ABORT 五判据)"

echo "--- 4) PCIe 恢复: 场景C => 根端口级 remove+rescan $(date +%s) ---"
$SSH --sudo "echo '--- 桥窗 before ---'; lspci -vvv -s 00:1c.0 2>/dev/null | grep -E 'Memory behind bridge'; echo 1 > /sys/bus/pci/devices/0000:00:1c.0/remove; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 6; echo '--- 桥窗 after ---'; lspci -vvv -s 00:1c.0 2>/dev/null | grep -E 'Memory behind bridge'; echo '--- lspci 02:00.0 ---'; lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'; echo '--- /dev ---'; ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 2>&1; echo '--- dmesg (identify_bars / probe) ---'; dmesg | grep -i xdma | grep -E 'identify_bars|probe_one|map_bars|probe err' | tail -6"

echo "--- 5) 身份门 (读 + p7b_snap.sh id) ---"
$SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'MARKER_0x14='; \$T/reg_rw /dev/xdma0_user 0x14 w 2>&1 | tail -1; echo -n 'UNIMPL_0x15C='; \$T/reg_rw /dev/xdma0_user 0x15C w 2>&1 | tail -1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
$SSH --sudo "NW=75 EXPECT_BID=0x00000028 bash /tmp/p7b_biz/p7b_snap.sh id; echo ID_RC=\$?"

echo "--- 6) 75 字窗口扫描 (期望 NFF=0) ---"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 74); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"

echo "--- 7) 解除受控停流 (0x08 写 0) + 链路见证 $(date +%s) ---"
$SSH --sudo "T=$T; echo -n 'SCRATCH_0x08(before)='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1; echo -n 'SCRATCH_0x08(after) ='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
echo "=== BURN_END $(date +%s.%N)"
