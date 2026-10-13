# 独立复算报告 — p9 板级轮 0x24（Kimi 跨组验证）

- 任务：bridge 任务 t_9c2a8dab503b（对 Claude 组 0x24 板级轮读数做独立复算）
- 被验件：`_proj_10g/notes/p9_board_0x24_20261013/REPORT.md`（顶部口径声明已读）
- 复算人/时间：Kimi 组 / 2026-10-13 22:58 +0800
- 方法：**自写解析器/LFSR/比较器**（`kx_*.py`，全部留档），⛔ 未 import/复跑对方 `_tools/` 任何脚本；只读对方既有文件；本目录之外零写入
- 纪律：本件**不下 PASS/FAIL 裁定**；「未观测到」≠「不存在」
- 复算环境：`/c/Users/zhxue/anaconda3/python.exe`（Windows Git Bash）

| 产物 | 说明 |
|---|---|
| `kx_stats.py / .out` | ① STATS/WIN 主读数复算（中位/均值/Σ/三口径一致/双口径窗长/式B 21-21/基线降幅） |
| `kx_holes.py / .out` | ② 洞结构独立复算（自写 xorshift64 LFSR + GF(2) 矩阵跳跃 + 自写解析器） |
| `kx_d4.py / .out` | ③ D4 停流链独立复算（含自写 LFSR 复算 TAIL 期望） |
| `kx_peergate.out` | 可选板级复跑的身份门核验记录（含阻断项证据） |

---

## ① URAM 收益主读数复算

**方法**：自写解析器分别解析 `runs/STATS_SINGLE.txt`、`runs/STATS_FOURSRC.txt`（每窗 dW70/式B/式A/reads/w_read/w_src），并从 6 个 `WIN_*.txt` 原始窗协议中**独立重取** MIR_STREAM_ACCT、pre/post 快照 W70 差分、式A/式B、TOOL_ARGS、READLOG 末行 t、TE−TS，三口径互相验证。原始命令：
`PYTHONIOENCODING=utf-8 python kx_stats.py`（输出 `kx_stats.out`）。

### 复算值 vs 报告值

| 读数 | 报告值（REPORT §5b 表） | 本复算值 | 判定 |
|---|---|---|---|
| 单源 ΣdW70 | 36.85 MB（36,845,912 B） | 36,845,912 B = 36.85 MB（十进制）= 35.14 MiB | 一致 |
| 单源中位 | 2.41 MB（2,414,504 B） | 2,414,504 B（第 8 窗 S8） | 一致 |
| 单源均值 | 3.35 MB | 3,349,628.4 B = 3.35 MB | 一致 |
| 单源极差 | 0.58–9.81 MB | 575,400–9,809,832 B = 0.58–9.81 MB | 一致 |
| 4 源 ΣdW70 | 62.27 MB（62,267,240 B） | 62,267,240 B = 62.27 MB | 一致 |
| 4 源中位 | 5.99 MB（5,989,288 B） | 5,989,288 B | 一致 |
| 4 源均值 | 6.23 MB | 6,226,724.0 B = 6.23 MB | 一致 |
| 4 源极差 | 4.40–8.25 MB | 4,402,728–8,254,120 B | 一致 |
| 逐窗 dW70 三口径 | STATS = ACCT = 快照差分 | 21/21 窗全等（逐窗表见 kx_stats.out） | 一致 |
| 单源窗长 Σw_read / Σw_src | 39.5 s / 32.6 s（≥30） | 39.54 s / 32.61 s | 一致，双口径 ≥30 ✓ |
| 4 源窗长 Σw_read / Σw_src | 38.0 s / 31.5 s（≥30） | 37.96 s / 31.54 s | 一致，双口径 ≥30 ✓ |
| 式B 终态 | 21/21 窗 res=0 closed_b=1 | 21/21（11/11 + 10/10） | 一致 |
| 每窗 TOOL_ARGS | 主轮构型串 | 21/21 窗逐字等于期望串 | 一致 |
| 工具/源钉扎 | TOOL_MD5 7cebded7…；PIN_CPU {1,4,7} | 21 窗 TOOL_MD5 全 7cebded7…；主臂窗 PIN_CPU ∈ {4,7}（P2A/D4 用 7；{1:×1} 未在主臂出现，与报告脚注不冲突） | 一致 |

### 基线降幅验证（基线 5.46/8.93 MB 出处现读核对）

基线出处 = `_proj_10g/notes/p9_hostread_20261013/REPORT.md` §4 表（第 185/187 行）：单源 after=`5.46 MB`（精确 5,459,912 B，第 189 行）；4 源 after=`8.93 MB`。✓ 与任务书给定一致。

| 臂 | 报告降幅 | 本复算 | 判定 |
|---|---|---|---|
| 单源中位 vs 5.46 MB | −56% | 2.4145 MB → **−55.8%**（对 5,459,912 B 精确 −55.78%） | 一致（四舍五入） |
| 单源均值 | −39% | 3.3496 MB → −38.7% | 一致 |
| 4 源中位 vs 8.93 MB | −33% | 5.9893 MB → **−32.9%** | 一致 |
| 4 源均值 | −30% | 6.2267 MB → −30.3% | 一致 |

**偏差分析**：四条降幅全部复现（差异仅来自报告取整）。STATS 文件内 "MB" 列实为 MiB（如 S0 2.61 = 2,740,136/2²⁰），REPORT 已声明此口径，复算确认。

**附带核到的背景见证**：FINAL_STATE ① NIC `1074175892364−1071720419586 = 2,455,472,778 B / 2 s = 9.82 Gbps`、帧 `1,617,571/2 s = 808,786 fps` —— 与 REPORT §5b「板 TX 侧 9.5 Gbps 泛洪背景」量级一致。

---

## ② 洞结构复核（自写 LFSR + 自写解析器，⛔ 未跑对方 ANALYZE/hole_finder 脚本）

**方法**：按 `p7b_pattern.h` 语义**自写** xorshift64（SEED=0x9E3779B97F4A7C15；先取 s[31:24] 后推进）+ GF(2) 64×64 矩阵二进制幂跳跃（大偏移必用）；自检三向量（off0..15 / off1460..67 / state@100）全过后再对账。`capd_*.bin` 样件**本仓俱全**（9 件，总 5.6 MB），无需降格为「有限复核」。原始命令：`python kx_holes.py`（`kx_holes.out`）。

### 复算值 vs 报告值

| 结构主张 | 报告值 | 本复算值 | 判定 |
|---|---|---|---|
| 头部 [0,64 KiB) | 0 失配 | fm=−1 mism=0 | 一致 |
| 首洞位置 | 绝对 4,229,208 | sliceA 洞前区 [3,180,632, 4,229,208) 0 失配；首失配恰在 4,229,208 | 一致 |
| 首洞 L | 39,608 B（16B 窗口唯一候选 + 64 KiB 验证） | 16B 窗口候选**唯一 [39,608]**；64 KiB 验证过；洞后 3,145,728 B 位移后 0 失配 | 一致 |
| 洞边界 16B dump | GOT/EXP 六行逐字 | 六行 hex **逐字相同**（kx_holes.out 对照 ANALYZE_CAPD24.txt 第 12–16 行） | 一致 |
| 洞相位 | ≡ 4 MiB+34,904（4 点） | 4,229,208 = 1×4MiB+34,904；16,812,120 = 4×4MiB+34,904；67,143,768 = 16×4MiB+34,904；201,361,496 = 48×4MiB+34,904 | 一致（4/4） |
| 16 MiB 探针 | 洞@16,812,120（L 探针内量不出） | S=61,992 下洞前 34,904 B 全净、首失配恰在 rel 34,904 | 一致 |
| 16 MiB 宽探针 | 另一洞 L=2,368 | 洞前 4,904 B 全净；洞后 S=64,360 全净 ⇒ L=2,368 复现 | 一致 |
| 64 MiB 探针 | 洞@67,143,768 | S=171,944 下首失配恰 rel 34,904 | 一致 |
| 128 MiB 探针 | S=372,648 全净 | S=372,648 全片 0 失配 | 一致 |
| 192 MiB 探针 | 洞@201,361,496 | S=604,840 下首失配恰 rel 34,904 | 一致 |
| 80 MiB 区 | 64 KiB 探针全净 | p80M1（@85,983,232=82 MiB）S=228,632 全片 0 失配、0 洞 | 一致 |
| 尾区 | S(251 MiB)=759,488 ⇒ ΔW70−10,216 | tail @263,192,576 用 S=759,488 对账 0 失配；错值 39,608 对照即 fm=0 | 一致 |
| 位移方向 | （隐含） | 本复算实测方向 = 抓取位置 c ↔ 图案位置 OFF+c+S（洞=删除 ⇒ 内容左移） | 同报告结论 |

**偏差分析**：全部复现，无偏差。注：全量 `mir_CAPD24.bin`（264,241,152 B，md5 `d348cd49…`）留对端 `/tmp/p9_board_0x24/` **未取回**；本复算覆盖其 9 个抓样区段（头/切片/尾/5 探针/宽探针）≈ 5.6 MB，另加 PHASE 4 点 + S 曲线 5 点共 13 个独立锚点，全部命中。

---

## ③ D4 停流链独立复算

**方法**：自写比较器解析 `ARM_D4_CHAIN_*.txt`（三跑）与 `STOP_PROBE_S5D4_*.txt`；式A/式B 用取自 ACCT 的 pc/taken/dW70/K **独立重算**；TAIL 期望用**自写 LFSR** 按 `mir(OFF_S5D4+K, 8)^0xA5` 复算并与 `D4_EXPECT_HEX.txt`、探针实际读数逐字节比。原始命令：`python kx_d4.py`（`kx_d4.out`）。

| 跑 | 报告值（pc/taken/式A/式B） | 本复算 | 判定 |
|---|---|---|---|
| S3D4 | 1,048,576 / 1,048,584 / 8 / 0 | pc=1,048,576 taken=1,048,584；式A 复算=8（closed_a=1）；式B 复算=0（closed_b=1）；K=1,048,584（--k-bytes）；VERIFY rc=0 fm=−1 | 一致 |
| S4D4 | 1,048,576 / 1,048,576 / 0 / 0 | 同上全对（clr 起测 ⇒ 无残拍、式A=0） | 一致 |
| S5D4 | 1,048,576 / 1,048,584 / 8 / 0 | 同上全对 | 一致 |
| 停流探针 | `dma_from_device -s 8` ⇒ RC=0 ELAPSED=0；TAIL 8 B 逐字节 MATCH | MIR_CTRL 0xb→写 0x8→读回 0xa；MIR_STATUS 0x00240000→0x00200000；DMA_CNT 0x00040002 不变；TAIL `23b90e8ca65bd320` = 文件 EXPECT = 本复算 LFSR 值 | 一致（逐字节 MATCH 复现） |

**偏差分析**：无偏差。CTRL 读回 0xa = 所写 0x8 + bit1 读侧翻转（报告 §5d 口径），非功能位。

---

## ④ sha256 转抄判定复核

**方法**：Python hashlib 独立实算 + 逐字节 cmp + 全仓文本 grep 变体。原始命令与输出：

```
$ python -c "hashlib.sha256(...)"
burn/wrapper_p4_0x24.bit : e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db
impl_1/wrapper_p4.bit    : e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db
identical: True   sizes: 15,431,261 / 15,431,261
$ python SHA256SUMS 自核: ok=56 bad=0
```

| 举证环节 | 报告主张 | 本复算 | 判定 |
|---|---|---|---|
| 盘上实算 | …e50**a**7c3…（程序化） | hashlib 实算 = e3b0…c92e50**a**7c3b0abadf1db ✓ | 一致 |
| SHA256SUMS.txt | 同值 | 56/56 条自核全过（含位流行 `*./burn/wrapper_p4_0x24.bit`） | 一致 |
| Vivado impl_1 原件 | 逐字节同 | `vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4.bit` sha 全同、mtime 2026-10-13 08:57:04.082 +0800 ✓（= 报告值）；`.bit` 头 `Version=2025.2;SW_CRC=05997278;…2026/10/13…08:57`（BURN 日志第 10 行） | 一致 |
| 四件散文就地订正 | REPORT:107 / PROGRESS:23 / HANDOFF:374 / 台账:928 的散文值「已订正」 | 现读：四件**主值均为 e50a7c3**，各带 ⚠️ 订正注（内引旧笔误 e50e7c3）；`e` 变体现仅存于：LEDGER:976 订正注、BURN 日志 DISPATCH_WANT_PROSE 登记行、burn_0x24.sh 注释+DISPATCH_HE 行 —— 全部为**登记/注记**语境 | 一致 |
| 转抄性质 | 1 字符 e↔a（idx 50），不可能是文件替换 | 复算确认：盘上件=impl_1 原件=SHA256SUMS 三源同值；散文侧 4 件同带订正注 | 与报告推断一致（最终裁定权在判据所有者） |

---

## ⑤ 身份门 / 收尾态三方对账（burn/ ↔ ENV_PRE ↔ FINAL_STATE）

**方法**：逐字读 `burn/BURN_0x24_20261013_220442.txt`（GBK 容错解码，2 处 U+FFFD 在原日志注释性文字、关键行完整）、`runs/ENV_PRE_*`、`runs/FINAL_STATE_*`；epoch 换算独立复核。

| 对账项 | burn（烧录时） | ENV_PRE（主臂前） | FINAL_STATE（收尾） | 判定 |
|---|---|---|---|---|
| BID=0x24 | 身份门 §5：BID_0x04=0x00000024、ID_OK/ID_RC=0、WINDOW_SCAN_NFF=0、MAGIC 0x50360001、MARKER 0xdeadbeef、0x14C=0xffffffff | （环境件不含 BID，时间戳 1791900489.65 > BURN_END 1791900449.20 ⇒ 时序衔接） | BID_0x04=0x00000024、MAGIC/MARKER/UNIMPL 同 | 三方一致；且 21 主臂窗 + CAPD24 + D4 链 MIR_ID 行 bid=00000024 全程在位 |
| 烧录前后 sha | 烧前：p9_build_0x24/wrapper_p4.bit 与 IMPL1_ORIG_SHA 均 a 变体、SHA_OK；烧后：burn/wrapper_p4_0x24.bit 同值 | — | ⑧ /tmp/p7b_biz 四件 md5 逐字未变（含 p7b_mir_dump 7cebded7…） | 一致 |
| 烧录五判据 | End of startup status: HIGH ✓；TCPREG_PROG_DONE 非注释行 ✓；路径含 wrapper_p4_0x24.bit ✓；stdout mtime 1791900427 ≥ T0 1791900289（age=138 s）✓；无 TCPREG-ABORT ✓ → BURN_OK | — | — | 逐字命中 |
| 收尾停流态 | 烧后 SCRATCH 0x08=0（解停流态） | CARRIER=1 / /32 / route dev enp1s0f1np1 / adaptive-rx off rx-usecs 0 / nmcli unmanaged(10) 全中 | 0x08=0x2（受控停流）、MIR_CTRL=0x2（功能位全 0）、MIR_STATUS=0x00200000、DMA_CNT=0x00040002、停流后 CARRIER=0、NIC 两读逐字冻结（1075029181146/708187952）、PROC_SCAN_DONE | 一致 |
| 计数链连续性 | — | — | W70 自 CAPD24_post 0x05f41768 → D4 三跑 → FINAL_STATE 未变（主臂后零再丢）；W11 逐窗接续 0x5026f800→…→0x5056f810 | 一致（session 内文件同源） |

**偏差分析**：无偏差。两处如实注记：①「无残留进程」仅留 PROC_SCAN_DONE 标记，原始 ps 输出未随档（覆盖注记，非矛盾）；② BURN 日志第 47–48 行注释性文字含 2 个不可解码字节（U+FFFD），TCPREG_PROG_DONE 行本体完整。

---

## 可选板级复跑（1–2 窗）：**未执行**（登记）

门核验结果与阻断项的完整原始记录见 `kx_peergate.out`。摘要：

- **通过**：ping 87 ms ✓；`/tmp/p7b_biz/p7b_mir_dump` md5=7cebded7… ✓；`p7b_udp_src` e0d4da58… ✓；`p7b_snap.sh` 双副本 97c66382… ✓；无残留 p7b 进程 ✓。
- **阻断**：板上身份读取/解停流/收尾停流/跑 dump 全部需 root（`/dev/xdma0_user`、`/dev/xdma0_c2h_0` 均 `crw------- root`；`p7b_snap.sh` 第 49 行自述「需要 root … 用 tools/peer_ssh.py --sudo 跑」）；本会话 **PEER_PW 不存在**（`sudo -n` ⇒ 需密码；项目纪律口令不落盘）。
- **处置**：按纪律「身份门不过 ⇒ 立即停手登记，不烧不跑」——未跑、未烧、未动 QSPI、未改板任何态（对端全程只读命令）。
- **覆盖面声明**：①–⑤ 的量化主张均由盘上原始件独立复算覆盖；复跑仅额外提供「同时段二次抽样」的时间稳定性见证 —— 本轮缺失，如实登记；若后续补跑，构型与见证要求已录于 `kx_peergate.out`。

---

## 发现清单（按严重度；本组不下裁定，建议仅为参考）

| # | 严重度 | 位置 | 发现 | 证据 | 建议 |
|---|---|---|---|---|---|
| F1 | 低（文档计数） | `p9_board_0x24_20261013/REPORT.md:143`（§7 头部） | 「`_tools/` 9 件」与盘上实数不符：实为 **10 件**（`ls _tools/ | wc -l` = 10；SHA256SUMS 56 = 10+42+3+1 自洽） | 本复算 `wc -l` + SHA256SUMS 行计数 | 改「10 件」（差的那件应为 `pattern_jump.py` 库） |
| F2 | 低（口径注记） | `runs/ANALYZE_CAPD24*.txt` | 对方 `fm_and_count` 的 mism 计 **bit**（`x.bit_count()`），非字节：尾区 ⑧ 的 mism=4,193,473 **> 片长 1,048,576 B**，按字节读会误判为不可能值；0/nonzero 判定不受影响 | 对方 `capd_analyze.py:27`（只读）vs 本复算字节口径 | 报告或脚本注记「mism = bit 计数」 |
| F3 | 低（留档覆盖） | `runs/FINAL_STATE_*.txt:42-43` | 「无残留进程」仅 PROC_SCAN_DONE 标记，无原始 ps 输出 | 逐字读档 | 下轮把 ps 原始块一并落盘 |
| F4 | 极低（文件卫生） | `burn/BURN_0x24_20261013_220442.txt:47-48` | 原日志含 2 个非 UTF-8 字节（读为 U+FFFD，在注释性文字；关键行完整） | Python errors='replace' 定位 2991/3047 | 无需处理；知悉即可 |

**零发现于**：主读数（①）、洞结构（②）、D4 链（③）、sha256 举证链（④）、身份/收尾对账（⑤）——五条的复算值与报告值全部一致（偏差分析见各节）。

---

## 覆盖面声明

- 已覆盖：§5a 干净抓取（附带：mir_P2A/mir_P2B 对本组 LFSR **逐字节全等**，超出必做范围）、§5b 主臂 21 窗全量、§5c 洞结构 13 锚点（全量样件 9 区段；全量 bin 在对端未取回——已登记）、§5d D4 链全量、§0–§2 烧录/身份/环境、sha256 全链、收尾态。
- 未覆盖：READLOG 派生辅助量（entry 率/idle/O 系列，报告自身已标「辅助口径（含 kimi B-1 竞态）」，本组未独立重导）；板级复跑（见上，权限阻断）；全量 264 MB bin 逐字节（仅样件区段，如上）。

*本件为独立复算登记，不下 PASS/FAIL 裁定；「未观测到」不写「不存在」。*
