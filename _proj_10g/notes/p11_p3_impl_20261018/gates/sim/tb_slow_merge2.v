`timescale 1ns/1ps
//=============================================================================
// tb_slow_merge2.v — P11 P3 G-P3-4 (慢 merge): 帧级 RR + 帧原子 + 反压
//   臂 A: 两帧同时就绪 -> 先 p0 (rr=0 工作保持偏好另一口? rr 初值 0 ⇒ pick1 优先)
//          —— 明确口径: 初值 rr=0 ⇒ 第一帧优先 p1; 之后交替。
//   臂 B: 帧内字连续 (输出帧的 id 不变直到 tlast)
//   臂 C: 反压 (m_tready=0) 时帧锁保持、另一口 tready=0
//   臂 D: 一帧结束后 rr 翻转
//=============================================================================
module tb_slow_merge2;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg [63:0] p0_tdata=0,p1_tdata=0;
    reg [7:0]  p0_tkeep=8'hFF,p1_tkeep=8'hFF;
    reg p0_tvalid=0,p1_tvalid=0,p0_tlast=0,p1_tlast=0;
    reg p0_tuser=0,p1_tuser=0,p0_tcrs=0,p1_tcrs=0,p0_terr=0,p1_terr=0;
    reg m_tready=1;
    wire p0_tready,p1_tready,m_tvalid,m_tlast,m_tuser,m_tcrs,m_terr;
    wire [63:0] m_tdata; wire [7:0] m_tkeep;

    slow_merge2 #(.STRICT(1'b0), .TO_CYCLES(0)) dut (
        .clk(clk), .rst_n(rst_n),
        .p0_tdata(p0_tdata),.p0_tkeep(p0_tkeep),.p0_tvalid(p0_tvalid),
        .p0_tready(p0_tready),.p0_tlast(p0_tlast),.p0_tuser(p0_tuser),
        .p0_tcrs(p0_tcrs),.p0_terr(p0_terr),
        .p1_tdata(p1_tdata),.p1_tkeep(p1_tkeep),.p1_tvalid(p1_tvalid),
        .p1_tready(p1_tready),.p1_tlast(p1_tlast),.p1_tuser(p1_tuser),
        .p1_tcrs(p1_tcrs),.p1_terr(p1_terr),
        .m_tdata(m_tdata),.m_tkeep(m_tkeep),.m_tvalid(m_tvalid),.m_tready(m_tready),
        .m_tlast(m_tlast),.m_tuser(m_tuser),.m_tcrs(m_tcrs),.m_terr(m_terr),
        .stat_frames0(),.stat_frames1(),.stat_out(),.stat_bubble(),.stat_abort()
    );

    integer errors=0;
    task chk(input cond, input [255:0] msg);
        begin if(!cond) begin errors=errors+1; $display(" FAIL: %0s", msg); end end
    endtask

    // 输出帧序列记录
    reg [7:0] seq_id [0:15];
    integer   seq_n = 0;
    reg [7:0] cur_id = 0;
    reg       cur_v  = 0;
    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            if (!cur_v) begin cur_id = m_tdata[7:0]; cur_v = 1; end
            else chk(m_tdata[7:0] == cur_id, "frame atomicity (id stable within frame)");
            if (m_tlast) begin
                if (seq_n < 16) seq_id[seq_n] = cur_id;
                seq_n = seq_n + 1;
                cur_v = 0;
            end
        end
    end

    // 帧发生器: id 帧 = nwords 个连续拍, data[7:0]=id, [15:8]=word idx
    task automatic send_frame(input integer port, input [7:0] id, input integer nwords);
        integer k;
        begin
            for (k=0;k<nwords;k=k+1) begin
                @(negedge clk);
                if (port==0) begin p0_tdata={56'd0, k[7:0], id}; p0_tvalid=1; p0_tlast=(k==nwords-1); end
                else         begin p1_tdata={56'd0, k[7:0], id}; p1_tvalid=1; p1_tlast=(k==nwords-1); end
                #0;
                // 在 negedge 采样组合 tready: 高 = 下一个 posedge 接受本字
                while (!(port==0 ? p0_tready : p1_tready)) begin
                    @(negedge clk); #0;
                end
            end
            @(negedge clk);
            if (port==0) begin p0_tvalid=0; p0_tlast=0; end
            else         begin p1_tvalid=0; p1_tlast=0; end
        end
    endtask

    event ev_c;
    initial begin
        @ev_c;
        send_frame(0, 8'hC0, 2);
    end
    initial begin
        $display("=== G-P3-4 slow_merge2 ===");
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; @(negedge clk);
        // 同时就绪两帧: rr=0 => pick1 优先 p1
        fork
            send_frame(0, 8'hA0, 4);
            send_frame(1, 8'hB0, 4);
        join
        repeat(3) @(negedge clk);
        chk(seq_n==2, "A two frames output");
        chk(seq_id[0]==8'hB0 && seq_id[1]==8'hA0, "A RR order: p1 first then p0");
        // 再发一帧 p1 => 上一帧是 p0, 应优先 p1
        send_frame(1, 8'hB1, 3);
        repeat(2) @(negedge clk);
        chk(seq_id[2]==8'hB1, "D rr flips (p1 again after p0)");
        // 反压臂: p0 帧推入后 m_tready=0, 检查 p1_tready=0 且帧锁保持
        m_tready = 0;
        ->ev_c;
        repeat(4) @(negedge clk);
        chk(p1_tready == 0, "C non-selected port tready=0 under backpressure");
        chk(m_tvalid == 1, "C frame held under backpressure");
        m_tready = 1;
        repeat(6) @(negedge clk);
        chk(seq_n==4, "C backpressure frame completes");

        if (errors==0) $display("SLOW_MERGE2 TB PASS");
        else           $display("SLOW_MERGE2 TB FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #200000; $display("SLOW_MERGE2 TB FAIL (timeout)"); $finish; end
endmodule
