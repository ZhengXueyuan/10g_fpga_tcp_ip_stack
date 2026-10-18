//=============================================================================
// udp_echo_tb.cpp — Phase 3 testbench
// Strategy: run enough idle to trigger first UDP frame, then capture the next.
// All TX output is drained during "wait" phases to prevent stream overflow.
//=============================================================================
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "hls_stream.h"
#include "../src/eth_types.h"
#include "../src/eth_utils.h"

// P4c (2026-09-12): 对齐当前 udp_echo 新签名 — P4b 起第 5 参为 cfg_stream
// (连接配置记录 -> fast path CAM/TCB)。本 TB 各测试点沿用旧 8 参调用, cfg 记录
// 本 TB 不消费 (csim 的 hls::stream 内存无界, 只写不读安全), 故加一层兼容壳
// 补 g_cfg —— 此前端口列表与新签名不匹配只能走 xsim (见 hls/run_hls.tcl 注释),
// 现本 TB 可直接 g++ 编译跑 csim; xsim 真 RTL 验证仍是最终判据。
static hls::stream<ap_uint<32> > g_cfg;
void udp_echo(bool, hls::stream<gmii_byte_t>&, hls::stream<gmii_byte_t>&, hls::stream<gmii_byte_t>&,
              hls::stream<ap_uint<32> >&, bool&, bool&, bool&, bool&);
static void udp_echo(bool reset_n, hls::stream<gmii_byte_t>&rx, hls::stream<gmii_byte_t>&tx,
                     hls::stream<gmii_byte_t>&msg, bool&d0, bool&d1, bool&d2, bool&d3) {
    udp_echo(reset_n, rx, tx, msg, g_cfg, d0, d1, d2, d3);
}

static int passed=0,failed=0;

#define TEST(n) printf("\n=== %s ===\n",n)
#define CHECK(c,m) do{if(c)passed++;else{failed++;printf(" FAIL: %s\n",m);}}while(0)

static hls::stream<gmii_byte_t> g_rx, g_tx, g_msg;
static bool led_d0, led_d1, led_d2, led_d3;
static gmii_byte_t dummy;

// Drain any pending TX (call between tests)
static void drain() { while(!g_tx.empty()) g_tx.read(dummy); }

// Wait for a complete frame to be sent, drain it. Returns when TX has been quiet.
static void skip_frames(int max_frames) {
    for(int f=0;f<max_frames;f++){
        bool got=false;
        for(int c=0;c<500;c++){
            udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
            if(!g_tx.empty()){got=true;break;}
        }
        if(!got) break;  // no more frames
        // Drain this frame completely
        gmii_byte_t b;
        for(int c=0;c<500;c++){
            udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
            while(!g_tx.empty()){
                g_tx.read(b);
                if(b.last) goto frame_done;
            }
        }
        frame_done:;
    }
}

// Feed a test frame into RX (with last flag on final byte)
static void feed(const uint8_t*f,int n) {
    for(int i=0;i<n;i++){
        gmii_byte_t b; b.data=f[i]; b.last=(i==n-1);
        g_rx.write(b);
        udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
    }
}

// Capture next complete frame from TX. Returns byte count, or -1 if timeout.
static int capture(uint8_t*buf,int max) {
    int n=0;
    for(int cyc=0;cyc<5000;cyc++){
        udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
        if(!g_tx.empty()){
            // Start of frame — read until last
            while(!g_tx.empty()){
                gmii_byte_t b=g_tx.read();
                if(n<max) buf[n++]=b.data;
                if(b.last) return n;
            }
        }
    }
    return -1;
}

//=============================================================================
void test_crc() {
    TEST("CRC32");
    uint32_t c=0xFFFFFFFF;
    for(int i=0;i<(int)strlen("123456789");i++) c=crc32_byte("123456789"[i],c);c^=0xFFFFFFFF;
    CHECK(c==0xCBF43926,"CRC('123456789')=0xCBF43926");
}
void test_reset() {
    TEST("Reset"); drain();
    for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
    drain();
    for(int i=0;i<100;i++) udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
    drain();
}

void test_tx_default() {
    TEST("UDP default frame");
    drain();
    for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    // Wait for first UDP frame to complete
    skip_frames(1);
    // Now capture the next UDP frame
    uint8_t cap[512]; int n=capture(cap,512);
    bool ok=true; for(int i=0;i<7;i++) if(cap[i]!=0x55) ok=false;
    CHECK(ok&&cap[7]==0xD5,"Preamble");
    int e=20; CHECK(cap[e]==0x08&&cap[e+1]==0x00,"EtherType=IPv4");
    int ip=22; CHECK((cap[ip]>>4)==4,"IP ver=4"); CHECK(cap[ip+9]==17,"UDP proto");
    int pl=50; const char*ex="HELLO       PERFXLAB"; ok=true;
    for(int i=0;ex[i];i++) if(cap[pl+i]!=(uint8_t)ex[i]) ok=false;
    CHECK(ok,"Payload");
    int ce=n-4; uint32_t ec=0xFFFFFFFF;
    for(int i=8;i<ce;i++) ec=crc32_byte(cap[i],ec); ec^=0xFFFFFFFF;
    uint32_t rc=((uint32_t)cap[ce+3]<<24)|((uint32_t)cap[ce+2]<<16)|((uint32_t)cap[ce+1]<<8)|cap[ce];
    CHECK(ec==rc,"CRC");
}

void test_arp() {
    TEST("ARP Reply");
    drain();
    for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    skip_frames(1); // drain default UDP
    uint8_t f[50]; int idx=0;
    for(int i=0;i<7;i++)f[idx++]=0x55;f[idx++]=0xD5;
    f[idx++]=0xFF;f[idx++]=0xFF;f[idx++]=0xFF;f[idx++]=0xFF;f[idx++]=0xFF;f[idx++]=0xFF;
    f[idx++]=0xAA;f[idx++]=0xBB;f[idx++]=0xCC;f[idx++]=0xDD;f[idx++]=0xEE;f[idx++]=0xFF;
    f[idx++]=0x08;f[idx++]=0x06;
    f[idx++]=0x00;f[idx++]=0x01;f[idx++]=0x08;f[idx++]=0x00;f[idx++]=6;f[idx++]=4;
    f[idx++]=0x00;f[idx++]=0x01;
    f[idx++]=0xAA;f[idx++]=0xBB;f[idx++]=0xCC;f[idx++]=0xDD;f[idx++]=0xEE;f[idx++]=0xFF;
    f[idx++]=192;f[idx++]=168;f[idx++]=100;f[idx++]=1;
    for(int i=0;i<6;i++)f[idx++]=0;f[idx++]=192;f[idx++]=168;f[idx++]=100;f[idx++]=2;
    feed(f,idx);
    uint8_t cap[256]; int n=capture(cap,256);
    if(n>0){CHECK(cap[20]==0x08&&cap[21]==0x06,"EtherType=ARP"); int a=22;CHECK(cap[a+6]==0&&cap[a+7]==2,"opcode=Reply");}
}

void test_icmp() {
    TEST("ICMP Echo");
    drain();
    for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    skip_frames(1);
    // Seed the ARP cache with the sender (0x10..0x15 @ 192.168.100.100) via an
    // ARP request so the echo reply goes to its unicast MAC (Bug 2 fix).
    uint8_t ar[60]; int ai=0;
    for(int i=0;i<7;i++)ar[ai++]=0x55;ar[ai++]=0xD5;
    ar[ai++]=BOARD_MAC_BYTE0;ar[ai++]=BOARD_MAC_BYTE1;ar[ai++]=BOARD_MAC_BYTE2;ar[ai++]=BOARD_MAC_BYTE3;ar[ai++]=BOARD_MAC_BYTE4;ar[ai++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;
    ar[ai++]=0x08;ar[ai++]=0x06;
    ar[ai++]=0;ar[ai++]=1;ar[ai++]=0x08;ar[ai++]=0;ar[ai++]=6;ar[ai++]=4;
    ar[ai++]=0;ar[ai++]=1;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=100;
    for(int i=0;i<6;i++)ar[ai++]=0;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=2;
    feed(ar,ai);
    skip_frames(1);  // drain the ARP reply this request triggers
    uint8_t p[80]; int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x10+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=20+8+4;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=1;p[idx++]=0;p[idx++]=0;p[idx++]=128;p[idx++]=1;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    int cs=idx;p[idx++]=8;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=1;p[idx++]=0;p[idx++]=1;
    p[idx++]='p';p[idx++]='i';p[idx++]='n';p[idx++]='g';
    uint32_t s=0;for(int i=0;i<6;i++)s+=((uint16_t)p[cs+i*2]<<8)|p[cs+i*2+1];while(s>>16)s=(s&0xFFFF)+(s>>16);
    p[cs+2]=((~s)>>8)&0xFF;p[cs+3]=(~s)&0xFF;
    feed(p,idx);
    uint8_t cap[256];int n=capture(cap,256);
    if(n>0){int icmp=42;CHECK(cap[icmp]==0&&cap[icmp+1]==0,"type=0 EchoReply");
        // capture() includes the 8-byte preamble (see EtherType at cap[20] = 12+8),
        // so dst_mac starts at cap[8]
        CHECK(cap[8]==0x10&&cap[9]==0x11&&cap[10]==0x12&&cap[11]==0x13&&cap[12]==0x14&&cap[13]==0x15,"reply dst_mac == sender MAC");
        CHECK(cap[icmp+8]=='p'&&cap[icmp+9]=='i',"payload intact");
        // verify the reply's ICMP checksum (FIX regression guard)
        int ilen=n-8-4-icmp;   // ICMP message length (payload 4 + hdr 8)
        uint8_t cbuf[64]; for(int i=0;i<ilen;i++) cbuf[i]=cap[icmp+i];
        cbuf[2]=0; cbuf[3]=0;   // zero the checksum field
        uint32_t s=0; for(int i=0;i<ilen-1;i+=2) s+=((uint16_t)cbuf[i]<<8)|cbuf[i+1];
        while(s>>16)s=(s&0xFFFF)+(s>>16);
        uint16_t exp=~s; uint16_t got=((uint16_t)cap[icmp+2]<<8)|cap[icmp+3];
        CHECK(exp==got,"ICMP reply checksum");}
}

void test_igmp_v2() {
    TEST("IGMPv2");
    drain();for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(1);
    uint8_t p[80]; int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x30+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=20+8;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=1;p[idx++]=0;p[idx++]=0;p[idx++]=1;p[idx++]=2;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    int gs=idx;p[idx++]=0x11;p[idx++]=100;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;
    uint32_t gs2=0;for(int i=0;i<4;i++)gs2+=((uint16_t)p[gs+i*2]<<8)|p[gs+i*2+1];while(gs2>>16)gs2=(gs2&0xFFFF)+(gs2>>16);
    p[gs+2]=((~gs2)>>8)&0xFF;p[gs+3]=(~gs2)&0xFF;
    feed(p,idx);
    uint8_t cap[256];int n=capture(cap,256);
    if(n>0){int ig=42;CHECK(cap[ig]==0x16,"type=0x16");}
}

void test_igmp_v1() {
    TEST("IGMPv1");
    drain();for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(1);
    uint8_t p[80]; int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x40+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=20+8;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=2;p[idx++]=0;p[idx++]=0;p[idx++]=1;p[idx++]=2;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    int gs=idx;p[idx++]=0x11;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;
    uint32_t gs2=0;for(int i=0;i<4;i++)gs2+=((uint16_t)p[gs+i*2]<<8)|p[gs+i*2+1];while(gs2>>16)gs2=(gs2&0xFFFF)+(gs2>>16);
    p[gs+2]=((~gs2)>>8)&0xFF;p[gs+3]=(~gs2)&0xFF;
    feed(p,idx);
    uint8_t cap[256];int n=capture(cap,256);
    if(n>0){int ig=42;CHECK(cap[ig]==0x12,"type=0x12");}
}

void test_ip_csum() {
    TEST("IP checksum");
    drain();for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(1);
    uint8_t p[80]; int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x20+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=20+8+5;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=0x42;p[idx++]=0;p[idx++]=0;p[idx++]=64;p[idx++]=17;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    p[idx++]=0x1F;p[idx++]=0x90;p[idx++]=0x1F;p[idx++]=0x90;uint16_t ul=8+5;p[idx++]=(ul>>8)&0xFF;p[idx++]=ul&0xFF;
    p[idx++]=0;p[idx++]=0;p[idx++]='H';p[idx++]='e';p[idx++]='l';p[idx++]='l';p[idx++]='o';
    feed(p,idx);
    uint8_t cap[256];int n=capture(cap,256);
}

void test_ethertype() {
    TEST("EtherType dispatch");
    drain();for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();
    uint8_t p[64];int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    for(int i=0;i<6;i++)p[idx++]=0xFF;for(int i=0;i<6;i++)p[idx++]=0xAA;p[idx++]=0x12;p[idx++]=0x34;
    for(int i=0;i<20;i++)p[idx++]=0;
    feed(p,idx);
    bool any=false;
    for(int i=0;i<100;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);if(!g_tx.empty())any=true;while(!g_tx.empty())g_tx.read(dummy);}
}

void test_crc_residue() {
    TEST("CRC residue");
    drain();for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(1);
    uint8_t cap[512];int n=capture(cap,512);
    if(n>8){uint32_t r=0xFFFFFFFF;for(int i=8;i<n;i++)r=crc32_byte(cap[i],r);printf("  residue=0x%08X (expect 0x2144DF1C)\n",r);CHECK(r==0x2144DF1C,"residue=0x2144DF1C");}
}

void test_arp_active() {
    TEST("ARP active lookup");
    drain();for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(3);
    // Feed ARP Reply to populate table
    uint8_t ar[50];int idx=0;
    for(int i=0;i<7;i++)ar[idx++]=0x55;ar[idx++]=0xD5;
    ar[idx++]=BOARD_MAC_BYTE0;ar[idx++]=BOARD_MAC_BYTE1;ar[idx++]=BOARD_MAC_BYTE2;ar[idx++]=BOARD_MAC_BYTE3;ar[idx++]=BOARD_MAC_BYTE4;ar[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)ar[idx++]=0xAA+i;ar[idx++]=0x08;ar[idx++]=0x06;
    ar[idx++]=0;ar[idx++]=1;ar[idx++]=0x08;ar[idx++]=0;ar[idx++]=6;ar[idx++]=4;
    ar[idx++]=0;ar[idx++]=2;
    for(int i=0;i<6;i++)ar[idx++]=0xAA+i;ar[idx++]=192;ar[idx++]=168;ar[idx++]=100;ar[idx++]=1;
    ar[idx++]=BOARD_MAC_BYTE0;ar[idx++]=BOARD_MAC_BYTE1;ar[idx++]=BOARD_MAC_BYTE2;ar[idx++]=BOARD_MAC_BYTE3;ar[idx++]=BOARD_MAC_BYTE4;ar[idx++]=BOARD_MAC_BYTE5;
    ar[idx++]=192;ar[idx++]=168;ar[idx++]=100;ar[idx++]=2;
    feed(ar,idx);drain();
    // Capture next frame — should still send (ARP table now has entry, but test just verifies no crash)
    uint8_t cap[512];int n=capture(cap,512);
    CHECK(n>60,"UDP frame after ARP Reply");printf(" %d bytes\n",n);
}

void test_dhcp_discover() {
    TEST("DHCP Discover");
    // Run this test last — after DHCP timer has elapsed in previous tests
    drain(); for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    // Skip many frames (DHCP needs time to trigger, ~1 sec at 125MHz)
    // For test purposes, just verify existing tests still pass and DHCP compiles
    uint8_t cap[512]; int n=capture(cap,512);
    CHECK(n>0,"DHCP test (infrastructure present)"); printf(" %d bytes\n",n);
}

void test_vlan_single() {
    TEST("VLAN single tag (802.1Q)");
    drain();for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(1);
    uint8_t p[68]; int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x50+i;
    p[idx++]=0x81;p[idx++]=0x00;p[idx++]=0x00;p[idx++]=0x64;
    p[idx++]=0x08;p[idx++]=0x06;
    p[idx++]=0x00;p[idx++]=0x01;p[idx++]=0x08;p[idx++]=0x00;p[idx++]=6;p[idx++]=4;
    p[idx++]=0x00;p[idx++]=0x01;
    for(int i=0;i<6;i++)p[idx++]=0x50+i;p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=1;
    for(int i=0;i<6;i++)p[idx++]=0;p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=2;
    feed(p,idx);
    uint8_t cap[256];int n=capture(cap,256);
    if(n>0){CHECK(cap[20]==0x08&&cap[21]==0x06,"EtherType=ARP");int a=22;CHECK(cap[a+6]==0&&cap[a+7]==2,"opcode=Reply");}
}

//=============================================================================
// UDP echo regression test (FIX 2026-08-18):
//  1) Reply must be IMMEDIATE (not gated on the 5s pacing tick).
//  2) Reply dst port must be the request's source port (ephemeral clients).
//  3) IP checksum / UDP length / IP total length / FCS all verified.
//  4) Reply goes to the sender's unicast MAC (ARP cache).
//=============================================================================
void test_udp_echo() {
    TEST("UDP echo immediate + src-port");
    drain();for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();
    skip_frames(1);
    // Seed ARP cache with sender 10:11:12:13:14:15 @ 192.168.100.100
    uint8_t ar[60];int ai=0;
    for(int i=0;i<7;i++)ar[ai++]=0x55;ar[ai++]=0xD5;
    ar[ai++]=BOARD_MAC_BYTE0;ar[ai++]=BOARD_MAC_BYTE1;ar[ai++]=BOARD_MAC_BYTE2;ar[ai++]=BOARD_MAC_BYTE3;ar[ai++]=BOARD_MAC_BYTE4;ar[ai++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;
    ar[ai++]=0x08;ar[ai++]=0x06;
    ar[ai++]=0;ar[ai++]=1;ar[ai++]=0x08;ar[ai++]=0;ar[ai++]=6;ar[ai++]=4;
    ar[ai++]=0;ar[ai++]=1;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=100;
    for(int i=0;i<6;i++)ar[ai++]=0;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=2;
    feed(ar,ai);
    skip_frames(1);  // drain the ARP reply this request triggers
    // Build UDP request: src port 12345 (0x3039), dst 8080, payload "hello ECO" (9B)
    uint8_t p[96];int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x10+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=20+8+9;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=0x42;p[idx++]=0x40;p[idx++]=0;p[idx++]=64;p[idx++]=17;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    p[idx++]=0x30;p[idx++]=0x39;p[idx++]=0x1F;p[idx++]=0x90;uint16_t ul=8+9;p[idx++]=(ul>>8)&0xFF;p[idx++]=ul&0xFF;
    p[idx++]=0;p[idx++]=0;   // UDP checksum 0 (no checksum)
    const char*pl="hello ECO";for(int i=0;i<9;i++)p[idx++]=pl[i];
    feed(p,idx);
    // Capture, skipping unrelated frames (periodic HELLO may fire mid-test)
    uint8_t cap[256];int n=-1;
    for(int t=0;t<4&&n<0;t++){
        n=capture(cap,256);
        if(n>0&&!(cap[20]==0x08&&cap[21]==0x00&&cap[42]==0x1F&&cap[43]==0x90))n=-1; // not our echo
    }
    if(n>0){
        CHECK(cap[20]==0x08&&cap[21]==0x00,"EtherType=IPv4");
        CHECK(cap[8]==0x10&&cap[9]==0x11&&cap[10]==0x12&&cap[11]==0x13&&cap[12]==0x14&&cap[13]==0x15,"reply dst_mac == sender MAC (unicast)");
        int iph=22;
        CHECK((cap[iph]>>4)==4,"IP ver=4");
        // IP checksum (checksum field = bytes iph+10,11)
        uint16_t ww[10];for(int i=0;i<10;i++)ww[i]=((uint16_t)cap[iph+i*2]<<8)|cap[iph+i*2+1];
        CHECK(ones_complement_checksum(ww,10)==0,"IP header checksum");
        CHECK(cap[iph+9]==17,"proto=UDP");
        uint16_t iplen=((uint16_t)cap[iph+2]<<8)|cap[iph+3];
        CHECK(iplen==it,"IP total length");
        CHECK(cap[iph+12]==192&&cap[iph+13]==168&&cap[iph+14]==100&&cap[iph+15]==2,"src IP=board");
        CHECK(cap[iph+16]==192&&cap[iph+17]==168&&cap[iph+18]==100&&cap[iph+19]==100,"dst IP=sender");
        int uh=iph+20;
        CHECK(cap[uh]==0x1F&&cap[uh+1]==0x90,"UDP src port=8080");
        CHECK(cap[uh+2]==0x30&&cap[uh+3]==0x39,"UDP dst port=request src port 12345");
        uint16_t udplen=((uint16_t)cap[uh+4]<<8)|cap[uh+5];
        CHECK(udplen==ul,"UDP length");
        int pp=uh+8;bool ok=true;
        for(int i=0;i<9;i++)if(cap[pp+i]!=(uint8_t)pl[i])ok=false;
        CHECK(ok,"payload 'hello ECO'");
        // frame = 8 preamble + 14 MAC + 46 padded payload + 4 FCS = 72 (not runt)
        CHECK(n==72,"frame padded to 64B + preamble + FCS");
        int ce=n-4;uint32_t ec=0xFFFFFFFF;
        for(int i=8;i<ce;i++)ec=crc32_byte(cap[i],ec);ec^=0xFFFFFFFF;
        uint32_t rc=((uint32_t)cap[ce+3]<<24)|((uint32_t)cap[ce+2]<<16)|((uint32_t)cap[ce+1]<<8)|cap[ce];
        CHECK(ec==rc,"CRC");
    } else {
        CHECK(false,"got a reply (immediate echo)");
    }
}

//=============================================================================
// TCP SYN-ACK regression test (FIX 2026-08-18):
//  SYN was previously dropped (tcp_find free-slot vs cid<0 bug) and the
//  SYN-ACK never came. Verify flags/ports, IP+TCP checksums, MSS option
//  bytes actually on the wire, then complete the handshake and verify the
//  echo data flows.
//=============================================================================
static uint16_t tcp_csum_ref(uint32_t sip, uint32_t dip, const uint8_t*d, uint16_t len){
    uint32_t s=6+len;s+=(sip>>16)&0xFFFF;s+=sip&0xFFFF;s+=(dip>>16)&0xFFFF;s+=dip&0xFFFF;
    for(int i=0;i<len-1;i+=2)s+=((uint16_t)d[i]<<8)|d[i+1];
    if(len&1)s+=((uint16_t)d[len-1]<<8);
    while(s>>16)s=(s&0xFFFF)+(s>>16);
    return (uint16_t)(~s);
}

void test_tcp_syn() {
    TEST("TCP SYN -> SYN-ACK (handshake)");
    drain();for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();
    skip_frames(1);
    // Seed ARP cache (10:11:12:13:14:15 @ 192.168.100.100)
    uint8_t ar[60];int ai=0;
    for(int i=0;i<7;i++)ar[ai++]=0x55;ar[ai++]=0xD5;
    ar[ai++]=BOARD_MAC_BYTE0;ar[ai++]=BOARD_MAC_BYTE1;ar[ai++]=BOARD_MAC_BYTE2;ar[ai++]=BOARD_MAC_BYTE3;ar[ai++]=BOARD_MAC_BYTE4;ar[ai++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;
    ar[ai++]=0x08;ar[ai++]=0x06;
    ar[ai++]=0;ar[ai++]=1;ar[ai++]=0x08;ar[ai++]=0;ar[ai++]=6;ar[ai++]=4;
    ar[ai++]=0;ar[ai++]=1;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=100;
    for(int i=0;i<6;i++)ar[ai++]=0;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=2;
    feed(ar,ai);
    skip_frames(1);
    // SYN: src port 12345 (0x3039), dst 7, seq 0x10000000, no options (doff=5)
    uint8_t p[88];int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x10+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=40;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=0x43;p[idx++]=0x40;p[idx++]=0;p[idx++]=64;p[idx++]=6;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    int ts=idx;
    p[idx++]=0x30;p[idx++]=0x39;p[idx++]=0;p[idx++]=7;   // src 12345, dst 7
    p[idx++]=0x10;p[idx++]=0x00;p[idx++]=0x00;p[idx++]=0x00; // seq
    p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;           // ack 0
    p[idx++]=0x50;p[idx++]=0x02;p[idx++]=0x20;p[idx++]=0x00; // doff=5, SYN, window 8192
    p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;           // checksum 0, urgent 0
    uint16_t tc=tcp_csum_ref(0xC0A86464,0xC0A86402,p+ts,20);
    p[ts+16]=(tc>>8)&0xFF;p[ts+17]=tc&0xFF;
    feed(p,idx);
    // Capture, skipping unrelated frames (periodic HELLO may fire mid-test)
    uint8_t cap[256];int n=-1;
    for(int t=0;t<4&&n<0;t++){
        n=capture(cap,256);
        if(n>0&&!(cap[20]==0x08&&cap[21]==0x00&&cap[42]==0&&cap[43]==7))n=-1; // not SYN-ACK
    }
    if(n>0){
        CHECK(cap[20]==0x08&&cap[21]==0x00,"EtherType=IPv4");
        int iph=22;
        uint16_t ww[10];for(int i=0;i<10;i++)ww[i]=((uint16_t)cap[iph+i*2]<<8)|cap[iph+i*2+1];
        CHECK(ones_complement_checksum(ww,10)==0,"IP header checksum");
        CHECK(cap[iph+9]==6,"proto=TCP");
        uint16_t iplen=((uint16_t)cap[iph+2]<<8)|cap[iph+3];
        CHECK(iplen==48,"IP total length (20+28)");
        int uh=iph+20;
        CHECK(cap[uh]==0&&cap[uh+1]==7,"TCP src port=7");
        CHECK(cap[uh+2]==0x30&&cap[uh+3]==0x39,"TCP dst port=12345");
        uint8_t doff=(cap[uh+12]>>4)&0xF;
        CHECK(doff==7,"doff=7 (SYN options)");
        uint8_t fl=cap[uh+13];
        CHECK((fl&0x12)==0x12,"flags=SYN|ACK");
        // P4c (2026-09-12): 通告窗必须 = 0xC000 (48K)。HLS 侧 layer_tcp.cpp
        // tcp_build_hdr(...,0xC000,...) 与 fast 侧 TCB rcv_wnd (slow_cfg_adp 常量)
        // / 门控帽 RING_CAP 0xBFFE 同量纲; 旧值 12K (0x3000) 为 P4c 前遗留。
        // 窗口字段在 TCP 偏移 14..15, 与选项 (doff=7) 无关。
        uint16_t win=((uint16_t)cap[uh+14]<<8)|cap[uh+15];
        CHECK(win==0xC000,"SYN-ACK window = 0xC000 (48K, P4c)");
        uint32_t sa=((uint32_t)cap[uh+8]<<24)|((uint32_t)cap[uh+9]<<16)|((uint32_t)cap[uh+10]<<8)|cap[uh+11];
        CHECK(sa==0x10000001,"ACK number = SYN seq+1");
        CHECK(cap[uh+20]==2&&cap[uh+21]==4&&cap[uh+22]==0x01&&cap[uh+23]==0xcc,"MSS=460 option on wire");
        // TCP checksum over 28-byte header (pseudo: 192.168.100.2 -> 192.168.100.100).
        // Zero the checksum field before summing (it is filled on the wire).
        uint8_t cb[40];for(int i=0;i<28;i++)cb[i]=cap[uh+i];
        cb[16]=0;cb[17]=0;
        uint16_t tc2=tcp_csum_ref(0xC0A86402,0xC0A86464,cb,28);
        uint16_t got2=((uint16_t)cap[uh+16]<<8)|cap[uh+17];
        CHECK(tc2==got2,"TCP checksum (with options)");
    } else {
        CHECK(false,"got SYN-ACK");
    }
    // Complete handshake: ACK (seq=0x10000001, ack=synack_seq+1=0x12345679)
    uint8_t a2[88];idx=0;
    for(int i=0;i<7;i++)a2[idx++]=0x55;a2[idx++]=0xD5;
    a2[idx++]=BOARD_MAC_BYTE0;a2[idx++]=BOARD_MAC_BYTE1;a2[idx++]=BOARD_MAC_BYTE2;a2[idx++]=BOARD_MAC_BYTE3;a2[idx++]=BOARD_MAC_BYTE4;a2[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)a2[idx++]=0x10+i;a2[idx++]=0x08;a2[idx++]=0x00;
    is=idx;a2[idx++]=0x45;a2[idx++]=0x00;it=40;a2[idx++]=(it>>8)&0xFF;a2[idx++]=it&0xFF;
    a2[idx++]=0;a2[idx++]=0x44;a2[idx++]=0x40;a2[idx++]=0;a2[idx++]=64;a2[idx++]=6;a2[idx++]=0;a2[idx++]=0;
    a2[idx++]=192;a2[idx++]=168;a2[idx++]=100;a2[idx++]=100;
    a2[idx++]=BOARD_IP_BYTE0;a2[idx++]=BOARD_IP_BYTE1;a2[idx++]=BOARD_IP_BYTE2;a2[idx++]=BOARD_IP_BYTE3;
    iw[0]=((uint16_t)a2[is]<<8)|a2[is+1];iw[1]=((uint16_t)a2[is+2]<<8)|a2[is+3];iw[2]=((uint16_t)a2[is+4]<<8)|a2[is+5];
    iw[3]=((uint16_t)a2[is+6]<<8)|a2[is+7];iw[4]=((uint16_t)a2[is+8]<<8)|a2[is+9];iw[5]=((uint16_t)a2[is+10]<<8)|a2[is+11];
    iw[6]=((uint16_t)a2[is+12]<<8)|a2[is+13];iw[7]=((uint16_t)a2[is+14]<<8)|a2[is+15];iw[8]=((uint16_t)a2[is+16]<<8)|a2[is+17];
    iw[9]=((uint16_t)a2[is+18]<<8)|a2[is+19];
    ic=ones_complement_checksum(iw,10);a2[is+10]=(ic>>8)&0xFF;a2[is+11]=ic&0xFF;
    ts=idx;
    a2[idx++]=0x30;a2[idx++]=0x39;a2[idx++]=0;a2[idx++]=7;
    a2[idx++]=0x10;a2[idx++]=0x00;a2[idx++]=0x00;a2[idx++]=0x01;   // seq=0x10000001
    a2[idx++]=0x12;a2[idx++]=0x34;a2[idx++]=0x56;a2[idx++]=0x79;   // ack=0x12345679
    a2[idx++]=0x50;a2[idx++]=0x10;a2[idx++]=0x20;a2[idx++]=0x00;   // doff=5, ACK
    a2[idx++]=0;a2[idx++]=0;a2[idx++]=0;a2[idx++]=0;
    tc=tcp_csum_ref(0xC0A86464,0xC0A86402,a2+ts,20);
    a2[ts+16]=(tc>>8)&0xFF;a2[ts+17]=tc&0xFF;
    feed(a2,idx);
    // Drain pending TX (bare ACK expects no reply; the periodic HELLO may
    // appear here, which is fine — the echo data test below is the real
    // handshake check).
    for(int c=0;c<100;c++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
    // --- Echo data: multi-MSS flow (FIX 2026-08-18) ---
    // After the handshake: cwnd=1072, seq=0x12345679, peer_seq=0x10000001.
    // Feed 5 data segments like a real peer (one MSS each: 460,460,460,460,160),
    // capturing each echo chunk after its segment (realistic RTT pacing).
    // Each segment's ACK makes progress, so the full 2000-byte echo must
    // come back at the right global offsets (re-chunked to <=TCP_TX_CHUNK).
    TEST("TCP echo multi-MSS (2000B in 4 segments)");
    const int lens[5]={460,460,460,460,160};
    uint32_t cseq=0x10000001;
    uint32_t ackv=0x12345679;
    uint32_t sent_total=0;
    uint32_t recv_total=0;
    uint8_t capB[700];
    for(int s=0;s<5;s++){
        uint8_t d3[700];int idx=0;
        for(int i=0;i<7;i++)d3[idx++]=0x55;d3[idx++]=0xD5;
        d3[idx++]=BOARD_MAC_BYTE0;d3[idx++]=BOARD_MAC_BYTE1;d3[idx++]=BOARD_MAC_BYTE2;d3[idx++]=BOARD_MAC_BYTE3;d3[idx++]=BOARD_MAC_BYTE4;d3[idx++]=BOARD_MAC_BYTE5;
        for(int i=0;i<6;i++)d3[idx++]=0x10+i;d3[idx++]=0x08;d3[idx++]=0x00;
        int is=idx;uint16_t it=40+lens[s];d3[idx++]=0x45;d3[idx++]=0x00;d3[idx++]=(it>>8)&0xFF;d3[idx++]=it&0xFF;
        d3[idx++]=0;d3[idx++]=0x4a+s;d3[idx++]=0x40;d3[idx++]=0;d3[idx++]=64;d3[idx++]=6;d3[idx++]=0;d3[idx++]=0;
        d3[idx++]=192;d3[idx++]=168;d3[idx++]=100;d3[idx++]=100;
        d3[idx++]=BOARD_IP_BYTE0;d3[idx++]=BOARD_IP_BYTE1;d3[idx++]=BOARD_IP_BYTE2;d3[idx++]=BOARD_IP_BYTE3;
        uint16_t iw[10];for(int i=0;i<10;i++){iw[i]=((uint16_t)d3[is+i*2]<<8)|d3[is+i*2+1];}
        uint16_t ic=ones_complement_checksum(iw,10);d3[is+10]=(ic>>8)&0xFF;d3[is+11]=ic&0xFF;
        int ts=idx;
        d3[idx++]=0x30;d3[idx++]=0x39;d3[idx++]=0;d3[idx++]=7;
        d3[idx++]=(cseq>>24)&0xFF;d3[idx++]=(cseq>>16)&0xFF;d3[idx++]=(cseq>>8)&0xFF;d3[idx++]=cseq&0xFF;
        d3[idx++]=(ackv>>24)&0xFF;d3[idx++]=(ackv>>16)&0xFF;d3[idx++]=(ackv>>8)&0xFF;d3[idx++]=ackv&0xFF;
        d3[idx++]=0x50;d3[idx++]=0x18;d3[idx++]=0x20;d3[idx++]=0x00;
        d3[idx++]=0;d3[idx++]=0;d3[idx++]=0;d3[idx++]=0;
        for(int i=0;i<lens[s];i++)d3[idx++]=((sent_total+i)&0xFF);
        uint16_t tc=tcp_csum_ref(0xC0A86464,0xC0A86402,d3+ts,20+lens[s]);
        d3[ts+16]=(tc>>8)&0xFF;d3[ts+17]=tc&0xFF;
        feed(d3,idx);
        cseq+=lens[s];
        ackv+=lens[s];   // ACK the previous echo chunk
        sent_total+=lens[s];
        // Capture the chunk(s) this segment triggers; skip spliced frames
        // (a HELLO mid-send clobbered by the un-gated TCP builder) via the
        // seq + length validation below.
        for(int cap_i=0;cap_i<3;cap_i++){
            int m4=-1;
            for(int tryc=0;tryc<4&&m4<0;tryc++){
                m4=capture(capB,700);
                bool pre=true;
                for(int i=0;i<7;i++)if(capB[i]!=0x55)pre=false;
                if(m4>0&&(!pre||capB[7]!=0xD5))m4=-1;
                if(m4>0&&!(capB[20]==0x08&&capB[21]==0x00&&(capB[42]==0&&capB[43]==7)))m4=-1;
            }
            if(m4<0)break;
            uint16_t iptot=((uint16_t)capB[24]<<8)|capB[25];
            uint16_t paylen=iptot-40;
            uint32_t tseq=((uint32_t)capB[46]<<24)|((uint32_t)capB[47]<<16)|((uint32_t)capB[48]<<8)|capB[49];
            if(paylen==0||paylen>600)continue;                 // spliced/odd frame
            if(m4 != 26+(int)iptot)continue;                   // truncated frame
            if(tseq != 0x12345679u+recv_total)continue;        // wrong seq
            bool okb=true;
            int badat=-1;
            for(int i=0;i<paylen;i++)
                if(capB[62+i]!=(((recv_total+i)&0xFF))){if(badat<0)badat=i;okb=false;}
            recv_total+=paylen;
            if(!okb)printf("  payload mismatch in chunk seq=%08x badat=%d hex:%02x %02x %02x %02x %02x %02x %02x %02x\n",tseq,badat,
                capB[62+badat],capB[62+badat+1],capB[62+badat+2],capB[62+badat+3],capB[62+badat+4],capB[62+badat+5],capB[62+badat+6],capB[62+badat+7]);
        }
    }
    // Feed a final pure ACK for the whole 2000-byte echo (ack = 0x12345679+2000)
    // — the last queued bytes only go out on ACK progress (flush-on-ACK).
    {
        uint8_t a3[64];int idx=0;
        for(int i=0;i<7;i++)a3[idx++]=0x55;a3[idx++]=0xD5;
        a3[idx++]=BOARD_MAC_BYTE0;a3[idx++]=BOARD_MAC_BYTE1;a3[idx++]=BOARD_MAC_BYTE2;a3[idx++]=BOARD_MAC_BYTE3;a3[idx++]=BOARD_MAC_BYTE4;a3[idx++]=BOARD_MAC_BYTE5;
        for(int i=0;i<6;i++)a3[idx++]=0x10+i;a3[idx++]=0x08;a3[idx++]=0x00;
        int is=idx;uint16_t it=40;a3[idx++]=0x45;a3[idx++]=0x00;a3[idx++]=(it>>8)&0xFF;a3[idx++]=it&0xFF;
        a3[idx++]=0;a3[idx++]=0x4e;a3[idx++]=0x40;a3[idx++]=0;a3[idx++]=64;a3[idx++]=6;a3[idx++]=0;a3[idx++]=0;
        a3[idx++]=192;a3[idx++]=168;a3[idx++]=100;a3[idx++]=100;
        a3[idx++]=BOARD_IP_BYTE0;a3[idx++]=BOARD_IP_BYTE1;a3[idx++]=BOARD_IP_BYTE2;a3[idx++]=BOARD_IP_BYTE3;
        uint16_t iw[10];for(int i=0;i<10;i++){iw[i]=((uint16_t)a3[is+i*2]<<8)|a3[is+i*2+1];}
        uint16_t ic=ones_complement_checksum(iw,10);a3[is+10]=(ic>>8)&0xFF;a3[is+11]=ic&0xFF;
        int ts=idx;
        a3[idx++]=0x30;a3[idx++]=0x39;a3[idx++]=0;a3[idx++]=7;
        uint32_t ackv2=0x12345679u+2000;
        a3[idx++]=(ackv2>>24)&0xFF;a3[idx++]=(ackv2>>16)&0xFF;a3[idx++]=(ackv2>>8)&0xFF;a3[idx++]=ackv2&0xFF;
        a3[idx++]=0x10;a3[idx++]=0x00;a3[idx++]=0x06;a3[idx++]=0x49;  // client seq=0x10000649
        a3[idx++]=0x50;a3[idx++]=0x10;a3[idx++]=0x20;a3[idx++]=0x00;
        a3[idx++]=0;a3[idx++]=0;a3[idx++]=0;a3[idx++]=0;
        uint16_t tc=tcp_csum_ref(0xC0A86464,0xC0A86402,a3+ts,20);
        a3[ts+16]=(tc>>8)&0xFF;a3[ts+17]=tc&0xFF;
        feed(a3,idx);
        for(int cap_i=0;cap_i<3;cap_i++){
            int m4=-1;
            for(int tryc=0;tryc<4&&m4<0;tryc++){
                m4=capture(capB,700);
                bool pre=true;
                for(int i=0;i<7;i++)if(capB[i]!=0x55)pre=false;
                if(m4>0&&(!pre||capB[7]!=0xD5))m4=-1;
                if(m4>0&&!(capB[20]==0x08&&capB[21]==0x00&&(capB[42]==0&&capB[43]==7)))m4=-1;
            }
            if(m4<0)break;
            uint16_t iptot=((uint16_t)capB[24]<<8)|capB[25];
            uint16_t paylen=iptot-40;
            uint32_t tseq=((uint32_t)capB[46]<<24)|((uint32_t)capB[47]<<16)|((uint32_t)capB[48]<<8)|capB[49];
            if(paylen==0||paylen>600)continue;
            if(m4 != 26+(int)iptot)continue;
            if(tseq != 0x12345679u+recv_total)continue;
            bool okb=true;
            for(int i=0;i<paylen;i++)
                if(capB[62+i]!=(((recv_total+i)&0xFF)))okb=false;
            recv_total+=paylen;
            if(!okb)printf("  payload mismatch in tail chunk seq=%08x\n",tseq);
        }
    }
    printf("recv_total=%u\n",recv_total);
    CHECK(recv_total==2000,"all 2000 echo bytes received");
    // drain any pending frames (HELLO pacing)
    for(int c=0;c<100;c++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
}

// FIX 2026-08-19 (agent): Windows IGNORES the advertised MSS=460 and sends
// 536-byte segments (IP total 576). Regression: a single 536B segment must be
// echoed fully (472 immediate + 64 queued), byte-for-byte. Also covers 392B
// (a 536+392 tail that is < TCP_TX_CHUNK so sent in one frame).
void test_tcp_echo_536() {
    TEST("TCP echo 536B segment (Windows ignores MSS=460)");
    drain();for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();
    skip_frames(1);
    // Seed ARP cache (10:11:12:13:14:15 @ 192.168.100.100)
    uint8_t ar[60];int ai=0;
    for(int i=0;i<7;i++)ar[ai++]=0x55;ar[ai++]=0xD5;
    ar[ai++]=BOARD_MAC_BYTE0;ar[ai++]=BOARD_MAC_BYTE1;ar[ai++]=BOARD_MAC_BYTE2;ar[ai++]=BOARD_MAC_BYTE3;ar[ai++]=BOARD_MAC_BYTE4;ar[ai++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;
    ar[ai++]=0x08;ar[ai++]=0x06;
    ar[ai++]=0;ar[ai++]=1;ar[ai++]=0x08;ar[ai++]=0;ar[ai++]=6;ar[ai++]=4;
    ar[ai++]=0;ar[ai++]=1;
    for(int i=0;i<6;i++)ar[ai++]=0x10+i;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=100;
    for(int i=0;i<6;i++)ar[ai++]=0;ar[ai++]=192;ar[ai++]=168;ar[ai++]=100;ar[ai++]=2;
    feed(ar,ai);
    skip_frames(1);
    // SYN (src 12345, dst 7, seq 0x10000000)
    uint8_t p[88];int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x10+i;p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;uint16_t it=40;p[idx++]=0x45;p[idx++]=0x00;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=0x43;p[idx++]=0x40;p[idx++]=0;p[idx++]=64;p[idx++]=6;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    int ts=idx;
    p[idx++]=0xD4;p[idx++]=0x31;p[idx++]=0;p[idx++]=7;   // src 54321, dst 7
    p[idx++]=0x10;p[idx++]=0x00;p[idx++]=0x00;p[idx++]=0x00;
    p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;
    p[idx++]=0x50;p[idx++]=0x02;p[idx++]=0x20;p[idx++]=0x00;
    p[idx++]=0;p[idx++]=0;p[idx++]=0;p[idx++]=0;
    uint16_t tc=tcp_csum_ref(0xC0A86464,0xC0A86402,p+ts,20);
    p[ts+16]=(tc>>8)&0xFF;p[ts+17]=tc&0xFF;
    feed(p,idx);
    uint8_t cap[256];int n=-1;
    for(int t=0;t<4&&n<0;t++){
        n=capture(cap,256);
        if(n>0&&!(cap[20]==0x08&&cap[21]==0x00&&cap[42]==0&&cap[43]==7))n=-1;
    }
    if(n<0){CHECK(false,"got SYN-ACK");return;}
    {   // P4c: SYN-ACK 通告窗 = 0xC000 (48K) — 第二条握手路径同断言
        uint16_t win2=((uint16_t)cap[42+14]<<8)|cap[42+15];
        CHECK(win2==0xC000,"SYN-ACK window = 0xC000 (536 path)");
    }
    // ACK to complete handshake (seq=0x10000001, ack=0x12345679)
    uint8_t a2[88];idx=0;
    for(int i=0;i<7;i++)a2[idx++]=0x55;a2[idx++]=0xD5;
    a2[idx++]=BOARD_MAC_BYTE0;a2[idx++]=BOARD_MAC_BYTE1;a2[idx++]=BOARD_MAC_BYTE2;a2[idx++]=BOARD_MAC_BYTE3;a2[idx++]=BOARD_MAC_BYTE4;a2[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)a2[idx++]=0x10+i;a2[idx++]=0x08;a2[idx++]=0x00;
    is=idx;it=40;a2[idx++]=0x45;a2[idx++]=0x00;a2[idx++]=(it>>8)&0xFF;a2[idx++]=it&0xFF;
    a2[idx++]=0;a2[idx++]=0x44;a2[idx++]=0x40;a2[idx++]=0;a2[idx++]=64;a2[idx++]=6;a2[idx++]=0;a2[idx++]=0;
    a2[idx++]=192;a2[idx++]=168;a2[idx++]=100;a2[idx++]=100;
    a2[idx++]=BOARD_IP_BYTE0;a2[idx++]=BOARD_IP_BYTE1;a2[idx++]=BOARD_IP_BYTE2;a2[idx++]=BOARD_IP_BYTE3;
    for(int i=0;i<10;i++)iw[i]=((uint16_t)a2[is+i*2]<<8)|a2[is+i*2+1];
    ic=ones_complement_checksum(iw,10);a2[is+10]=(ic>>8)&0xFF;a2[is+11]=ic&0xFF;
    ts=idx;
    a2[idx++]=0xD4;a2[idx++]=0x31;a2[idx++]=0;a2[idx++]=7;
    a2[idx++]=0x10;a2[idx++]=0x00;a2[idx++]=0x00;a2[idx++]=0x01;
    a2[idx++]=0x12;a2[idx++]=0x34;a2[idx++]=0x56;a2[idx++]=0x79;
    a2[idx++]=0x50;a2[idx++]=0x10;a2[idx++]=0x20;a2[idx++]=0x00;
    a2[idx++]=0;a2[idx++]=0;a2[idx++]=0;a2[idx++]=0;
    tc=tcp_csum_ref(0xC0A86464,0xC0A86402,a2+ts,20);
    a2[ts+16]=(tc>>8)&0xFF;a2[ts+17]=tc&0xFF;
    feed(a2,idx);
    for(int c=0;c<100;c++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
    // Send one 536B segment (peer ignores MSS=460)
    const int lens2[2]={536,392};
    uint32_t cseq=0x10000001;
    uint32_t ackv=0x12345679;
    uint32_t sent_total=0;
    uint32_t recv_total=0;
    uint8_t capB[700];
    for(int s=0;s<2;s++){
        uint8_t d3[700];idx=0;
        for(int i=0;i<7;i++)d3[idx++]=0x55;d3[idx++]=0xD5;
        d3[idx++]=BOARD_MAC_BYTE0;d3[idx++]=BOARD_MAC_BYTE1;d3[idx++]=BOARD_MAC_BYTE2;d3[idx++]=BOARD_MAC_BYTE3;d3[idx++]=BOARD_MAC_BYTE4;d3[idx++]=BOARD_MAC_BYTE5;
        for(int i=0;i<6;i++)d3[idx++]=0x10+i;d3[idx++]=0x08;d3[idx++]=0x00;
        is=idx;it=40+lens2[s];d3[idx++]=0x45;d3[idx++]=0x00;d3[idx++]=(it>>8)&0xFF;d3[idx++]=it&0xFF;
        d3[idx++]=0;d3[idx++]=0x4a+s;d3[idx++]=0x40;d3[idx++]=0;d3[idx++]=64;d3[idx++]=6;d3[idx++]=0;d3[idx++]=0;
        d3[idx++]=192;d3[idx++]=168;d3[idx++]=100;d3[idx++]=100;
        d3[idx++]=BOARD_IP_BYTE0;d3[idx++]=BOARD_IP_BYTE1;d3[idx++]=BOARD_IP_BYTE2;d3[idx++]=BOARD_IP_BYTE3;
        for(int i=0;i<10;i++)iw[i]=((uint16_t)d3[is+i*2]<<8)|d3[is+i*2+1];
        ic=ones_complement_checksum(iw,10);d3[is+10]=(ic>>8)&0xFF;d3[is+11]=ic&0xFF;
        ts=idx;
        d3[idx++]=0xD4;d3[idx++]=0x31;d3[idx++]=0;d3[idx++]=7;
        d3[idx++]=(cseq>>24)&0xFF;d3[idx++]=(cseq>>16)&0xFF;d3[idx++]=(cseq>>8)&0xFF;d3[idx++]=cseq&0xFF;
        d3[idx++]=(ackv>>24)&0xFF;d3[idx++]=(ackv>>16)&0xFF;d3[idx++]=(ackv>>8)&0xFF;d3[idx++]=ackv&0xFF;
        d3[idx++]=0x50;d3[idx++]=0x18;d3[idx++]=0x20;d3[idx++]=0x00;
        d3[idx++]=0;d3[idx++]=0;d3[idx++]=0;d3[idx++]=0;
        for(int i=0;i<lens2[s];i++)d3[idx++]=((sent_total+i)&0xFF);
        tc=tcp_csum_ref(0xC0A86464,0xC0A86402,d3+ts,20+lens2[s]);
        d3[ts+16]=(tc>>8)&0xFF;d3[ts+17]=tc&0xFF;
        feed(d3,idx);
        cseq+=lens2[s];
        ackv+=lens2[s];
        sent_total+=lens2[s];
        for(int cap_i=0;cap_i<4;cap_i++){
            int m4=-1;
            for(int tryc=0;tryc<4&&m4<0;tryc++){
                m4=capture(capB,700);
                bool pre=true;
                for(int i=0;i<7;i++)if(capB[i]!=0x55)pre=false;
                if(m4>0&&(!pre||capB[7]!=0xD5))m4=-1;
                if(m4>0&&!(capB[20]==0x08&&capB[21]==0x00&&(capB[42]==0&&capB[43]==7)))m4=-1;
            }
            if(m4<0)break;
            uint16_t iptot=((uint16_t)capB[24]<<8)|capB[25];
            uint16_t paylen=iptot-40;
            uint32_t tseq=((uint32_t)capB[46]<<24)|((uint32_t)capB[47]<<16)|((uint32_t)capB[48]<<8)|capB[49];
            if(paylen==0||paylen>600)continue;
            if(m4 != 26+(int)iptot)continue;
            if(tseq != 0x12345679u+recv_total)continue;
            bool okb=true;
            int badat=-1;
            for(int i=0;i<paylen;i++)
                if(capB[62+i]!=(((recv_total+i)&0xFF))){if(badat<0)badat=i;okb=false;}
            recv_total+=paylen;
            if(!okb)printf("  payload mismatch in 536 chunk seq=%08x badat=%d hex:%02x exp:%02x\n",tseq,badat,capB[62+badat],(recv_total-paylen+badat)&0xFF);
        }
    }
    printf("recv_total=%u (536+392)\n",recv_total);
    CHECK(recv_total==928,"all 928 echo bytes (536+392) received");
    for(int c=0;c<100;c++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
}

void test_vlan_qinq() {
    TEST("VLAN QinQ (802.1ad)");
    drain();for(int i=0;i<5;i++) udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);drain();skip_frames(1);
    uint8_t p[72]; int idx=0;
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    p[idx++]=BOARD_MAC_BYTE0;p[idx++]=BOARD_MAC_BYTE1;p[idx++]=BOARD_MAC_BYTE2;p[idx++]=BOARD_MAC_BYTE3;p[idx++]=BOARD_MAC_BYTE4;p[idx++]=BOARD_MAC_BYTE5;
    for(int i=0;i<6;i++)p[idx++]=0x60+i;
    p[idx++]=0x88;p[idx++]=0xA8;p[idx++]=0x00;p[idx++]=0x65;
    p[idx++]=0x81;p[idx++]=0x00;p[idx++]=0x00;p[idx++]=0x64;
    p[idx++]=0x08;p[idx++]=0x00;
    int is=idx;p[idx++]=0x45;p[idx++]=0x00;uint16_t it=20+8+5;p[idx++]=(it>>8)&0xFF;p[idx++]=it&0xFF;
    p[idx++]=0;p[idx++]=0x50;p[idx++]=0;p[idx++]=0;p[idx++]=64;p[idx++]=17;p[idx++]=0;p[idx++]=0;
    p[idx++]=192;p[idx++]=168;p[idx++]=100;p[idx++]=100;
    p[idx++]=BOARD_IP_BYTE0;p[idx++]=BOARD_IP_BYTE1;p[idx++]=BOARD_IP_BYTE2;p[idx++]=BOARD_IP_BYTE3;
    uint16_t iw[10];for(int i=0;i<10;i++)iw[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t ic=ones_complement_checksum(iw,10);p[is+10]=(ic>>8)&0xFF;p[is+11]=ic&0xFF;
    p[idx++]=0x1F;p[idx++]=0x90;p[idx++]=0x1F;p[idx++]=0x90;uint16_t ul=8+5;p[idx++]=(ul>>8)&0xFF;p[idx++]=ul&0xFF;
    p[idx++]=0;p[idx++]=0;p[idx++]='Q';p[idx++]='i';p[idx++]='n';p[idx++]='Q';p[idx++]='!';
    feed(p,idx);
    uint8_t cap[256];int n=capture(cap,256);
    if(n>0){CHECK(cap[20]==0x08&&cap[21]==0x00,"EtherType=IPv4");int pl=50;CHECK(cap[pl]=='Q'&&cap[pl+1]=='i',"payload");}
}


//=============================================================================
// P11 P2-甲 (G8): 双板 IP / 回源 / 单口等价 csim 用例
//=============================================================================
// 约定: 所有 feed() 帧含 8B 前导 (7x55 + D5); capture() 原样返回 (含前导)。
// 捕获辅助: 只接受满足谓词的完整帧 (其它帧整帧丢弃后继续找)。
static int capture_if(bool (*pred)(const uint8_t*,int), uint8_t*buf, int max) {
    for (int f=0; f<24; f++) {
        int n = capture(buf, max);
        if (n < 0) return -1;
        if (pred(buf,n)) return n;
    }
    return -1;
}
static bool pred_arp(const uint8_t*c,int n){ return n>42 && c[20]==0x08 && c[21]==0x06; }
static bool pred_udp_echo(const uint8_t*c,int n){ return n>50 && c[20]==0x08 && c[21]==0x00 && c[31]==17 && c[42]==0x1F && c[43]==0x90 && c[44]==0x30 && c[45]==0x39; }
static bool pred_icmp(const uint8_t*c,int n){ return n>50 && c[20]==0x08 && c[21]==0x00 && c[31]==1; }
static bool pred_synack(const uint8_t*c,int n){ return n>60 && c[20]==0x08 && c[21]==0x00 && c[31]==6 && (c[55]&0x12)==0x12; }

// 清空 cfg 记录流; 返回读到的 32 位字数 (每记录 8 字)。
static int drain_cfg(uint32_t *rec, int maxw) {
    int n=0;
    while(!g_cfg.empty()) { ap_uint<32> v=g_cfg.read(); if(rec && n<maxw) rec[n]=v.to_uint(); n++; }
    return n;
}

// 组 IP 头 (20B, 校验和已填), 返回头起始偏移; idx 前进 20。
static int put_ip_hdr(uint8_t*p,int &idx,uint32_t sip,uint32_t dip,uint8_t proto,uint16_t tot){
    int is=idx;
    p[idx++]=0x45;p[idx++]=0x00;p[idx++]=(tot>>8)&0xFF;p[idx++]=tot&0xFF;
    p[idx++]=0x00;p[idx++]=0x11;p[idx++]=0x40;p[idx++]=0x00;
    p[idx++]=64;p[idx++]=proto;p[idx++]=0x00;p[idx++]=0x00;
    p[idx++]=(sip>>24)&0xFF;p[idx++]=(sip>>16)&0xFF;p[idx++]=(sip>>8)&0xFF;p[idx++]=sip&0xFF;
    p[idx++]=(dip>>24)&0xFF;p[idx++]=(dip>>16)&0xFF;p[idx++]=(dip>>8)&0xFF;p[idx++]=dip&0xFF;
    uint16_t w[10];for(int i=0;i<10;i++)w[i]=((uint16_t)p[is+i*2]<<8)|p[is+i*2+1];
    uint16_t c=ones_complement_checksum(w,10);p[is+10]=(c>>8)&0xFF;p[is+11]=c&0xFF;
    return is;
}

// 组以太网帧头 (前导 + dst/src MAC + ethertype); idx 指向载荷。
static void put_eth(uint8_t*p,int &idx,uint64_t dmac,uint64_t smac,uint16_t et){
    for(int i=0;i<7;i++)p[idx++]=0x55;p[idx++]=0xD5;
    for(int i=5;i>=0;i--)p[idx++]=(dmac>>(i*8))&0xFF;
    for(int i=5;i>=0;i--)p[idx++]=(smac>>(i*8))&0xFF;
    p[idx++]=(et>>8)&0xFF;p[idx++]=(et)&0xFF;
}
static uint64_t smac_101(void){ return 0x101112131415ULL; }

// ARP request: spa/tpa; 返回帧长。
static int build_arp_req(uint8_t*f,uint32_t spa,uint32_t tpa,uint64_t sha){
    int idx=0; put_eth(f,idx,0xFFFFFFFFFFFFULL,sha,0x0806);
    f[idx++]=0x00;f[idx++]=0x01;f[idx++]=0x08;f[idx++]=0x00;f[idx++]=6;f[idx++]=4;
    f[idx++]=0x00;f[idx++]=0x01;
    for(int i=5;i>=0;i--)f[idx++]=(sha>>(i*8))&0xFF;
    f[idx++]=(spa>>24)&0xFF;f[idx++]=(spa>>16)&0xFF;f[idx++]=(spa>>8)&0xFF;f[idx++]=spa&0xFF;
    for(int i=0;i<6;i++)f[idx++]=0x00;
    f[idx++]=(tpa>>24)&0xFF;f[idx++]=(tpa>>16)&0xFF;f[idx++]=(tpa>>8)&0xFF;f[idx++]=tpa&0xFF;
    return idx;
}
// ICMP echo request: 返回帧长。
static int build_icmp_req(uint8_t*f,uint32_t sip,uint32_t dip,uint8_t tag){
    int idx=0; put_eth(f,idx,0x000A3501FEC0ULL,smac_101(),0x0800);
    put_ip_hdr(f,idx,sip,dip,1,20+8+4);
    int cs=idx;
    f[idx++]=8;f[idx++]=0;f[idx++]=0;f[idx++]=0;f[idx++]=0;f[idx++]=1;f[idx++]=0;f[idx++]=1;
    f[idx++]='p';f[idx++]='i';f[idx++]='n';f[idx++]=tag;
    uint32_t s=0;for(int i=0;i<6;i++)s+=((uint16_t)f[cs+i*2]<<8)|f[cs+i*2+1];while(s>>16)s=(s&0xFFFF)+(s>>16);
    f[cs+2]=((~s)>>8)&0xFF;f[cs+3]=(~s)&0xFF;
    return idx;
}
// UDP echo request (src port -> 8080): 返回帧长。
static int build_udp_req(uint8_t*f,uint32_t sip,uint32_t dip,uint16_t sport,const char*pl){
    int idx=0; put_eth(f,idx,0x000A3501FEC0ULL,smac_101(),0x0800);
    int plen=(int)strlen(pl);
    put_ip_hdr(f,idx,sip,dip,17,(uint16_t)(20+8+plen));
    f[idx++]=(sport>>8)&0xFF;f[idx++]=(sport)&0xFF;f[idx++]=0x1F;f[idx++]=0x90;
    uint16_t ul=8+plen;f[idx++]=(ul>>8)&0xFF;f[idx++]=ul&0xFF;
    f[idx++]=0;f[idx++]=0;
    for(int i=0;i<plen;i++)f[idx++]=pl[i];
    return idx;
}
// TCP SYN: 返回帧长。
static int build_syn(uint8_t*f,uint32_t sip,uint32_t dip,uint16_t sport,uint32_t seq){
    int idx=0; put_eth(f,idx,0x000A3501FEC0ULL,smac_101(),0x0800);
    put_ip_hdr(f,idx,sip,dip,6,40);
    int ts=idx;
    f[idx++]=(sport>>8)&0xFF;f[idx++]=sport&0xFF;f[idx++]=0x1F;f[idx++]=0x90;
    f[idx++]=(seq>>24)&0xFF;f[idx++]=(seq>>16)&0xFF;f[idx++]=(seq>>8)&0xFF;f[idx++]=seq&0xFF;
    f[idx++]=0;f[idx++]=0;f[idx++]=0;f[idx++]=0;
    f[idx++]=0x50;f[idx++]=0x02;f[idx++]=0x20;f[idx++]=0x00;
    f[idx++]=0;f[idx++]=0;f[idx++]=0;f[idx++]=0;
    uint32_t s=6+20;s+=(sip>>16)&0xFFFF;s+=sip&0xFFFF;s+=(dip>>16)&0xFFFF;s+=dip&0xFFFF;
    for(int i=0;i<19;i+=2)s+=((uint16_t)f[ts+i]<<8)|f[ts+i+1];
    while(s>>16)s=(s&0xFFFF)+(s>>16);
    uint16_t tc=(uint16_t)(~s);f[ts+16]=(tc>>8)&0xFF;f[ts+17]=tc&0xFF;
    return idx;
}
// RST: 返回帧长。
static int build_rst(uint8_t*f,uint32_t sip,uint32_t dip,uint16_t sport,uint32_t seq){
    int idx=0; put_eth(f,idx,0x000A3501FEC0ULL,smac_101(),0x0800);
    put_ip_hdr(f,idx,sip,dip,6,40);
    int ts=idx;
    f[idx++]=(sport>>8)&0xFF;f[idx++]=sport&0xFF;f[idx++]=0x1F;f[idx++]=0x90;
    f[idx++]=(seq>>24)&0xFF;f[idx++]=(seq>>16)&0xFF;f[idx++]=(seq>>8)&0xFF;f[idx++]=seq&0xFF;
    f[idx++]=0;f[idx++]=0;f[idx++]=0;f[idx++]=0;
    f[idx++]=0x50;f[idx++]=0x04;f[idx++]=0x00;f[idx++]=0x00;
    f[idx++]=0;f[idx++]=0;f[idx++]=0;f[idx++]=0;
    uint32_t s=6+20;s+=(sip>>16)&0xFFFF;s+=sip&0xFFFF;s+=(dip>>16)&0xFFFF;s+=dip&0xFFFF;
    for(int i=0;i<19;i+=2)s+=((uint16_t)f[ts+i]<<8)|f[ts+i+1];
    while(s>>16)s=(s&0xFFFF)+(s>>16);
    uint16_t tc=(uint16_t)(~s);f[ts+16]=(tc>>8)&0xFF;f[ts+17]=tc&0xFF;
    return idx;
}

#define IP_A_U32 (0xC0A86402u)
#define IP_B_U32 (0xC0A86404u)

// ---- G8-1: ARP / ICMP / UDP 到 IP_B (dual 接受 / legacy 丢弃) ----
static void test_p11_ipb_arp_icmp_udp(void){
    TEST("P11 IP_B accept (ARP/ICMP/UDP)");
    drain(); for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    uint8_t f[128]; int n;
    n=build_arp_req(f,0xC0A86465u,IP_B_U32,smac_101()); feed(f,n);
    uint8_t cap[256];
    int m=capture_if(pred_arp,cap,256);
#if BOARD_IP_DUAL
    CHECK(m>0,"ARP reply for IP_B (dual)");
    if(m>0){
        CHECK(cap[22+6]==0&&cap[22+7]==2,"ARP opcode=reply");
        CHECK(cap[36]==192&&cap[37]==168&&cap[38]==100&&cap[39]==4,"ARP reply SPA = IP_B");
        CHECK(cap[46]==192&&cap[47]==168&&cap[48]==100&&cap[49]==0x65,"ARP reply TPA = requester");
    }
#else
    CHECK(m<0,"ARP reply for IP_B suppressed (legacy)");
#endif
    n=build_icmp_req(f,0xC0A86465u,IP_B_U32,0x11); feed(f,n);
    m=capture_if(pred_icmp,cap,256);
#if BOARD_IP_DUAL
    CHECK(m>0,"ICMP reply for IP_B (dual)");
    if(m>0){
        CHECK(cap[42]==0,"ICMP echo reply type=0");
        CHECK(cap[34]==192&&cap[35]==168&&cap[36]==100&&cap[37]==4,"ICMP reply src IP=IP_B");
    }
#else
    CHECK(m<0,"ICMP reply for IP_B suppressed (legacy)");
#endif
    n=build_udp_req(f,0xC0A86465u,IP_B_U32,0x3039,"P11B"); feed(f,n);
    m=capture_if(pred_udp_echo,cap,256);
#if BOARD_IP_DUAL
    CHECK(m>0,"UDP echo reply for IP_B (dual)");
    if(m>0){
        CHECK(cap[34]==192&&cap[35]==168&&cap[36]==100&&cap[37]==4,"UDP reply src IP=IP_B");
        CHECK(cap[50]=='P'&&cap[51]=='1'&&cap[52]=='1'&&cap[53]=='B',"UDP reply payload");
    }
#else
    CHECK(m<0,"UDP echo reply for IP_B suppressed (legacy)");
#endif
    for(int i=0;i<20;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
}

// ---- G8-2: 广播 -> 源 IP = IP_A (两种构建同行为) ----
static void test_p11_broadcast_src(void){
    TEST("P11 broadcast reply source = IP_A");
    drain(); for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    uint8_t f[128]; int n=build_icmp_req(f,0xC0A86465u,0xFFFFFFFFu,0x22); feed(f,n);
    uint8_t cap[256]; int m=capture_if(pred_icmp,cap,256);
    CHECK(m>0,"broadcast ICMP reply present");
    if(m>0) CHECK(cap[34]==192&&cap[35]==168&&cap[36]==100&&cap[37]==2,"broadcast reply src IP = IP_A");
    for(int i=0;i<20;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
}

// ---- G8-3: TCP 同 peer 双 IP 分离 + cfg local_ip ----
static void test_p11_tcp_dual(void){
    TEST("P11 TCP dual-IP separation + cfg local_ip");
    drain(); for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    drain_cfg(NULL,0);
    uint8_t f[128],cap[256]; int n,m;
    n=build_syn(f,0xC0A86465u,IP_B_U32,23456,0x20000000u); feed(f,n);
    m=capture_if(pred_synack,cap,256);
#if BOARD_IP_DUAL
    CHECK(m>0,"SYN-ACK for IP_B (dual)");
    if(m>0){
        CHECK(cap[34]==192&&cap[35]==168&&cap[36]==100&&cap[37]==4,"SYN-ACK src IP = IP_B");
        CHECK(cap[38]==192&&cap[39]==168&&cap[40]==100&&cap[41]==0x65,"SYN-ACK dst IP = peer .101");
        CHECK(cap[42]==0x1F&&cap[43]==0x90,"SYN-ACK src port 8080");
        CHECK(cap[44]==(23456>>8)&&cap[45]==(23456&0xFF),"SYN-ACK dst port = peer port");
    }
    uint32_t rec[64]; int w=drain_cfg(rec,64);
    CHECK(w>=8,"cfg ADD record written");
    if(w>=8) CHECK(rec[2]==IP_B_U32,"cfg ADD w2 (local_ip) = IP_B");
    n=build_syn(f,0xC0A86465u,IP_A_U32,23456,0x30000000u); feed(f,n);
    m=capture_if(pred_synack,cap,256);
    CHECK(m>0,"SYN-ACK for IP_A (same 4-tuple except local IP)");
    if(m>0) CHECK(cap[34]==192&&cap[35]==168&&cap[36]==100&&cap[37]==2,"second SYN-ACK src IP = IP_A (no collision)");
    w=drain_cfg(rec,64);
    CHECK(w>=8,"second cfg ADD record written");
    if(w>=8) CHECK(rec[2]==IP_A_U32,"second cfg ADD w2 (local_ip) = IP_A");
#else
    CHECK(m<0,"SYN to IP_B suppressed (legacy)");
    uint32_t rec[64]; int w=drain_cfg(rec,64);
    CHECK(w==0,"no cfg record for IP_B SYN (legacy)");
#endif
    for(int i=0;i<40;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
}

// ---- G8-4: IP_A 回包签名 (两二进制必须逐字节相同; 由 run 脚本比较) ----
static void test_p11_ip_a_signature(void){
    TEST("P11 IP_A reply signatures (dual vs legacy byte-equal)");
    drain(); for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    uint8_t f[128],cap[256]; int n,m;
    struct { const char* tag; int len; uint32_t crc; } sig[4];
    n=build_arp_req(f,0xC0A86465u,IP_A_U32,smac_101()); feed(f,n);
    m=capture_if(pred_arp,cap,256);
    { uint32_t c=0xFFFFFFFF; for(int i=8;i<m-4;i++)c=crc32_byte(cap[i],c); sig[0].tag="ARP";sig[0].len=m;sig[0].crc=(m>0)?(c^0xFFFFFFFF):0; CHECK(m>0,"ARP reply IP_A"); }
    n=build_icmp_req(f,0xC0A86465u,IP_A_U32,0x33); feed(f,n);
    m=capture_if(pred_icmp,cap,256);
    { uint32_t c=0xFFFFFFFF; for(int i=8;i<m-4;i++)c=crc32_byte(cap[i],c); sig[1].tag="ICMP";sig[1].len=m;sig[1].crc=(m>0)?(c^0xFFFFFFFF):0; CHECK(m>0,"ICMP reply IP_A"); }
    n=build_udp_req(f,0xC0A86465u,IP_A_U32,0x3039,"P11A"); feed(f,n);
    m=capture_if(pred_udp_echo,cap,256);
    { uint32_t c=0xFFFFFFFF; for(int i=8;i<m-4;i++)c=crc32_byte(cap[i],c); sig[2].tag="UDP";sig[2].len=m;sig[2].crc=(m>0)?(c^0xFFFFFFFF):0; CHECK(m>0,"UDP echo reply IP_A"); }
    n=build_syn(f,0xC0A86465u,IP_A_U32,23457,0x40000000u); feed(f,n);
    m=capture_if(pred_synack,cap,256);
    { uint32_t c=0xFFFFFFFF; for(int i=8;i<m-4;i++)c=crc32_byte(cap[i],c); sig[3].tag="SYNACK";sig[3].len=m;sig[3].crc=(m>0)?(c^0xFFFFFFFF):0; CHECK(m>0,"SYN-ACK IP_A"); }
    for(int i=0;i<4;i++) printf("P11SIG %s len=%d crc=%08X\n",sig[i].tag,sig[i].len,sig[i].crc);
    for(int i=0;i<40;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
}

#if ACTIVE_CONNECT
#if defined(TCP_STATE_PROBE)
extern uint8_t tcp_state_probe(uint16_t port, uint32_t ip, uint32_t local_ip);
#endif
// ---- G8-5 (M-1): RTO 释放槽保留 local_ip; 对端 RST 命中并 CFG_DEL ----
// 只在 -DACTIVE_CONNECT=1 -DTCP_RTO_MIN=<small> 的 csim 臂里编/跑 (默认构建的
// tcp_rx_process 只在 TCP 帧到达时被调用, 空闲 RTO 不推进 — 见 udp_echo.cpp
// 的 P1-2 注释)。本用例因此作为 G8 的第三个二进制臂。
static void test_p11_rst_released_slot(void){
    TEST("P11 RST-to-released-slot (local_ip retention)");
    drain(); for(int i=0;i<5;i++)udp_echo(false,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3); drain();
    drain_cfg(NULL,0);
    uint8_t f[128]; int n;
    n=build_syn(f,0xC0A86465u,IP_B_U32,23458,0x50000000u); feed(f,n);
    uint32_t rec[64]; int w=drain_cfg(rec,64);
    CHECK(w>=8,"cfg ADD for IP_B connection");
    if(w>=8) CHECK(rec[2]==IP_B_U32,"ADD w2 = IP_B");
    // 推进空闲拍让 T_SYN_RCVD 的 RTO 超限释放槽位 (保留 peer/local IP)
    for(int i=0;i<(TCP_RTO_MIN*3/2+200);i++){
        udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);
        while(!g_tx.empty())g_tx.read(dummy);
        while(!g_cfg.empty())(void)g_cfg.read();
    }
#if defined(TCP_STATE_PROBE)
    // 直接见证: 槽已释放 (T_FREE=0) 而 peer/local IP 仍可按四元组找回
    CHECK(tcp_state_probe(23458,0xC0A86465u,IP_B_U32)==0,"slot released to T_FREE after RTO");
#endif
    // 对端从 .101 发 RST -> IP_B (同一四元组): 必须命中释放槽并写 CFG_DEL
    n=build_rst(f,0xC0A86465u,IP_B_U32,23458,0x60000000u); feed(f,n);
    for(int i=0;i<20;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
    w=drain_cfg(rec,64);
    CHECK(w>=8,"CFG_DEL written for RST to released slot");
    if(w>=8) CHECK(((rec[0]>>8)&0xFF)==1,"cfg cmd = DEL");
    // 负对照: 同一 RST 发到 IP_A (local_ip 不匹配) ⇒ 不得产生 DEL
    n=build_rst(f,0xC0A86465u,IP_A_U32,23458,0x60000001u); feed(f,n);
    for(int i=0;i<20;i++){udp_echo(true,g_rx,g_tx,g_msg,led_d0,led_d1,led_d2,led_d3);while(!g_tx.empty())g_tx.read(dummy);}
    w=drain_cfg(rec,64);
    CHECK(w==0,"RST with wrong local_ip produces no DEL (negative control)");
}
#endif

int main() {
    test_crc();
    test_reset();
    test_tx_default();
    test_arp();
    test_icmp();
    test_igmp_v2();
    test_igmp_v1();
    test_ip_csum();
    test_ethertype();
    test_arp_active();
    test_vlan_single();
    test_vlan_qinq();
    test_udp_echo();
    test_tcp_syn();
    test_tcp_echo_536();
    test_dhcp_discover();
    test_p11_ipb_arp_icmp_udp();
    test_p11_broadcast_src();
    test_p11_tcp_dual();
    test_p11_ip_a_signature();
#if ACTIVE_CONNECT
    test_p11_rst_released_slot();
#endif
    printf("P11_SUMMARY passed=%d failed=%d\n",passed,failed);
    return failed>0?1:0;
}
