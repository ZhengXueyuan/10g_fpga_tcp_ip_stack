# 台架恢复报告 —— 从"关机后"恢复到"可跑 0x23 位流板级测试"（2026-10-13 01:07–01:15）

> 轮次：**台架恢复轮**（TL 派单）。范围 = **只做部署与烧录**：不跑 xsim / 不跑综合 / 不改任何 RTL 或工具源码 / 不发业务流量。
> 配方权威源 = `_proj_10g/notes/P7B_LOOP_HANDOFF.md` **§6-新块 A（恢复顺序）** + `_proj_10g/notes/p7b_affinity/BUILD.md`（部署/编译口径）
> + `_proj_10g/notes/P7B_PCIE_RESCAN_RECOVERY.md` §7（场景 C）。
> **本件只报事实与读数；不下 PASS/FAIL 裁定、不写"已验证/已解决"式结语。**
> （落盘说明：REPORT.md 由 TL 代落盘 —— 平台拒写 .md 的已知间歇故障；正文逐字为恢复 agent 回传。）

---

## 0. 一句话

对端 `192.168.0.38` 的**台架已重部署**（29 源件 put + 9 产物对端现编，逐件 md5 与仓内现树相同）、**网络面已恢复**（`/32` + `/32` 路由走 `enp1s0f1np1`，`nmcli unmanaged`）、
**板卡已重烧 0x23 并过身份门**（`sha256=066a3923…3126` 双核 / `0x00=0x50360001` / `0x04=0x00000023` / `0x14C=0xffffffff` / 71 字 NFF=0），
**PCIe 已按场景 C 用根端口级 `remove`+`rescan` 恢复**（桥窗 1M→2M，`identify_bars = 2 BARs: config 1, user 0`），
**受控停流已解除**（`0x08=0`，板侧收发使能；NIC `CARRIER=1 / Link detected: yes`）。
**未做**：任何业务流量/镜像窗口功能测试（不在本轮派单范围；板子留在静止+发流使能态）、4 个较重的台架自检（只跑了 `p7b_selftest.sh` 与两个工具的 `--selftest`）。

---

## 1. 逐条：命令 + 原始输出摘录

原始记录件（逐字，全部在本目录）：`01_deploy_20261013_010743.txt` · `02_net_20261013_010924.txt` · `03_burn_20261013_011040.txt` · `04_ready_20261013_011356.txt` · `burn/BURN_stdout_copy_20261013_011308.txt`。
脚本（本目录新建的记录件）：`01_deploy.sh` · `02_net.sh` · `03_burn_pcie_id.sh` · `04_ready_witness.sh`。

### 1.1 对端可达性（判据 = TCP，不用 Windows `ping` 退出码）

```
$ python tools/peer_ssh.py "hostname; uname -r; uptime; systemctl is-active hw_server; ss -ltn | grep 3121"
a-MS-7850
7.0.0-38-generic
 01:06:02 up  2:34,  2 users,  load average: 0.20, 0.08, 0.02
---
active
LISTEN 0      16           0.0.0.0:3121      0.0.0.0:*
```
⇒ 对端在线、`hw_server` active 且监听 3121（systemd 拉起）；内核 7.0.0-38-generic。

### 1.2 重部署 `/tmp/p7b_biz/`（配方 = BUILD.md §2/§6；清单 = `p7b_env_restore_20261009/04_deploy.txt` 27 件 + `p7b_mir_dump.cpp`）

```
PUT_FAILS=0                       # 29 件 --put 全 OK
BUILD p7b_tcp_sink rc=0 errbytes=0 / p7b_tcp_src rc=0 / p7b_udp_src rc=0 / p7b_tcp_src_fix rc=0
BUILD p7b_tcp_sink_rate rc=0 / p7b_tcp_src_rate rc=0 / p7b_tcp_src_diag rc=0 / p7b_rate2_bench rc=0
BUILD p7b_mir_dump rc=0 errbytes=0
g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
PUT2_OK=8/8                       # /tmp/p9_board_0x23/（mir_dump/udp_src/snap/run_arm/stop_probe/final_state）
MIR_BUILD_RC=0  SRC_BUILD_RC=0 errbytes=300   # 300 B = 已知良性 -Wunused-function（p7b_affinity.h:851，与 2026-10-12 轮同款）
```

**编译口径（与派单描述不符，已核实）**：派单文字写"`g++ -O2`"，但同一派单指示"以 BUILD.md 为准"——BUILD.md §2 权威口径 = **`g++ -O3 -pthread -o <name> <name>.cpp`**（2026-10-09 用户逐字裁定"编译用 -O3"；R1 轮的 `-O2` 已废）。**本轮实按 `-O3 -pthread` 编译**（不加 `-std=`；g++13 默认 gnu++17）。

**md5 双核（对端 = 仓内现树，逐件相同）**——源件 13/13 相同；产物：

| 件 | 对端 md5 | 备注 |
|---|---|---|
| `p7b_tcp_sink` | `6d9b14f24725fa326ffe5b169f77e30f` | = BUILD.md §3 现树值 |
| `p7b_tcp_src` | `79be2a09024206b7c678dc13a3b9051d` | 源 `7a6191fc…`（树在 §3 表后前进过 ⇒ 与表值不同，属预期） |
| `p7b_udp_src` | `e0d4da5834cb95d67afb0cc523d1f92f` | ⭐ 与 2026-10-12 轮部署值**逐字节相同**（跨会话可复现） |
| `p7b_tcp_src_fix` | `d1ca0c288efe6723488e4c1a6960d1b5` | = §3 表值 |
| `p7b_tcp_sink_rate` | `ca6900fd54036be7fe1d337ca9ef83b8` | = §3 表值 |
| `p7b_tcp_src_rate` | `a76b2b4b1e44d6c9edcaa301d90aabcb` | = §3 表值 |
| `p7b_tcp_src_diag` | `430ed36ade4ec64ba6f5cb52e5f4f335` | = §3 表值（负对照臂） |
| `p7b_rate2_bench` | `1e956072f30a25f3e547e8c42107afb3` | = §3 表值 |
| `p7b_mir_dump` | `5ea97067cd90f93c8c47d1f272b04667` | ⭐ 与 2026-10-12 轮部署值**逐字节相同** |
| 源件 13/13（`p7b_affinity.h` `b0322279…` · `p7b_io.h` `62b1257d…` · `p7b_spsc.h` `3132db49…` · `p7b_pattern.h` `b2f2e962…` · `p7b_snap.sh` `6325658a0ff62cf6d26095e567b084bc` 等） | — | 对端 = 仓内现树逐字 |

**就位确认（派单点名件）**：`reg_rw`（对端盘上既有，未动）× `p7b_mir_dump`（`--help` 中 `| --stream [--stream-dev /dev/xdma0_c2h_0] [--buf-mb 128]` 逐字可见）× sink/src 族 8 产物 × `p7b_affinity.h` × `p7b_pattern.h` —— 全部在位。附加：`/tmp/p9_board_0x23/`（0x23 测试目录）= 8 件 + 2 产物现编；`run_arm.sh`/`stop_probe.sh`/`final_state.sh` md5 与仓内逐字相同。

**工具自检（板外）**：`./p7b_mir_dump --selftest` ⇒ `SELFTEST_RC=0 / MIR_SELFTEST PASS`（44 条 OK，含 T14 子进程负对照）；`./p7b_udp_src --selftest` ⇒ `SELFTEST_SRC_RC=0`；`bash p7b_selftest.sh 18899` ⇒ **`SELFTEST_SUMMARY PASS=30 FAIL=0` + `SELFTEST_OK`**。

### 1.3 对端网络前置（每次现取）

```
（配置）ip link set enp1s0f1np1 up; ip addr add 192.168.100.100/32 …; ip route add 192.168.100.2/32 … src 192.168.100.100; nmcli device set enp1s0f1np1 managed no ⇒ SUDO_CFG_DONE
（见证）192.168.100.2 dev enp1s0f1np1 src 192.168.100.100 uid 1000      ← 不走 WiFi
       192.168.100.2 dev enp1s0f1np1 scope link src 192.168.100.100
       nmcli = 10 (unmanaged)   irqbalance = inactive
（中断合并，按 #68 口径）ethtool -c enp1s0f1np1 ⇒ Adaptive RX: off / rx-usecs: 0   （SET_RC=0）
```
⚠️ 登记一处自伤：`02_net.sh` 读合并参数误用 `ethtool -C`（= **set**，无参数时静默无输出）⇒ 脚本内两处读数为空；**已就地用 `ethtool -c`（show）重取**（上行为重取读数）。**设置动作本身生效**（返回 0）。脚本未改（本轮"不改工具源码"；留原样以便对照）。

### 1.4 烧录 0x23（JTAG via `192.168.0.38:3121`，1 MHz；配方 = 既有 `run_program_tcpreg.bat` + `TCPREG_BIT`）

烧前 sha256 双核：
```
066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126  _proj_10g/notes/p9_build_0x23/wrapper_p4.bit
066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126  …/p9_bench_restore_20261013/burn/wrapper_p4_0x23.bit
SHA_WANT=066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126   （== 派单值 ✓）
LOCAL_BIT … size=15431261 mtime=2026-10-13 01:10:40 +0800
```
命令（`MSYS_NO_PATHCONV=1` + `cmd /c`；env 与 `cmd //c` 并用会互相抵消）：
```
TCPREG_BIT='D:\…\p9_bench_restore_20261013\burn\wrapper_p4_0x23.bit' cmd /c 'D:\…\p7b_biz_tcpreg\run_program_tcpreg.bat'
```
`burn/BURN_stdout_copy_20261013_011308.txt` 关键行逐字（**本次会话 01:10:48 起、01:13:08 止**；freshness `age=141s ≥ T0-5` 通过）：
```
TCPREG_BIT = D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_bench_restore_20261013\burn\wrapper_p4_0x23.bit
TCPREG_BIT_EXISTS = 1
TCPREG_BIT_MTIME = 1791825040
TCPREG_PROG device=xcku5p_0 freq=1MHz
INFO: [Labtools 27-3164] End of startup status: HIGH
program_hw_devices: Time (s): cpu = 00:02:01 ; elapsed = 00:02:04 .
TCPREG_PROG_DONE (检查上… 'End of startup status: HIGH')
INFO: [Common 17-206] Exiting Vivado at Tue Oct 13 01:13:08 2026...
```
⇒ `BURN_OK`（HIGH + DONE + 位流路径匹配 + stdout 新鲜 + 无 ABORT）。**旁证**：烧前 JTAG 探到的板载设计 = `5 ILA core(s)` + `1 MIG core(s)` ⇒ 与"QSPI 厂商设计"身份一致。

### 1.5 烧前现态（= 派单描述的"QSPI 厂商设计"，已核实）

```
lsmod ⇒ XDMA_NOT_LOADED（首次 insmod 前）
lspci 02:00.0 ⇒ Region 0: Memory at f7a00000 [size=64K]（只有 1 个 BAR）；LnkSta: Speed 5GT/s (downgraded), Width x4
桥窗 00:1c.0 ⇒ Memory behind bridge: f7a00000-f7afffff [size=1M]
insmod /home/a/xdma_test/…/xdma/xdma.ko（vermagic=7.0.0-38-generic == 运行内核）⇒ INSMOD_RC=0
dmesg: identify_bars: 1 BARs: config 0, user -1, bypass -1. / probe_one: 0000:02:00.0 xdma0 … usr 16, ch 1,1.
厂商设计 control BAR 读: reg_rw /dev/xdma0_control 0x0000 w ⇒ 0x1fc00006
```
⇒ **场景 C 成立**（POST 时枚举的是 1-BAR 厂商设计 ⇒ 父桥窗按 1M 定死），与派单描述一致。

### 1.6 PCIe 恢复（场景 C ⇒ 根端口级 `remove`+`rescan`）

```
桥窗 before: f7a00000-f7afffff [size=1M]
echo 1 > /sys/bus/pci/devices/0000:00:1c.0/remove; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 6
桥窗 after : df200000-df3fffff [size=2M]        ← 窗重算
Region 0: Memory at df200000 [size=1M] / Region 1: Memory at df300000 [size=64K]
LnkSta: Speed 5GT/s (downgraded), Width x4
/dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 全部出现
dmesg: map_bars: config bar 1, pos 1. / identify_bars: 2 BARs: config 1, user 0, bypass -1.   ← 判别式命中"我们的设计"
```
（无需重启对端机；`LnkSta` 全程 `x4` = "有救"分支。）

### 1.7 身份门（板侧读数原文）

```
user 0x00 = 0x50360001   （MAGIC）
user 0x04 = 0x00000023   （BID —— 派单判据值）
user 0x14 = 0xdeadbeef   （MARKER）
user 0x14C = 0xffffffff  （未实现地址 ⇒ SLVERR；71 字几何负对照）
user 0x08 = 0x00000000   （SCRATCH/TX_DIS 门）
user 0x144 = 0x00000000  （MIR_CTRL）  user 0x148 = 0x00000000（MIR_DMA_CNT）  user 0x0C = 0x918cb7fa（通道活性 marker）
NW=71 EXPECT_BID=0x00000023 bash /tmp/p7b_biz/p7b_snap.sh id
  ID_MAGIC 0x50360001 / ID_BID 0x00000023 / ID_MARKER 0xdeadbeef / ID_UNIMPL 0xffffffff → ID_OK（ID_RC=0）
71 字逐字扫: WINDOW_SCAN_NFF=0
```
⚠️ 两处口径差（如实登记，非故障）：① 派单写 `reg_rw … 0x04 r`；本工程既有口径第 3 参 = **位宽**（`w`）。**两种都实测**（`r` 落 reg_rw.c default 分支 = word）：`0x04 r ⇒ 0x00000023`、`0x04 w ⇒ 0x00000023`、`0x00 r ⇒ 0x50360001`，逐字相同。② "快照 71 字"读法 = 上表 `0x14C` + NFF=0 + `id` 门（三项全过）。

### 1.8 解除受控停流 + 链路见证

```
SCRATCH_0x08(before)=0x00000000   ← ⭐ 新配置自清 SCRATCH/TX_DIS 锁存（与 HANDOFF"重烧后 0x08 自读即 0"一致）
reg_rw /dev/xdma0_user 0x08 w 0x0  ← 按派单执行（幂等）
SCRATCH_0x08(after) =0x00000000
（8 s 后）NIC_CARRIER=1 / OPERSTATE=up / Speed: 10000Mb/s / Link detected: yes
ip route get 192.168.100.2 ⇒ dev enp1s0f1np1 src 192.168.100.100
```

### 1.9 就绪态活体见证（只读 + 快照触发；**未发任何业务流量**）

`p7b_snap.sh pair`（两点各自自证 `gen` 恰 +1）：
```
PAIR LIVE_W5  W5  gmii_free_FE      A=0xcf7118c1 (gen=1) B=0xe22d47cc (gen=2)
PAIR LIVE_W24 W24 dp_free_DP        A=0xe26c2f34 (gen=3) B=0xf5276b5f (gen=4)
PAIR LIVE_W43 W43 mtx_stat_tx_words A=0xf533d0a5 (gen=5) B=0x07eef890 (gen=6)
```
随后一次 `snap`（gen=7）：`W5=0x17180589 · W20 mac_tx_frames=0x00000004 · W24=0x17317af9 · W43=0x1717bd85 · W11=0 · W13=0 · W70=0`（`nff=0`）。
**NIC 静置窗**：2 s 窗 `port_rx 1448→1512 B / 5→6 pkt`；10 s 窗 `port_rx 1576→1768 B / 7→10 pkt`；`port_tx` 两窗静止（91 B / 1 pkt）。
⇒ 存在**约 64 B × ~0.3 帧/s 的背景小流量**（未定位；量级上不构成数据流）。如实登记，不猜机理。

### 1.10 环境台账（运行时改动，可回退）

| # | 项 | 现值 | 回退 |
|---|---|---|---|
| 1 | `/tmp/p7b_biz/`（46 件）+ `/tmp/p9_board_0x23/` | 本轮新建 | `rm -rf` |
| 2 | xdma 驱动 | 已 insmod（out-of-tree，vermagic 7.0.0-38-generic） | 重启即丢；`rmmod xdma` |
| 3 | `enp1s0f1np1` | `/32 192.168.100.100` + `/32` 路由（src）+ unmanaged | `ip addr del` / `nmcli device set … managed yes` |
| 4 | 中断合并 | `Adaptive RX: off / rx-usecs: 0` | `ethtool -C … adaptive-rx on rx-usecs 60`（出厂默认；回退须登记） |
| 5 | PCIe | 根端口 `00:1c.0` remove+rescan ×1（桥窗 2M 现役） | 即现役所需 |
| 6 | 板卡 | JTAG 易失烧录 0x23（**未碰 QSPI**） | 断电即失 |
| 7 | 其它 | `tc qdisc = mq`（默认）/ `irqbalance inactive` / 无残留进程 / 未改 sysctl | — |
| 8 | 仓库 | 未改任何 RTL/工具源码；唯一被改写的 **tracked** 文件 = `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt`（烧录 launcher 输出目标，按设计被本次覆盖；副本已归档于本目录 `burn/`） | 该文件即烧录日志，可在提交时更新或还原 |

---

## 2. 与派单描述的核实结果（含一处修正）

| 派单描述 | 核实结果 |
|---|---|
| "板上现在跑的是 QSPI 厂商设计" | ✅ 成立（1 BAR / `1 BARs: config 0, user -1` / 5 ILA + 1 MIG / control=0x1fc00006） |
| "本次属场景 C ⇒ 连根端口一起 remove+rescan" | ✅ 适用（桥窗实测 1M）；根端口级一次成功（窗→2M） |
| "烧前核本地 sha256 == `066a3923…3126`" | ✅ 双核命中（源 + 副本） |
| "身份门 0x04==0x23 / 0x00==0x50360001 / 71 字 0x14C" | ✅ 全中（另加 `0x14=deadbeef`、`id` 门 ID_OK、NFF=0） |
| "用 `g++ -O2` 编译（含 `-pthread`）" | ⚠️ **未按此执行** —— 同派单指示"以 BUILD.md 为准"，BUILD.md §2 权威口径 = **`-O3 -pthread`**（2026-10-09 用户裁定）。**本轮用 `-O3 -pthread`**。引用旧速率读数须标 `-O2` 口径（BUILD.md §4b） |
| "reg_rw … 0x04 **r**" | ✅ `r` 形式可用（default→word，读数与 `w` 逐字相同）；既有口径写 `w` |
| "解除受控停流 `0x08 w 0x0`" | ✅ 已执行；实测**新烧后 `0x08` 自读即 0** ⇒ 本次为幂等 |

---

## 3. 未做 / 未测 / 未定位（不许当已做）

1. **未发任何业务流量**（UDP src / mir_dump / TCP 均未跑）——按派单范围只做部署+烧录+身份；板子留在**静止 + 发流使能**态。⇒ **0x23 的镜像窗口功能（`--stream`/D4/停流探针）本轮零验证**。
2. **4 个较重的台架自检未跑**：`p7b_dualthread_selftest.sh` / `p7b_lane8_selftest.sh` / `aff_selftest.sh` / `pcap_off_dryrun.sh`（本轮只跑了 `p7b_selftest.sh` 与 `mir_dump`/`udp_src --selftest`）。
3. **背景小流量未定位**（~64 B × ~0.3 帧/s，NIC rx 侧；板侧 W20 静止）——只报读数。
4. **xdma 驱动为会话态**：重启对端即丢（重编/insmod 配方 = `p7b_bench/ACCEPT_FIRST_RUN.md` §0-1）。
5. **`02_net.sh` 的 `ethtool -C` 读法自伤**（见 1.3）：脚本内两处读数为空，已用 `-c` 重取补证；脚本留原样。
6. 板子现态（下一轮开工先核）：**`0x23` / `0x08=0` / carrier=1 / `MIR_CTRL=0` / `MIR_DMA_CNT=0` / 无残留进程**；快照几何 **71 字 / 未实现 `0x14C`**；取数器默认值 = `NW=71 / EXPECT_BID=0x00000023`。
7. 本机与对端**未关机**；若再关机，重做流程 = 本目录 01→02→03→04（03 自动判定烧前态并重取 sha256）。
8. **REPORT.md 未落盘**（平台拒写 .md —— 已知间歇故障）⇒ 本件全文由 TL 代落盘。

---

*本件 = 台架恢复轮记录；**判据层的 PASS/FAIL 裁定权在判据所有者（用户）**。所有读数均为本会话现场取回，原始件见本目录（含 `burn/BURN_stdout_copy_20261013_011308.txt` 与四个 phase 日志）。*
