// ============================================================================
// axi4_slave_checker — formal protocol checker for an AXI4 slave
//
// Replaces the third-party ZipCPU wb2axip faxi_master checker, whose public
// bench/formal/faxi_master.v is a deliberately non-functional teaser (its
// own header: "This subset is not intended to be functional... The full set
// of AXI4 properties may be purchased from Gisselquist Technology, LLC.").
// Also, that checker verified an AXI4 *master*; this project's IPs expose
// AXI4 as a *slave* (slaves-only bus convention), so a master-checking file
// was never the right shape for this template even before the third-party
// issue.
//
// Binds to the master-facing side of an AXI4 slave DUT:
//   assume()  — constrains the free-variable master stimulus (awvalid,
//               wvalid, arvalid, and their payloads) to obey AXI4 protocol
//               rules, so the solver only explores legal master behavior.
//   assert()  — checks the DUT's slave-driven outputs (awready, wready,
//               bvalid/bid/bresp, arready, rvalid/rid/rlast/rresp) are
//               protocol-compliant.
//
// Scope (intentionally moderate, not full AMBA AXI4 compliance):
//   - VALID/payload stability while stalled, on all five channels.
//   - No response (B or R) without a matching accepted request outstanding.
//   - VALID held low during reset, on both the master and slave sides.
// NOT covered (would need per-ID/per-burst tracking beyond this file's
// scope): burst length vs. RLAST timing, WSTRB/AWSIZE/AWBURST legality,
// exclusive access, out-of-order ID response matching, QoS/region/cache/
// prot field checks. Extend this file (or add a second checker) before
// relying on it for burst-capable or out-of-order slaves.
//
// Author: project-wide shared checker (not IP-specific; not a copier
// template — plain Verilog, parameterized by ID/address/data width).
// ============================================================================
`default_nettype none

module axi4_slave_checker #(
    parameter C_AXI_ID_WIDTH   = 4,
    parameter C_AXI_ADDR_WIDTH = 32,
    parameter C_AXI_DATA_WIDTH = 32
) (
    input wire i_clk,
    input wire i_axi_reset_n,

    // Write address channel
    input wire                        i_axi_awvalid,
    input wire                        i_axi_awready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_awid,
    input wire [C_AXI_ADDR_WIDTH-1:0] i_axi_awaddr,
    input wire [7:0]                  i_axi_awlen,

    // Write data channel
    input wire                        i_axi_wvalid,
    input wire                        i_axi_wready,
    input wire                        i_axi_wlast,

    // Write response channel
    input wire                        i_axi_bvalid,
    input wire                        i_axi_bready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_bid,
    input wire [1:0]                  i_axi_bresp,

    // Read address channel
    input wire                        i_axi_arvalid,
    input wire                        i_axi_arready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_arid,
    input wire [C_AXI_ADDR_WIDTH-1:0] i_axi_araddr,
    input wire [7:0]                  i_axi_arlen,

    // Read data channel
    input wire                        i_axi_rvalid,
    input wire                        i_axi_rready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_rid,
    input wire                        i_axi_rlast,
    input wire [1:0]                  i_axi_rresp
);

    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge i_clk)
        f_past_valid <= 1'b1;

    // ------------------------------------------------------------------
    // Reset: no request or response may be in flight while in reset.
    // ------------------------------------------------------------------
    always @(*) if (!i_axi_reset_n) begin
        assume (!i_axi_awvalid);
        assume (!i_axi_wvalid);
        assume (!i_axi_arvalid);
        assert (!i_axi_bvalid);
        assert (!i_axi_rvalid);
    end

    // ------------------------------------------------------------------
    // VALID/payload stability while stalled — AXI4 spec: once VALID is
    // asserted, it (and the associated payload) must not change until the
    // corresponding READY is seen. Master-driven channels are constrained
    // with assume; slave-driven response channels are checked with assert.
    // ------------------------------------------------------------------

    // AW channel (assume: master stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_awvalid) && !$past(i_axi_awready)) begin
            assume (i_axi_awvalid);
            assume ($stable(i_axi_awid));
            assume ($stable(i_axi_awaddr));
            assume ($stable(i_axi_awlen));
        end
    end

    // W channel (assume: master stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_wvalid) && !$past(i_axi_wready)) begin
            assume (i_axi_wvalid);
            assume ($stable(i_axi_wlast));
        end
    end

    // AR channel (assume: master stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_arvalid) && !$past(i_axi_arready)) begin
            assume (i_axi_arvalid);
            assume ($stable(i_axi_arid));
            assume ($stable(i_axi_araddr));
            assume ($stable(i_axi_arlen));
        end
    end

    // B channel (assert: DUT response)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_bvalid) && !$past(i_axi_bready)) begin
            assert (i_axi_bvalid);
            assert ($stable(i_axi_bid));
            assert ($stable(i_axi_bresp));
        end
    end

    // R channel (assert: DUT response)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_rvalid) && !$past(i_axi_rready)) begin
            assert (i_axi_rvalid);
            assert ($stable(i_axi_rid));
            assert ($stable(i_axi_rlast));
            assert ($stable(i_axi_rresp));
        end
    end

    // ------------------------------------------------------------------
    // No spurious response: BVALID/RVALID must not fire without a
    // matching accepted request outstanding. Tracks accepted-but-not-yet-
    // responded-to write/read requests; does not verify ID matching or
    // response ordering (see NOT covered, above).
    // ------------------------------------------------------------------
    localparam F_CNT_WIDTH = 8;

    reg [F_CNT_WIDTH-1:0] f_outstanding_wr;
    reg [F_CNT_WIDTH-1:0] f_outstanding_rd;

    wire aw_accepted = i_axi_awvalid && i_axi_awready;
    wire b_accepted  = i_axi_bvalid  && i_axi_bready;
    wire ar_accepted = i_axi_arvalid && i_axi_arready;
    wire r_accepted  = i_axi_rvalid  && i_axi_rready && i_axi_rlast;

    always @(posedge i_clk) begin
        if (!i_axi_reset_n) begin
            f_outstanding_wr <= {F_CNT_WIDTH{1'b0}};
            f_outstanding_rd <= {F_CNT_WIDTH{1'b0}};
        end else begin
            f_outstanding_wr <= f_outstanding_wr + aw_accepted - b_accepted;
            f_outstanding_rd <= f_outstanding_rd + ar_accepted - r_accepted;
        end
    end

    always @(posedge i_clk) if (f_past_valid && i_axi_reset_n) begin
        assert (f_outstanding_wr != {F_CNT_WIDTH{1'b1}}); // no underflow
        assert (f_outstanding_rd != {F_CNT_WIDTH{1'b1}}); // no underflow
        // A response this cycle needs either a request already outstanding
        // before this cycle, or one being accepted this same cycle.
        if (i_axi_bvalid) assert (f_outstanding_wr != 0 || aw_accepted);
        if (i_axi_rvalid) assert (f_outstanding_rd != 0 || ar_accepted);
    end

endmodule
`default_nettype wire
