#!/bin/bash
cd /d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_review_board_b4_20261016/raw
PY=/c/Users/zhxue/anaconda3/python.exe
echo "############ B4P_S3"; $PY k0_verify2.py B4P_S3 pcap/k0_B4P_S3_full.pcap0 pcap/k0_B4P_S3_full.pcap1 > k0_verify_B4P_S3.txt 2>&1; tail -3 k0_verify_B4P_S3.txt
echo "############ N4H3"; $PY k0_verify2.py N4H3 pcap/k0_N4H3_full.pcap0 > k0_verify_N4H3.txt 2>&1; tail -12 k0_verify_N4H3.txt
echo "############ B4H2"; $PY k0_verify2.py B4H2 pcap/k0_B4H2_full.pcap0 > k0_verify_B4H2.txt 2>&1; tail -14 k0_verify_B4H2.txt
echo "############ B4P_S2"; $PY k0_verify2.py B4P_S2 pcap/k0_B4P_S2_full.pcap0 pcap/k0_B4P_S2_full.pcap1 pcap/k0_B4P_S2_full.pcap2 pcap/k0_B4P_S2_full.pcap3 pcap/k0_B4P_S2_full.pcap4 > k0_verify_B4P_S2.txt 2>&1; tail -9 k0_verify_B4P_S2.txt
echo "############ ALL_DONE"
