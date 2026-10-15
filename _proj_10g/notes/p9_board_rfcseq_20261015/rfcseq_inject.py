#!/usr/bin/env python3
# rfcseq_inject.py -- 板级轮 B2 (RFC seq 修复注入 A/B) 的对端侧注入器 + 见证器
#
#   底本 = `_proj_10g/notes/p7b_persist_board_20261011/_tools/stall_probe.py`
#           (md5 2274c15975e78307dc9d9b286da03ffb; 设计件 P7B_BUILDG_RFC_SEQ_DESIGN_v3r3.md
#            附录 A 逐字指定 = "板测注入器原型 (§7.2)")
#   帧构造 / csum / AF_INET+SOCK_RAW+IPPROTO_RAW+IP_HDRINCL 发送路径 / doff=5 /
#   POST_INJECT_BOARD_FRAME 见证风格 = 自原型**逐字保留**。
#
#   本件相对原型的新增 (逐条回指 §7.2, **无自创配方**):
#     (1) seq 参数化 = §7.2 两条配方 (原型 seq 写死 `isn+1` = 等价域, 构造不出目标向);
#     (2) 嗅探方向取反 = 取【板→对端】帧的 ack 字段 = **板的 rcv_nxt** (原型取的是对端自己的 ack);
#     (3) 分歧域自证 (设计件 §8.2-R8: 注入前先自证 D ∉ [-2^31, 2^31-1] 再上线);
#     (4) 安静门 (注入前等无板侧帧的空档) + 目标注入后逐帧见证 + 逐次 OBS_SUMMARY;
#     (5) 注入帧 IP-ID 打标 0xA5C0+i (自捕帧输出时排除, 防污染 peer_snd_nxt 估计);
#     (6) 阳性对照 = dup 生命探针 (seq = rcv_nxt - 1: 两版本 ackresp 同为 1 ⇒ 都应回 ACK);
#     (7) `--stop-pid`: 由本进程 SIGSTOP 源头进程 (在嗅探已拿到 rcv_nxt 之后) —— 消除
#         "先停后启嗅探 ⇒ 发现窗错过" 的竞态。
#
#   用法 (对端, root): python3 rfcseq_inject.py --stop-pid <PID> [--quiet 0.8] [--obs 0.6]
#   退出码: 0 = 全部阶段完成; 3 = 目标向不可行 (rcv_nxt >= 2^31, §7.2 可行性注 => 重开连接);
#           4 = 发现失败; 5 = 其他硬失败 (含分歧域自证失败)
#
#   ⚠️ 本件只给读数与形态; PASS/FAIL 裁定权在用户/判据所有者。
import os, signal, socket, struct, sys, time, argparse

IFACE = "enp1s0f1np1"
BOARD_IP = "192.168.100.2"
MY_IP = "192.168.100.100"
PORT = 8080
WIN = 65535
ID_BASE = 0xA5C0          # 注入帧 IP-ID 标记 (0xA5C0 + i)

def csum(data):           # 逐字保留 (原型)
    if len(data) % 2:
        data += b"\x00"
    s = 0
    for i in range(0, len(data), 2):
        s += (data[i] << 8) + data[i+1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF

def inject(lport, seq, ack, win, ident, data=b"", flags_extra=0):
    """逐字保留原型 (IPPROTO_RAW + IP_HDRINCL ⇒ 内核算 L2); 仅 seq/ident 由调用方给。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    src = socket.inet_aton(MY_IP); dst = socket.inet_aton(BOARD_IP)
    tcp = struct.pack(">HHIIHHHH", lport, PORT, seq, ack, (5 << 12) | 0x10 | flags_extra, win, 0, 0)
    payload = data
    pseudo = src + dst + struct.pack(">BBH", 0, 6, len(tcp) + len(payload))
    tc = csum(pseudo + tcp + payload)
    tcp = tcp[:16] + struct.pack(">H", tc) + tcp[18:]
    tot = 20 + len(tcp) + len(payload)
    ip = struct.pack(">BBHHHBBH4s4s", 0x45, 0, tot, ident & 0xFFFF, 0x4000, 64, 6, 0, src, dst)
    ip = ip[:10] + struct.pack(">H", csum(ip)) + ip[12:]
    s.sendto(ip + tcp + payload, (BOARD_IP, 0))
    s.close()

def parse(pkt):
    if len(pkt) < 14 + 20 + 20:
        return None
    if pkt[12:14] != b"\x08\x00":
        return None
    ip = pkt[14:]
    ihl = (ip[0] & 0xF) * 4
    if ip[9] != 6:
        return None
    if len(ip) < ihl + 20:
        return None
    src = socket.inet_ntoa(ip[12:16]); dst = socket.inet_ntoa(ip[16:20])
    tcp = ip[ihl:]
    sport, dport, seq, ack, off_flags = struct.unpack(">HHIIH", tcp[:14])
    flags = off_flags & 0x1FF
    doff = (off_flags >> 12) & 0xF
    win = struct.unpack(">H", tcp[14:16])[0]
    tot = struct.unpack(">H", ip[2:4])[0]
    plen = tot - ihl - doff * 4
    ident = struct.unpack(">H", ip[4:6])[0]
    return dict(src=src, dst=dst, sport=sport, dport=dport, seq=seq, ack=ack,
                flags=flags, win=win, plen=plen, ident=ident)

FLAG_S = 0x02; FLAG_A = 0x10; FLAG_F = 0x01; FLAG_R = 0x04

def flagstr(f):
    s = ""
    s += "S" if f & FLAG_S else ""
    s += "A" if f & FLAG_A else ""
    s += "F" if f & FLAG_F else ""
    s += "R" if f & FLAG_R else ""
    return s or "-"

class Sniffer:
    def __init__(self, iface):
        self.s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003))
        self.s.bind((iface, 0))
        self.s.settimeout(0.05)

    def drain(self, dur, on_pkt):
        t_end = time.time() + dur
        while True:
            t = time.time()
            if t >= t_end:
                return
            self.s.settimeout(min(0.05, max(0.001, t_end - t)))
            try:
                pkt = self.s.recv(65536)
            except socket.timeout:
                continue
            p = parse(pkt)
            if p is None:
                continue
            on_pkt(p, time.time())

    def close(self):
        try: self.s.close()
        except Exception: pass

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stop-pid", type=int, default=0)     # SIGSTOP 该 PID (源头进程)
    ap.add_argument("--quiet", type=float, default=0.8)    # 安静门: 需连续无板侧帧的空档 (秒)
    ap.add_argument("--quiet-max", type=float, default=8.0)
    ap.add_argument("--stop-settle", type=float, default=1.2)
    ap.add_argument("--watch", type=float, default=3.0)    # STOP 前的观测窗上限 (秒)
    ap.add_argument("--obs", type=float, default=0.6)      # 每次注入后的观察窗 (秒)
    ap.add_argument("--disc", type=float, default=6.0)     # 发现窗上限 (秒)
    args = ap.parse_args()

    st = dict(rcv_nxt=None, peer_snd=None, lport=0, board_n=0, peer_n=0,
              last_board_t=None, last_board=None)
    events = []

    def on_pkt(p, t):
        if ID_BASE <= p["ident"] < ID_BASE + 0x40:
            return   # 自捕: 自己的注入帧 (IP-ID 标记) ⇒ 排除
        if p["src"] == BOARD_IP and p["sport"] == PORT and p["dst"] == MY_IP:
            st["board_n"] += 1
            st["last_board_t"] = t
            st["last_board"] = p
            if p["flags"] & FLAG_A:
                a = p["ack"]
                cur = st["rcv_nxt"]
                if cur is None or ((a - cur) & 0xFFFFFFFF) < 0x80000000:
                    st["rcv_nxt"] = a
            return
        if p["dst"] == BOARD_IP and p["dport"] == PORT and p["src"] == MY_IP:
            st["peer_n"] += 1
            if st["lport"] == 0:
                st["lport"] = p["sport"]
            if p["sport"] == st["lport"] and p["plen"] > 0 and (p["flags"] & FLAG_A):
                end = (p["seq"] + p["plen"]) & 0xFFFFFFFF
                cur = st["peer_snd"]
                if cur is None or ((end - cur) & 0xFFFFFFFF) < 0x80000000:
                    st["peer_snd"] = end
            if (p["flags"] & (FLAG_F | FLAG_R)) and st["lport"] and p["sport"] == st["lport"]:
                print("WARN_PEER_CTRL flags=%s t=%.6f" % (flagstr(p["flags"]), t), flush=True)
            return

    print("INJ_START t=%.6f iface=%s stop_pid=%d" % (time.time(), IFACE, args.stop_pid), flush=True)
    sn = Sniffer(IFACE)

    # ---- 阶段 A: 发现 (lport / rcv_nxt / peer_snd_nxt), 同时在流量中 ----
    t0 = time.time()
    while time.time() - t0 < args.disc:
        sn.drain(0.2, on_pkt)
        if st["lport"] and st["rcv_nxt"] is not None and st["peer_snd"] is not None \
           and st["board_n"] >= 64 and st["peer_n"] >= 64:
            break
    if not st["lport"] or st["rcv_nxt"] is None:
        print("DISCOVER_FAIL lport=%s rcv_nxt=%s peer_snd=%s board_n=%d peer_n=%d" % (
            st["lport"], st["rcv_nxt"], st["peer_snd"], st["board_n"], st["peer_n"]), flush=True)
        sn.close(); return 4
    print("DISCOVER lport=%d rcv_nxt=%d(0x%08X) peer_snd_nxt=%s board_frames=%d peer_frames=%d" % (
        st["lport"], st["rcv_nxt"], st["rcv_nxt"],
        ("%d(0x%08X)" % (st["peer_snd"], st["peer_snd"])) if st["peer_snd"] is not None else "None",
        st["board_n"], st["peer_n"]), flush=True)

    # ---- 冻结源头 (SIGSTOP): 上行 rcv_nxt 静止 ----
    if args.stop_pid:
        try:
            os.kill(args.stop_pid, signal.SIGSTOP)
            time.sleep(0.05)
            stato = "?"
            try:
                with open("/proc/%d/stat" % args.stop_pid) as f:
                    stato = f.read().rsplit(")", 1)[1].split()[0]
            except Exception as e:
                stato = "ERR:%s" % e
            print("SRC_STOPPED pid=%d state=%s t=%.6f" % (args.stop_pid, stato, time.time()), flush=True)
        except Exception as e:
            print("SRC_STOP_FAIL pid=%d err=%s" % (args.stop_pid, e), flush=True)
            sn.close(); return 5
    sn.drain(args.stop_settle, on_pkt)

    rcv = st["rcv_nxt"]
    # ---- 可行性闸 (§7.2 全局可行性注: 目标向注入存在 ⇔ rcv_nxt < 2^31) ----
    if rcv >= (1 << 31):
        print("INFEASIBLE rcv_nxt=0x%08X >= 2^31 => 目标向不可构造 (设计件 §7.2 可行性注) => 重开连接" % rcv, flush=True)
        sn.close(); return 3

    # ---- 同步自检: 板 rcv_nxt == 对端 snd_nxt (全部已送达) ----
    if st["peer_snd"] is not None:
        d = (st["peer_snd"] - rcv) & 0xFFFFFFFF
        print("SYNC_CHECK peer_snd-rcv_nxt=%d %s" % (
            d if d < 0x80000000 else d - (1 << 32), "OK" if st["peer_snd"] == rcv else "MISMATCH"), flush=True)

    def quiet_gate(tag):
        t_start = time.time()
        while True:
            gap = time.time() - (st["last_board_t"] or 0)
            if gap >= args.quiet or time.time() - t_start > args.quiet_max:
                print("QUIET_ENTER tag=%s gap_s=%.3f waited=%.3f" % (tag, gap, time.time() - t_start), flush=True)
                return
            sn.drain(0.05, on_pkt)

    # ---- 注入计划 (§7.2 两条配方; T3 = 配方① 带响亮 SKIP) ----
    rcv32 = rcv & 0xFFFFFFFF
    plan = []
    plan.append(("T1_recipe2_d2p31_boundary", (rcv32 + (1 << 31)) & 0xFFFFFFFF, 100, "recipe2 D=2^31 (边界行 d_mod=0x80000000; 与 xsim F5 同形)"))
    plan.append(("T2_recipe2_d2p31_1MiB", (rcv32 + (1 << 31) + 0x100000) & 0xFFFFFFFF, 100, "recipe2 D=2^31+1MiB (内点)"))
    if rcv32 < 0x40000000:
        plan.append(("T3_recipe1_sub0x40000000", (rcv32 - 0x40000000) & 0xFFFFFFFF, 100, "recipe1 D=0xC0000000"))
    else:
        print("SKIP T3_recipe1: rcv_nxt=0x%08X >= Δ=0x40000000 ⇒ 配方① 前提 (rcv_nxt < Δ) 不成立" % rcv32, flush=True)
        plan.append(("T3_alt_recipe2_d2p31_2MiB", (rcv32 + (1 << 31) + 0x200000) & 0xFFFFFFFF, 100, "recipe2 D=2^31+2MiB (替代, 已登记)"))

    # ---- 逐例复算 + 分歧域自证 (设计件 §8.2-R8; 不满足即硬失败) ----
    ok = True
    for name, seq, plen, how in plan:
        D = seq - rcv32                       # 真差 (普通整数)
        d_mod = (seq - rcv32) & 0xFFFFFFFF
        old = 1 if seq < rcv32 else 0         # 旧式: seq_lt_abs = (seq < rcv_nxt)
        new = 1 if (d_mod >> 31) else 0       # 新式: seq_lt_rfc = seq_diff[31]
        in_equiv = (D >= -(1 << 31)) and (D <= (1 << 31) - 1)
        div = (old == 0 and new == 1)
        print("SELFCHECK %-30s seq=0x%08X rcv=0x%08X D=%+d d_mod=0x%08X old=%d new=%d 分歧=%s 等价域=%s | %s" % (
            name, seq, rcv32, D, d_mod, old, new, "YES" if div else "NO", "YES" if in_equiv else "NO", how), flush=True)
        if not div or in_equiv:
            ok = False
    if not ok:
        print("SELFCHECK_FAIL 有注入不在目标向分歧域 => 拒绝注入 (设计件 §8.2-R8)", flush=True)
        sn.close(); return 5

    # ---- 注入执行器 ----
    def run_injection(kind, seq, plen, ident):
        payload = bytes([0xAA + (i % 16) for i in range(plen)]) if plen else b""
        quiet_gate(kind)
        ack, win = 0, WIN
        lb = st.get("last_board")
        if lb is not None:
            ack, win = lb["ack"], lb["win"]
        t_send = time.time()
        print("INJECT kind=%s seq=0x%08X len=%d ack=0x%08X win=%d ident=0x%04X t=%.6f" % (
            kind, seq, plen, ack, win, ident, t_send), flush=True)
        inject(st["lport"], seq, ack, win, ident, payload)
        seen = []
        def on_obs(p, t):
            if p["src"] == BOARD_IP and p["sport"] == PORT:
                seen.append((t - t_send, p))
            on_pkt(p, t)
        sn.drain(args.obs, on_obs)
        ev = dict(kind=kind, seq=seq, plen=plen)
        for dt, p in seen:
            print("POST_INJECT_BOARD_FRAME kind=%s t=%.6f(rel %.3f ms) seq=%u ack=%u win=%d len=%d flags=%s" % (
                kind, dt + t_send, dt * 1000.0, p["seq"], p["ack"], p["win"], p["plen"], flagstr(p["flags"])), flush=True)
        ev["n_board_frames"] = len(seen)
        ev["raw"] = [(round(dt, 6), p["seq"], p["ack"], p["plen"], flagstr(p["flags"])) for dt, p in seen]
        events.append(ev)
        print("OBS_SUMMARY kind=%s board_frames=%d within_100ms=%d" % (
            kind, len(seen), sum(1 for dt, _ in seen if dt <= 0.1)), flush=True)
        return ev

    run_injection("dup", (rcv32 - 1) & 0xFFFFFFFF, 1, ID_BASE + 1)
    for i, (name, seq, plen, how) in enumerate(plan):
        run_injection(name, seq, plen, ID_BASE + 0x10 + i)
        time.sleep(0.2)

    print("SUMMARY " + " | ".join("%s n=%d" % (e["kind"], e["n_board_frames"]) for e in events), flush=True)
    print("INJ_DONE t=%.6f rcv_nxt=0x%08X" % (time.time(), rcv32), flush=True)
    sn.close()
    return 0

if __name__ == "__main__":
    sys.exit(main())
