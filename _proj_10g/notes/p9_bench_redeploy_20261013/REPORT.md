# p9_bench_redeploy_20261013 — 台架重部署（关机后）简报

> 轮次 = **只重部署**：对端可达 + `hw_server` + `/tmp/p7b_biz/` 重建 + 编译 + 自检 + 窗协议脚本上载 + 网络/驱动命令清单。
> **边界声明**：**未烧板 · 未写 QSPI · 未碰板侧寄存器**（全程 0 次寄存器写；§5 只读见证）· **未改仓内任何已存在文件** · **本报告不下 PASS/FAIL 裁定**；「未观测到」不写成「不存在」。口令 `PEER_PW` 只作命令前缀、**未落盘**（本轮实际未用到 `--sudo`）。
> （落盘说明：REPORT.md 由 TL 代落盘 —— 平台拒写 .md 的已知间歇故障；正文逐字为重部署 agent 回传。）

## 1. 对端可达 + `hw_server`（证据）

| 项 | 读数 | 判据 |
|---|---|---|
| 可达性（**TCP 判据，不用 ping 退出码**） | `TCP OPEN 192.168.0.38:22` + `TCP OPEN 192.168.0.38:3121` | 本机 `socket.connect` 实测 |
| 登录 | `hostname a-MS-7850` · `date` = `Tue Oct 13 21:41:16 PM CST 2026` · **`uptime` = up 6 min** | ⇒ 对端 **≈21:34 开机**，与「关机后重启」相符 |
| `/tmp` 现状 | 只剩 systemd 私有目录（`.font-unix`/`snap-private-tmp`/`systemd-private-*`/`TMP_LD_LIB_PATH…`）—— `p7b_biz/` `p9_rate/` `p9_hostread/` `p9_board_0x23/` **全不存在** | 与 `P7B_LOOP_HANDOFF.md` §6-新块2 §B 的「重启即清空」逐条相符 |
| `hw_server` | `systemctl is-active hw_server` = **active**；`ss -lntp` = **`LISTEN 0 16 0.0.0.0:3121`** | 与预期一致 |

## 2. 文件上载（28 件：`/tmp/p7b_biz/` 25 件 + `/tmp/` 3 件）

⭐ **上载后逐件 md5 双核 = 25/25 逐字相同**（本机 `md5sum` vs 对端 `md5sum` 现算）：

- `p7b_io.h` `62b1257d69c40f24bfa9a799593073b7` · `p7b_spsc.h` `3132db495c29ab85b7f6a5617803644f` · `p7b_affinity.h` `b03222792d20443138515ba2804b0d87` · `p7b_pattern.h` `b2f2e9627bac53bf3b4ab2b565afe872`
- `p7b_tcp_sink.cpp` `8d02ef6426d4ef6ad5fd2c514965c1e8` · `p7b_tcp_src.cpp` `7a6191fc01818f64eb956da069ed0640` · `p7b_udp_src.cpp` `f5ff317288b59b3e3c91988ca07446c9` · `p7b_rate2_bench.cpp` `b9c18a7695480a24f60169313034c0fd`
- **`p7b_mir_dump.cpp` `b4833c55642120f093fa2ee9e2544aa8`** ✅ = 派单期望值
- `p7b_tcp_src_fix.cpp` `21ca7fa995fae7dc06675b64ff24dc36` · `p7b_tcp_src_diag.cpp` `217a0e48191e02f9fc120cf5fa42a49e` · `p7b_tcp_src_rate.cpp` `c3b9b01c42dae1ef3e098893d839f986` · `p7b_tcp_sink_rate.cpp` `92ef5b458043179a432e1515546b585a`
- `p7b_snap.sh` `97c66382cf2a0c334f5e6466ce714ad2` · `p7b_selftest.sh` `40c3f658b504b874c0df51037fa68f3a` · `p7b_dualthread_selftest.sh` `902c01079f9bd7bf32b939f596882be0` · `p7b_lane8_selftest.sh` `ac6d56dca7d203fe4b7a281fa0a1bb53`
- `aff_selftest.sh` `19cb9f2d9781e8a338246960e3c340ff` · `p7b_fake_board.py` `4154925a8cd5a44d12bfc0a1fd7db35d` · `p7baff_faultinject.cpp` `23a01d88b6acd01587f70692e421b476`
- `pcap_off_dryrun.sh` `3be0e9d757e00286a29efceb151de0a9` · `stc_dl.sh` `a9b4a0c2691fa47be2365ddd9d6a5726` · `j6_stagec.sh` `3b248ece038b01e2df7483b5aa25efe5` · `tcpreg_j6.sh` `78e24f7ab25cd81789fd088aeb179481` · `j6_r6fix.sh` `7b0968cf4cae5bbdeedfeb827b653e6d`

**窗协议脚本（同文副本，落 `/tmp/`）**——三件与仓内 md5 相同、已 `chmod +x`：

| 件 | 仓内出处 | md5 |
|---|---|---|
| `/tmp/run_win_hw.sh` | `_proj_10g/notes/p9_hostread_20261013/_tools/` | `7b40bcbb4adc2bf776d421656b65e7a9`（= hostread 订正轮记录的权威值） |
| `/tmp/analyze_readlog.py` | 同上 | `a451b98d1416e9c21be5ce03e9e61169` |
| `/tmp/final_state_rt.sh` | `_proj_10g/notes/p9_rate_20261013/_tools/` | `e72ae91d0141dd5646e8deca8a022c45` |

⭐ **顺带登记两个工具坑（本轮实测，必修）**：① Git Bash 下 `peer_ssh.py --put … <远端 /tmp/…>` **必须加 `MSYS_NO_PATHCONV=1`** —— 否则 MSYS 把远端 `/tmp/...` 改写成 Windows 路径 ⇒ paramiko 在对端写不存在的路径 ⇒ **`FileNotFoundError: [Errno 2] No such file`（28/28 全红，看着像"本地文件不存在"）**；② 本机 stdout 为 GBK 时，打印对端含 `∉` 等字符的输出抛 `UnicodeEncodeError` ⇒ 需 `PYTHONIOENCODING=utf-8`。两条都不是板侧问题。

## 3. 编译 + 产物指纹（**BUILD.md §3 对照**）

- 编译器 = 对端 `g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0`；命令**逐字** = `g++ -O3 -pthread -o <name> <name>.cpp`（BUILD.md §2 权威口径；`p7b_mir_dump` 用其头注释的同款行）。
- **9/9 RC=0、零编译诊断**（`/tmp/p7b_biz/_build.log` 288 B 内只有 `BUILD … RC=0` 九行；`grep -v` 后为空）。
- 产物 mtime 全落 **2026-10-13 21:43:07–21:43:28 (+0800)**（本次会话独有窗口）。

| # | 产物 | 字节 | md5（本次现编） | BUILD.md §3 | 判定 |
|---|---|---|---|---|---|
| 1 | `p7b_tcp_sink` | 169,392 | `6d9b14f24725fa326ffe5b169f77e30f` | 同 | ✅ 逐字相同 |
| 2 | `p7b_tcp_src` | 127,720 | `79be2a09024206b7c678dc13a3b9051d` | `48d066a04684fbd6b901679120d88c3c` (119,488) | ⛔ 与表不同 —— 见下「表落后两代」 |
| 3 | `p7b_udp_src` | 128,048 | `e0d4da5834cb95d67afb0cc523d1f92f` | `a3faafd37ed2e21e0acd3cc925e9c98c` | ⛔ 同上（新旧**同尺寸**） |
| 4 | `p7b_tcp_src_fix` | 119,496 | `d1ca0c288efe6723488e4c1a6960d1b5` | 同 | ✅ |
| 5 | `p7b_tcp_sink_rate` | 127,488 | `ca6900fd54036be7fe1d337ca9ef83b8` | 同 | ✅ |
| 6 | `p7b_tcp_src_rate` | 119,496 | `a76b2b4b1e44d6c9edcaa301d90aabcb` | 同 | ✅ |
| 7 | `p7b_tcp_src_diag` | 123,592 | `430ed36ade4ec64ba6f5cb52e5f4f335` | 同 | ✅ |
| 8 | `p7b_rate2_bench` | 171,040 | `1e956072f30a25f3e547e8c42107afb3` | 同 | ✅ |
| 9 | `p7b_mir_dump` | 108,696 | **`7cebded7e9270b6a2d81f5db29843f4d`** | 派单期望值 | ✅ **逐字击中** |

**两条失配的逐条解释（都不是"不可复现"）**：BUILD.md §3 表冻结于 **2026-10-11 00:47**，而 `p7b_tcp_src.cpp`（mtime 10-11 12:45）/`p7b_udp_src.cpp`（mtime 10-11 12:16）在其后被 P8 轮改过。本次现编产物 **逐字等于 P8/P9 轮记录的"冻结工具"指纹**：`p7b_tcp_src 79be2a09…` = `p8_board_20261011/REPORT.md:34` · `p8_tcp_0x21_20261011/deploy_tcp.sh:29`（EXPECT 行）· `runs/DEPLOY_TCP_20261011_193219.txt`；`p7b_udp_src e0d4da58…` = `p8_board_0x20_20261011/REPORT.md:44` · `p8_board_0x21_20261011/deploy_0x21.sh:38`（EXPECT 行）。

**输入指纹对照**：12 件输入中 **10 件逐字同**；不同 2 件同上（`e73309a9…→7a6191fc…`、`074321cf…→f5ff3172…`，均被 P8 轮独立记录佐证）。脚本类：`p7b_selftest.sh` `40c3f658…` ✅ · `aff_selftest.sh` `19cb9f2d…` ✅ · `p7b_dualthread_selftest.sh` `902c0107…` ✅ · `p7b_lane8_selftest.sh` `ac6d56dc…` ✅ · `p7baff_faultinject.cpp` `23a01d88…` ✅ · `pcap_off_dryrun.sh` `3be0e9d7…` ✅ · `stc_dl.sh` `a9b4a0c2…` ✅ · `j6_stagec.sh` `3b248ece…` ✅；`tcpreg_j6.sh` 表 `158454d4…` → 现树 `78e24f7a…`（表亦落后，未逐条追平）。

## 4. 自检（板外，未碰板）

| 件 | 命令 | 结果 | 判据指纹（mtime + 本次独有 tag） |
|---|---|---|---|
| `p7b_mir_dump` | `./p7b_mir_dump --selftest` | **RC=0 · `OK=52` · `FAIL=0` · 末行 `MIR_SELFTEST PASS`** | `_selftest_mir_20261013_214427.log` 5051 B · 21:44:38 +0800 · md5 `08b4caa653dd7d8f99cb7264b127314f` |
| `p7b_udp_src` | `./p7b_udp_src --selftest` | **RC=0 · `SELFTEST p7b_udp_src: OK`** + 3 组向量逐字匹配（`off0..15` / `off1460..7` / `state@100`） | `_selftest_udp_20261013_214427.log` 805 B · 21:44:38 +0800 · md5 `671f6b8fe792cd9f1ef1ad7fecde7572` |

- ⭐ `52 OK / 0 FAIL / PASS` **与派单期望逐字相符**（T1–T15b 全绿；T8 式A/式B 的「必须红」负臂、T10/T10b/T10d/T10e、T12 六个参数硬门、T14 九条子进程 RC 门全在）。
- `p7b_udp_src --selftest` 见证行现取核号 **`PIN_CPU=1`**（`PIN_DEGRADED=none` / `PIN_ALLOWED_MASK=2` / `PIN_FREQ_START_KHZ=3893939`）—— ⚠️ 按纪律核号是"现取值"不是常量。
- 自检日志留在对端 `/tmp/p7b_biz/`（带本次独有 tag `20261013_214427`）。

## 5. ⛔ 只列不执行（留给烧板/测量轮）

以下**本轮一条都没执行**（含读侧见证），仅抄录现成配方，阶段 = 烧板轮开工时按序执行（`PEER_PW` 仅 `--sudo` 需要）：

**(a) 网络前置（每次重启/重来；`/32` 会被 NetworkManager 静默冲掉）** —— 出处 `p9_bench_restore_20261013/02_net.sh`：
```bash
# sudo:
ip link set enp1s0f1np1 up
ip addr add 192.168.100.100/32 dev enp1s0f1np1
ip route add 192.168.100.2/32 dev enp1s0f1np1 src 192.168.100.100
nmcli device set enp1s0f1np1 managed no
ethtool -C enp1s0f1np1 adaptive-rx off rx-usecs 0    # 长流/测速必须（全局 #68）
# 见证（现取）:
ip -br addr show enp1s0f1np1 ; ip route get 192.168.100.2   # 必须 dev enp1s0f1np1，不许走 WiFi
cat /sys/class/net/enp1s0f1np1/carrier ; nmcli -g GENERAL.STATE device show enp1s0f1np1
```

**(b) xdma 驱动 `insmod`（out-of-tree，重启即丢）** —— 出处 `p9_bench_restore_20261013/03_burn_pcie_id.sh:15,36`：
```bash
KO=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/xdma.ko
sudo insmod $KO ; lsmod | grep -w xdma ; ls /dev/xdma0_control /dev/xdma0_user
```
盘上在位已核：`xdma.ko` 3,275,104 B（root，2026-10-09 01:02）· `tools/reg_rw` 16,568 B 可执行（2026-09-28）。

**(c) PCIe 恢复（场景 C = POST 时厂商设计、只 1 BAR ⇒ 必须连根端口一起 remove+rescan）**：
```bash
echo 1 > /sys/bus/pci/devices/0000:00:1c.0/remove ; sleep 2 ; echo 1 > /sys/bus/pci/rescan ; sleep 6
# 判据: identify_bars 2 BARs（我们的）/ 1 BAR（厂商）; LnkSta x4 有救 / x0 没救
```
**本轮只读现状（见证起点，非命令）**：`lsmod | grep -w xdma` = **XDMA_NOT_LOADED** · `enp1s0f1np1` = **DOWN**、无 `/32`、`ip route get 192.168.100.2` 走 **wlp6s0（WiFi）**、`carrier = 0`、`Link detected: no`、`/dev/xdma*` 不存在 · `lspci -s 02:00.0` = **`Serial controller: Xilinx Corporation Device 9034`**（上电从 QSPI 起的厂商设计、PCIe 正常枚举 = 场景 C）。

## 6. ⛔ 未竟项（**不许当已答**）

1. **BUILD.md §3 表落后两代**：`p7b_tcp_src`（源+产物）· `p7b_udp_src`（源+产物）· `tcpreg_j6.sh`（脚本）。本轮**未改 BUILD.md**（派单禁改仓内文件）⇒ 引用该表时按本报告 §3 口径读。
2. ⚠️ **`0x24` 未烧未验** ⇒ 烧板轮注意：`run_win_hw.sh` 默认 **`EXPECT_BID=0x00000023`** ⇒ **烧 `0x24` 须显式 `EXPECT_BID=0x00000024`**（`P7B_LOOP_HANDOFF.md` §6-新块2 §A-4 已登记）。
3. **检查面只到"板外自检"**：`p7b_selftest.sh`(30 条) / `p7b_dualthread_selftest.sh`(48 条) / `p7b_lane8_selftest.sh`(42 条) **本轮未跑**（非派单要求；三件已部署 + `chmod +x`，可随时补跑）。
4. **本轮未取任何板级读数**（未烧板）；对端现态的"未观测"项（如 SFP 链路）**不写成"不存在"**。
5. 根 `README.md` 结构迁移在途（Kimi 组）—— 与本次重部署无关，按 `P7B_LOOP_HANDOFF.md` §6-新块2 §D-5 读。

*本件 = 重部署轮记录；**判据层的 PASS/FAIL 裁定权在判据所有者（用户）**。*
