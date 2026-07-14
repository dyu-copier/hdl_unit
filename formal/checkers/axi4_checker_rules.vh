// ============================================================================
// axi4_checker_rules.vh — shared AXI4 protocol rule body
//
// Included by axi4_slave_checker.v and axi4_master_checker.v INSIDE the
// module body, AFTER the includer defines:
//
//   `AXI4_MASTER_RULE(x)  — obligation of the AXI master
//                           (assume in the slave checker, assert in the
//                            master checker)
//   `AXI4_SLAVE_RULE(x)   — obligation of the AXI slave
//                           (assert in the slave checker, assume in the
//                            master checker)
//   `AXI4_CHK_DUT_IS_SLAVE or `AXI4_CHK_DUT_IS_MASTER
//                           (selects which side gets the clocked
//                            synchronous-reset treatment of R3/R4)
//
// and `undef's all three afterwards. Both wrappers must declare the same
// port and parameter set (see either wrapper for the canonical list).
//
// Rule IDs (R*, H*, W*, RD*, B*, P*, X*) refer to AXI4_rules.md at the
// repository root. Deliberate simplifications, all documented there:
//
//  * R3/R4 are checked only after one full clock cycle inside reset
//    (synchronous-reset designs make no power-up promise).
//  * Tracking capacity is bounded: at most F_MAX_OUTSTANDING write bursts
//    in flight and F_MAX_PER_ID read bursts per ID. Beyond-capacity issue
//    is itself flagged by a MASTER_RULE — raise the parameters if a real
//    design legitimately exceeds them.
//  * Exclusive access is disabled by default (F_OPT_EXCLUSIVE=0 assumes/
//    asserts AxLOCK low and forbids EXOKAY). Set 1 to enable X1–X3 checks.
//  * Liveness (W9/RD7 and eventual-READY) is unbounded in the spec; set
//    F_OPT_MAX_STALL > 0 to impose a bounded-liveness variant.
// ============================================================================

    localparam ADDR_LSB   = $clog2(C_AXI_DATA_WIDTH/8);
    localparam NUM_IDS    = (1 << C_AXI_ID_WIDTH);
    localparam MAX_SIZE   = $clog2(C_AXI_DATA_WIDTH/8); // B5: largest legal AxSIZE
    localparam WQ_CNT_W   = $clog2(F_MAX_OUTSTANDING + 1);
    localparam RQ_CNT_W   = $clog2(F_MAX_PER_ID + 1);
    localparam STRB_W     = C_AXI_DATA_WIDTH/8;

    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge i_clk)
        f_past_valid <= 1'b1;

    wire aw_accepted = i_axi_awvalid && i_axi_awready && i_axi_reset_n;
    wire w_accepted  = i_axi_wvalid  && i_axi_wready  && i_axi_reset_n;
    wire b_accepted  = i_axi_bvalid  && i_axi_bready  && i_axi_reset_n;
    wire ar_accepted = i_axi_arvalid && i_axi_arready && i_axi_reset_n;
    wire r_accepted  = i_axi_rvalid  && i_axi_rready  && i_axi_reset_n;

    // ------------------------------------------------------------------
    // R3/R4/R5 — reset behavior.
    // Environment-driven valids are constrained combinationally (legal to
    // pin free variables at step 0). DUT-driven valids are checked only
    // after a full clock cycle inside reset — BSC designs use synchronous
    // reset, so the power-up state makes no promise (see AXI4_rules.md
    // note 1). R5 (first VALID at a rising edge after reset release)
    // follows from these plus H1.
    // ------------------------------------------------------------------
`ifdef AXI4_CHK_DUT_IS_SLAVE
    always @(*) if (!i_axi_reset_n) begin
        assume (!i_axi_awvalid);
        assume (!i_axi_wvalid);
        assume (!i_axi_arvalid);
    end
    always @(posedge i_clk)
    if (f_past_valid && !$past(i_axi_reset_n) && !i_axi_reset_n) begin
        assert (!i_axi_bvalid);
        assert (!i_axi_rvalid);
    end
`else
    always @(*) if (!i_axi_reset_n) begin
        assume (!i_axi_bvalid);
        assume (!i_axi_rvalid);
    end
    always @(posedge i_clk)
    if (f_past_valid && !$past(i_axi_reset_n) && !i_axi_reset_n) begin
        assert (!i_axi_awvalid);
        assert (!i_axi_wvalid);
        assert (!i_axi_arvalid);
    end
`endif

    // ------------------------------------------------------------------
    // H1/H2 (+M2) — VALID hold and full-payload stability while stalled,
    // all five channels. Obligations void if reset asserts mid-stall.
    // ------------------------------------------------------------------
    always @(posedge i_clk)
    if (f_past_valid && $past(i_axi_reset_n) && i_axi_reset_n) begin
        // AW (master-driven)
        if ($past(i_axi_awvalid) && !$past(i_axi_awready)) begin
            `AXI4_MASTER_RULE(i_axi_awvalid);
            `AXI4_MASTER_RULE($stable(i_axi_awid));
            `AXI4_MASTER_RULE($stable(i_axi_awaddr));
            `AXI4_MASTER_RULE($stable(i_axi_awlen));
            `AXI4_MASTER_RULE($stable(i_axi_awsize));
            `AXI4_MASTER_RULE($stable(i_axi_awburst));
            `AXI4_MASTER_RULE($stable(i_axi_awlock));
            `AXI4_MASTER_RULE($stable(i_axi_awcache));
            `AXI4_MASTER_RULE($stable(i_axi_awprot));
            `AXI4_MASTER_RULE($stable(i_axi_awqos));
            `AXI4_MASTER_RULE($stable(i_axi_awregion));
        end
        // W (master-driven)
        if ($past(i_axi_wvalid) && !$past(i_axi_wready)) begin
            `AXI4_MASTER_RULE(i_axi_wvalid);
            `AXI4_MASTER_RULE($stable(i_axi_wdata));
            `AXI4_MASTER_RULE($stable(i_axi_wstrb));
            `AXI4_MASTER_RULE($stable(i_axi_wlast));
        end
        // B (slave-driven)
        if ($past(i_axi_bvalid) && !$past(i_axi_bready)) begin
            `AXI4_SLAVE_RULE(i_axi_bvalid);
            `AXI4_SLAVE_RULE($stable(i_axi_bid));
            `AXI4_SLAVE_RULE($stable(i_axi_bresp));
        end
        // AR (master-driven)
        if ($past(i_axi_arvalid) && !$past(i_axi_arready)) begin
            `AXI4_MASTER_RULE(i_axi_arvalid);
            `AXI4_MASTER_RULE($stable(i_axi_arid));
            `AXI4_MASTER_RULE($stable(i_axi_araddr));
            `AXI4_MASTER_RULE($stable(i_axi_arlen));
            `AXI4_MASTER_RULE($stable(i_axi_arsize));
            `AXI4_MASTER_RULE($stable(i_axi_arburst));
            `AXI4_MASTER_RULE($stable(i_axi_arlock));
            `AXI4_MASTER_RULE($stable(i_axi_arcache));
            `AXI4_MASTER_RULE($stable(i_axi_arprot));
            `AXI4_MASTER_RULE($stable(i_axi_arqos));
            `AXI4_MASTER_RULE($stable(i_axi_arregion));
        end
        // R (slave-driven)
        if ($past(i_axi_rvalid) && !$past(i_axi_rready)) begin
            `AXI4_SLAVE_RULE(i_axi_rvalid);
            `AXI4_SLAVE_RULE($stable(i_axi_rid));
            `AXI4_SLAVE_RULE($stable(i_axi_rdata));
            `AXI4_SLAVE_RULE($stable(i_axi_rresp));
            `AXI4_SLAVE_RULE($stable(i_axi_rlast));
        end
    end

    // ------------------------------------------------------------------
    // B1–B6 (+X1/X2) — burst legality, checked whenever an address is
    // presented. Byte count fits in 16 bits (256 beats × 128 bytes max).
    // ------------------------------------------------------------------
    wire [15:0] f_aw_bytes = ({8'h0, i_axi_awlen} + 16'd1) << i_axi_awsize;
    wire [15:0] f_ar_bytes = ({8'h0, i_axi_arlen} + 16'd1) << i_axi_arsize;

    always @(*) if (i_axi_reset_n && i_axi_awvalid) begin
        `AXI4_MASTER_RULE(i_axi_awburst != 2'b11);                    // B1
        `AXI4_MASTER_RULE({29'h0, i_axi_awsize} <= MAX_SIZE);         // B5
        if (i_axi_awburst != 2'b01)
            `AXI4_MASTER_RULE(i_axi_awlen[7:4] == 4'h0);              // B2 (FIXED/WRAP <= 16 beats)
        if (i_axi_awburst == 2'b10) begin
            `AXI4_MASTER_RULE(i_axi_awlen == 8'd1 || i_axi_awlen == 8'd3
                           || i_axi_awlen == 8'd7 || i_axi_awlen == 8'd15);          // B3
            `AXI4_MASTER_RULE((i_axi_awaddr & ((32'h1 << i_axi_awsize) - 1)) == 0); // B4
        end
        if (i_axi_awburst == 2'b01)
            `AXI4_MASTER_RULE(({4'h0, i_axi_awaddr[11:0]} + f_aw_bytes) <= 16'd4096); // B6
        if (F_OPT_EXCLUSIVE == 0)
            `AXI4_MASTER_RULE(i_axi_awlock == 1'b0);                  // X1 (exclusive disabled)
        else if (i_axi_awlock) begin
            `AXI4_MASTER_RULE((f_aw_bytes & (f_aw_bytes - 16'd1)) == 0);             // X2: power of 2
            `AXI4_MASTER_RULE(f_aw_bytes <= 16'd128);                                // X2: <= 128 bytes
            `AXI4_MASTER_RULE((i_axi_awaddr & ({16'h0, f_aw_bytes} - 32'd1)) == 0);  // X2: aligned
        end
    end

    always @(*) if (i_axi_reset_n && i_axi_arvalid) begin
        `AXI4_MASTER_RULE(i_axi_arburst != 2'b11);                    // B1
        `AXI4_MASTER_RULE({29'h0, i_axi_arsize} <= MAX_SIZE);         // B5
        if (i_axi_arburst != 2'b01)
            `AXI4_MASTER_RULE(i_axi_arlen[7:4] == 4'h0);              // B2
        if (i_axi_arburst == 2'b10) begin
            `AXI4_MASTER_RULE(i_axi_arlen == 8'd1 || i_axi_arlen == 8'd3
                           || i_axi_arlen == 8'd7 || i_axi_arlen == 8'd15);          // B3
            `AXI4_MASTER_RULE((i_axi_araddr & ((32'h1 << i_axi_arsize) - 1)) == 0); // B4
        end
        if (i_axi_arburst == 2'b01)
            `AXI4_MASTER_RULE(({4'h0, i_axi_araddr[11:0]} + f_ar_bytes) <= 16'd4096); // B6
        if (F_OPT_EXCLUSIVE == 0)
            `AXI4_MASTER_RULE(i_axi_arlock == 1'b0);                  // X1
        else if (i_axi_arlock) begin
            `AXI4_MASTER_RULE((f_ar_bytes & (f_ar_bytes - 16'd1)) == 0);             // X2
            `AXI4_MASTER_RULE(f_ar_bytes <= 16'd128);                                // X2
            `AXI4_MASTER_RULE((i_axi_araddr & ({16'h0, f_ar_bytes} - 32'd1)) == 0);  // X2
        end
    end

    // ------------------------------------------------------------------
    // Write transaction tracking (W1/W2/W4/W5/W6/W7, B7 for writes).
    //
    // AXI4 removed WID: write data follows write-address order, so a
    // single in-order queue of accepted AWs suffices. A W burst may begin
    // in the same cycle its AW is accepted (payload taken live from the
    // AW channel); W data strictly before its address is NOT supported by
    // this checker (a legal but rare pattern — see AXI4_rules.md W3 note).
    // ------------------------------------------------------------------
    reg [C_AXI_ID_WIDTH-1:0]   f_wq_id    [0:F_MAX_OUTSTANDING-1];
    reg [7:0]                  f_wq_len   [0:F_MAX_OUTSTANDING-1];
    reg [C_AXI_ADDR_WIDTH-1:0] f_wq_addr  [0:F_MAX_OUTSTANDING-1];
    reg [2:0]                  f_wq_size  [0:F_MAX_OUTSTANDING-1];
    reg [1:0]                  f_wq_burst [0:F_MAX_OUTSTANDING-1];
    reg [WQ_CNT_W-1:0]         f_wq_cnt;

    // Active (partially transferred) write burst
    reg                        f_w_active;
    reg [8:0]                  f_w_beat;   // beats already accepted
    reg [C_AXI_ID_WIDTH-1:0]   f_w_id_r;
    reg [7:0]                  f_w_len_r;
    reg [C_AXI_ADDR_WIDTH-1:0] f_w_addr_r; // address of the NEXT beat
    reg [2:0]                  f_w_size_r;
    reg [1:0]                  f_w_burst_r;

    // Current-beat view: active burst, else queue head, else same-cycle AW
    wire f_w_head_valid = f_w_active || (f_wq_cnt != 0) || aw_accepted;
    wire [C_AXI_ID_WIDTH-1:0]   f_w_cur_id    = f_w_active ? f_w_id_r
                                              : (f_wq_cnt != 0) ? f_wq_id[0]    : i_axi_awid;
    wire [7:0]                  f_w_cur_len   = f_w_active ? f_w_len_r
                                              : (f_wq_cnt != 0) ? f_wq_len[0]   : i_axi_awlen;
    wire [C_AXI_ADDR_WIDTH-1:0] f_w_cur_addr  = f_w_active ? f_w_addr_r
                                              : (f_wq_cnt != 0) ? f_wq_addr[0]  : i_axi_awaddr;
    wire [2:0]                  f_w_cur_size  = f_w_active ? f_w_size_r
                                              : (f_wq_cnt != 0) ? f_wq_size[0]  : i_axi_awsize;
    wire [1:0]                  f_w_cur_burst = f_w_active ? f_w_burst_r
                                              : (f_wq_cnt != 0) ? f_wq_burst[0] : i_axi_awburst;
    wire [8:0]                  f_w_beat_idx  = f_w_active ? f_w_beat : 9'd0;

    // W4 — legal strobe window for the current beat: bytes from the beat
    // address up to the end of its size-aligned container. The first beat
    // of a burst may start unaligned; later beats are container-aligned.
    reg [STRB_W-1:0] f_w_strb_mask;
    reg [31:0] f_w_lane_lo, f_w_lane_hi;
    integer f_bi;
    always @(*) begin
        f_w_lane_lo = {{(32-ADDR_LSB){1'b0}}, f_w_cur_addr[ADDR_LSB-1:0]};
        f_w_lane_hi = (f_w_lane_lo & ~((32'h1 << f_w_cur_size) - 1))
                      + (32'h1 << f_w_cur_size) - 32'h1;
        f_w_strb_mask = {STRB_W{1'b0}};
        for (f_bi = 0; f_bi < STRB_W; f_bi = f_bi + 1)
            if ((f_bi >= f_w_lane_lo) && (f_bi <= f_w_lane_hi))
                f_w_strb_mask[f_bi] = 1'b1;
    end

    // Next-beat address (INCR/WRAP stepping; FIXED repeats)
    wire [C_AXI_ADDR_WIDTH-1:0] f_w_container = ({24'h0, f_w_cur_len} + 32'd1) << f_w_cur_size;
    wire [C_AXI_ADDR_WIDTH-1:0] f_w_incr_addr =
        (f_w_cur_addr & ~((32'h1 << f_w_cur_size) - 1)) + (32'h1 << f_w_cur_size);
    wire [C_AXI_ADDR_WIDTH-1:0] f_w_next_addr =
        (f_w_cur_burst == 2'b00) ? f_w_cur_addr :               // FIXED
        (f_w_cur_burst == 2'b10) ?                              // WRAP
            ((f_w_cur_addr & ~(f_w_container - 1)) | (f_w_incr_addr & (f_w_container - 1))) :
        f_w_incr_addr;                                          // INCR

    always @(*) if (i_axi_reset_n && i_axi_wvalid) begin
        // W2/W3 — every W beat belongs to an accepted (or same-cycle) AW
        `AXI4_MASTER_RULE(f_w_head_valid);
        if (f_w_head_valid) begin
            // W1/B7 — WLAST exactly on the final beat
            `AXI4_MASTER_RULE(i_axi_wlast == (f_w_beat_idx == {1'b0, f_w_cur_len}));
            // W4 — strobes only inside the addressed window
            `AXI4_MASTER_RULE((i_axi_wstrb & ~f_w_strb_mask) == {STRB_W{1'b0}});
        end
    end

    // Tracking-capacity bound (checker limitation, not a protocol rule):
    // raise F_MAX_OUTSTANDING if a real design needs more.
    always @(*) if (i_axi_reset_n)
        `AXI4_MASTER_RULE(!(i_axi_awvalid && f_wq_cnt == F_MAX_OUTSTANDING[WQ_CNT_W-1:0]));

    // Per-ID completed-but-unresponded write bursts (for W5/W6/W7)
    reg [7:0] f_wr_pend [0:NUM_IDS-1];

    wire f_w_burst_done = w_accepted && i_axi_wlast && f_w_head_valid;

    // W5/W6/W7 — a B response requires a completed write burst of that ID
    // (same-cycle completion allowed: BVALID may follow WLAST combinationally)
    always @(*) if (i_axi_reset_n && i_axi_bvalid) begin
        `AXI4_SLAVE_RULE((f_wr_pend[i_axi_bid] != 8'd0)
                      || (f_w_burst_done && (f_w_cur_id == i_axi_bid)));
        if (F_OPT_EXCLUSIVE == 0)
            `AXI4_SLAVE_RULE(i_axi_bresp != 2'b01);               // P2 (no EXOKAY)
    end

    integer f_wi;
    reg f_w_pop, f_w_push;
    always @(posedge i_clk) begin
        if (!i_axi_reset_n) begin
            f_wq_cnt   <= {WQ_CNT_W{1'b0}};
            f_w_active <= 1'b0;
            f_w_beat   <= 9'd0;
            for (f_wi = 0; f_wi < NUM_IDS; f_wi = f_wi + 1)
                f_wr_pend[f_wi] <= 8'd0;
        end else begin
            // Active-burst progress
            if (w_accepted && f_w_head_valid) begin
                if (i_axi_wlast) begin
                    f_w_active <= 1'b0;
                    f_w_beat   <= 9'd0;
                end else begin
                    f_w_active  <= 1'b1;
                    f_w_beat    <= f_w_beat_idx + 9'd1;
                    f_w_id_r    <= f_w_cur_id;
                    f_w_len_r   <= f_w_cur_len;
                    f_w_size_r  <= f_w_cur_size;
                    f_w_burst_r <= f_w_cur_burst;
                    f_w_addr_r  <= f_w_next_addr;
                end
            end

            // Queue pop (head consumed by a starting burst) / push (new AW)
            f_w_pop  = w_accepted && !f_w_active && (f_wq_cnt != 0);
            f_w_push = aw_accepted
                       && !(w_accepted && !f_w_active && (f_wq_cnt == 0)); // consumed live
            if (f_w_pop)
                for (f_wi = 0; f_wi < F_MAX_OUTSTANDING - 1; f_wi = f_wi + 1) begin
                    f_wq_id[f_wi]    <= f_wq_id[f_wi+1];
                    f_wq_len[f_wi]   <= f_wq_len[f_wi+1];
                    f_wq_addr[f_wi]  <= f_wq_addr[f_wi+1];
                    f_wq_size[f_wi]  <= f_wq_size[f_wi+1];
                    f_wq_burst[f_wi] <= f_wq_burst[f_wi+1];
                end
            if (f_w_push) begin
                f_wq_id[f_w_pop ? f_wq_cnt - 1'b1 : f_wq_cnt]    <= i_axi_awid;
                f_wq_len[f_w_pop ? f_wq_cnt - 1'b1 : f_wq_cnt]   <= i_axi_awlen;
                f_wq_addr[f_w_pop ? f_wq_cnt - 1'b1 : f_wq_cnt]  <= i_axi_awaddr;
                f_wq_size[f_w_pop ? f_wq_cnt - 1'b1 : f_wq_cnt]  <= i_axi_awsize;
                f_wq_burst[f_w_pop ? f_wq_cnt - 1'b1 : f_wq_cnt] <= i_axi_awburst;
            end
            f_wq_cnt <= f_wq_cnt - (f_w_pop ? 1'b1 : 1'b0) + (f_w_push ? 1'b1 : 1'b0);

            // Per-ID completed/responded bookkeeping
            for (f_wi = 0; f_wi < NUM_IDS; f_wi = f_wi + 1)
                f_wr_pend[f_wi] <= f_wr_pend[f_wi]
                    + ((f_w_burst_done && (f_w_cur_id == f_wi[C_AXI_ID_WIDTH-1:0])) ? 8'd1 : 8'd0)
                    - ((b_accepted && (i_axi_bid == f_wi[C_AXI_ID_WIDTH-1:0])) ? 8'd1 : 8'd0);
        end
    end

    // ------------------------------------------------------------------
    // Read transaction tracking (RD1–RD5, B7 for reads, per-ID).
    //
    // Per-ID FIFOs of expected burst lengths give RD2/RD4/RD5 for free:
    // beats are matched by RID, same-ID bursts complete in issue order,
    // and cross-ID interleaving is naturally permitted.
    // ------------------------------------------------------------------
    reg [7:0]          f_rq_len   [0:NUM_IDS-1][0:F_MAX_PER_ID-1];
    reg [RQ_CNT_W-1:0] f_rq_cnt   [0:NUM_IDS-1];
    reg                f_r_active [0:NUM_IDS-1];
    reg [7:0]          f_r_len    [0:NUM_IDS-1];
    reg [8:0]          f_r_beat   [0:NUM_IDS-1];

    // Current-beat view for the responding ID (same-cycle AR allowed)
    wire f_r_head_valid = f_r_active[i_axi_rid] || (f_rq_cnt[i_axi_rid] != 0)
                       || (ar_accepted && (i_axi_arid == i_axi_rid));
    wire [7:0] f_r_cur_len  = f_r_active[i_axi_rid] ? f_r_len[i_axi_rid]
                            : (f_rq_cnt[i_axi_rid] != 0) ? f_rq_len[i_axi_rid][0]
                            : i_axi_arlen;
    wire [8:0] f_r_beat_idx = f_r_active[i_axi_rid] ? f_r_beat[i_axi_rid] : 9'd0;

    always @(*) if (i_axi_reset_n && i_axi_rvalid) begin
        // RD3 — no read data without an accepted request of this ID
        `AXI4_SLAVE_RULE(f_r_head_valid);
        if (f_r_head_valid)
            // RD1/B7 — RLAST exactly on the final beat of this ID's burst
            `AXI4_SLAVE_RULE(i_axi_rlast == (f_r_beat_idx == {1'b0, f_r_cur_len}));
        if (F_OPT_EXCLUSIVE == 0)
            `AXI4_SLAVE_RULE(i_axi_rresp != 2'b01);                   // P2 (no EXOKAY)
    end

    // Tracking-capacity bound per ID (checker limitation)
    always @(*) if (i_axi_reset_n)
        `AXI4_MASTER_RULE(!(i_axi_arvalid
                            && f_rq_cnt[i_axi_arid] == F_MAX_PER_ID[RQ_CNT_W-1:0]));

    integer f_ri, f_rk;
    reg f_r_pop, f_r_samec, f_r_push;
    always @(posedge i_clk) begin
        if (!i_axi_reset_n) begin
            for (f_ri = 0; f_ri < NUM_IDS; f_ri = f_ri + 1) begin
                f_rq_cnt[f_ri]   <= {RQ_CNT_W{1'b0}};
                f_r_active[f_ri] <= 1'b0;
                f_r_beat[f_ri]   <= 9'd0;
            end
        end else begin
            // Beat progress for the responding ID
            if (r_accepted && f_r_head_valid) begin
                if (i_axi_rlast) begin
                    f_r_active[i_axi_rid] <= 1'b0;
                    f_r_beat[i_axi_rid]   <= 9'd0;
                end else begin
                    f_r_active[i_axi_rid] <= 1'b1;
                    f_r_beat[i_axi_rid]   <= f_r_beat_idx + 9'd1;
                    f_r_len[i_axi_rid]    <= f_r_cur_len;
                end
            end

            // Queue pop (burst started from queue head) / push (new AR)
            f_r_pop   = r_accepted && !f_r_active[i_axi_rid] && (f_rq_cnt[i_axi_rid] != 0);
            f_r_samec = r_accepted && !f_r_active[i_axi_rid] && (f_rq_cnt[i_axi_rid] == 0);
            f_r_push  = ar_accepted && !(f_r_samec && (i_axi_arid == i_axi_rid));
            if (f_r_pop)
                for (f_rk = 0; f_rk < F_MAX_PER_ID - 1; f_rk = f_rk + 1)
                    f_rq_len[i_axi_rid][f_rk] <= f_rq_len[i_axi_rid][f_rk+1];
            if (f_r_push)
                f_rq_len[i_axi_arid][(f_r_pop && (i_axi_rid == i_axi_arid))
                                     ? f_rq_cnt[i_axi_arid] - 1'b1
                                     : f_rq_cnt[i_axi_arid]] <= i_axi_arlen;
            for (f_ri = 0; f_ri < NUM_IDS; f_ri = f_ri + 1)
                f_rq_cnt[f_ri] <= f_rq_cnt[f_ri]
                    - ((f_r_pop  && (i_axi_rid  == f_ri[C_AXI_ID_WIDTH-1:0])) ? 1'b1 : 1'b0)
                    + ((f_r_push && (i_axi_arid == f_ri[C_AXI_ID_WIDTH-1:0])) ? 1'b1 : 1'b0);
        end
    end

    // ------------------------------------------------------------------
    // X3 — an exclusive write must match the preceding exclusive read
    // from the same ID (address/length/size). Only when F_OPT_EXCLUSIVE=1.
    // ------------------------------------------------------------------
    generate if (F_OPT_EXCLUSIVE != 0) begin : EXCL_MON
        reg                        f_ex_valid [0:NUM_IDS-1];
        reg [C_AXI_ADDR_WIDTH-1:0] f_ex_addr  [0:NUM_IDS-1];
        reg [7:0]                  f_ex_len   [0:NUM_IDS-1];
        reg [2:0]                  f_ex_size  [0:NUM_IDS-1];
        integer f_xi;

        always @(posedge i_clk) begin
            if (!i_axi_reset_n) begin
                for (f_xi = 0; f_xi < NUM_IDS; f_xi = f_xi + 1)
                    f_ex_valid[f_xi] <= 1'b0;
            end else if (ar_accepted && i_axi_arlock) begin
                f_ex_valid[i_axi_arid] <= 1'b1;
                f_ex_addr[i_axi_arid]  <= i_axi_araddr;
                f_ex_len[i_axi_arid]   <= i_axi_arlen;
                f_ex_size[i_axi_arid]  <= i_axi_arsize;
            end
        end

        always @(*) if (i_axi_reset_n && i_axi_awvalid && i_axi_awlock) begin
            `AXI4_MASTER_RULE(f_ex_valid[i_axi_awid]);
            if (f_ex_valid[i_axi_awid]) begin
                `AXI4_MASTER_RULE(f_ex_addr[i_axi_awid] == i_axi_awaddr);
                `AXI4_MASTER_RULE(f_ex_len[i_axi_awid]  == i_axi_awlen);
                `AXI4_MASTER_RULE(f_ex_size[i_axi_awid] == i_axi_awsize);
            end
        end
    end endgenerate

    // ------------------------------------------------------------------
    // Bounded liveness (optional, F_OPT_MAX_STALL > 0): the spec places
    // no bound on handshake waits, so these are DISABLED by default. When
    // enabled: sources must see READY within the bound (W9/RD7 for the
    // master's BREADY/RREADY; eventual-accept for the slave's AxREADY /
    // WREADY). Useful to approximate liveness under BMC.
    // ------------------------------------------------------------------
    generate if (F_OPT_MAX_STALL != 0) begin : LIVENESS
        reg [15:0] f_aw_stall, f_w_stall, f_b_stall, f_ar_stall, f_r_stall;
        always @(posedge i_clk) begin
            if (!i_axi_reset_n) begin
                f_aw_stall <= 16'd0; f_w_stall <= 16'd0; f_b_stall <= 16'd0;
                f_ar_stall <= 16'd0; f_r_stall <= 16'd0;
            end else begin
                f_aw_stall <= (i_axi_awvalid && !i_axi_awready) ? f_aw_stall + 16'd1 : 16'd0;
                f_w_stall  <= (i_axi_wvalid  && !i_axi_wready)  ? f_w_stall  + 16'd1 : 16'd0;
                f_b_stall  <= (i_axi_bvalid  && !i_axi_bready)  ? f_b_stall  + 16'd1 : 16'd0;
                f_ar_stall <= (i_axi_arvalid && !i_axi_arready) ? f_ar_stall + 16'd1 : 16'd0;
                f_r_stall  <= (i_axi_rvalid  && !i_axi_rready)  ? f_r_stall  + 16'd1 : 16'd0;
            end
        end
        always @(*) if (i_axi_reset_n) begin
            `AXI4_SLAVE_RULE(f_aw_stall < F_OPT_MAX_STALL[15:0]);  // slave must accept AW
            `AXI4_SLAVE_RULE(f_w_stall  < F_OPT_MAX_STALL[15:0]);  // slave must accept W
            `AXI4_MASTER_RULE(f_b_stall < F_OPT_MAX_STALL[15:0]);  // W9: master must take B
            `AXI4_SLAVE_RULE(f_ar_stall < F_OPT_MAX_STALL[15:0]);  // slave must accept AR
            `AXI4_MASTER_RULE(f_r_stall < F_OPT_MAX_STALL[15:0]);  // RD7: master must take R
        end
    end endgenerate
