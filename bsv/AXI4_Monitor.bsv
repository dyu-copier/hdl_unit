// ============================================================================
// AXI4_Monitor — dynamic (simulation-time) AXI4 protocol checker in BSV
//
// The Bluespec counterpart of formal/checkers/axi4_{slave,master}_checker.v:
// the same AXI4 rule set (rule IDs refer to AXI4_rules.md at the repo root),
// enforced with dynamicAssert at simulation time in Bluesim / Verilog sim.
// One shared checker core (mkAXI4_ProtocolChecker) implements the rules; two
// pass-through taps bind it to either side:
//
//   mkAXI4_SlaveMonitor  (tag, dut_slave_ifc)  -> AXI4_Slave_IFC
//       wraps the DUT's AXI4 *slave* port (e.g. the xactor's axi_side)
//   mkAXI4_MasterMonitor (tag, dut_master_ifc) -> AXI4_Master_IFC
//       wraps the DUT's AXI4 *master* port
//
// Hookup example (inside mk<Ip>, sim/debug builds only):
//
//     AXI4_Slave_IFC#(4,32,32,0) mon_s <-
//         mkAXI4_SlaveMonitor("axi4_s", xactor_s.axi_side);
//     interface axi4_s = mon_s;   // instead of xactor_s.axi_side
//
// The monitor is OPT-IN and sim-only: it adds tracking state and $fatal-on-
// violation behavior, so do not leave it in the synthesized netlist that
// goes to PnR. It is compile-checked (bsc -u, .bo only) by bsv/Makefile.
//
// Rules covered: H1/H2 (VALID hold + full payload stability, all five
// channels), W1/W2 (WLAST vs AWLEN, in-order write data), W4 (WSTRB window),
// W5/W6/W7 (per-ID response accounting), RD1-RD5 (per-ID RLAST/ordering),
// B1-B6 (burst legality), P2 (no EXOKAY), X1 (exclusive not supported —
// AxLOCK must be 0), plus tracking-capacity guards (4 outstanding write
// bursts, 2 read bursts per ID — mirrors the Verilog checkers' defaults).
// Reset rules R3/R4 are NOT checked here (the monitor shares the DUT's
// reset); they are covered by the yosys checkers.
//
// Fixed at the template's configuration: ID=4, ADDR=32, DATA=32, USER=0.
// ============================================================================
package AXI4_Monitor;

import Vector     :: *;
import Assert     :: *;
import AXI4_Types :: *;

// ----------------------------------------------------------------------------
// One cycle's view of every AXI4 signal (user signals omitted, USER=0)
// ----------------------------------------------------------------------------
typedef struct {
   Bool     awvalid;  Bool     awready;
   Bit#(4)  awid;     Bit#(32) awaddr;  Bit#(8) awlen;   Bit#(3) awsize;
   Bit#(2)  awburst;  Bit#(1)  awlock;  Bit#(4) awcache; Bit#(3) awprot;
   Bit#(4)  awqos;    Bit#(4)  awregion;
   Bool     wvalid;   Bool     wready;
   Bit#(32) wdata;    Bit#(4)  wstrb;   Bool    wlast;
   Bool     bvalid;   Bool     bready;  Bit#(4) bid;     Bit#(2) bresp;
   Bool     arvalid;  Bool     arready;
   Bit#(4)  arid;     Bit#(32) araddr;  Bit#(8) arlen;   Bit#(3) arsize;
   Bit#(2)  arburst;  Bit#(1)  arlock;  Bit#(4) arcache; Bit#(3) arprot;
   Bit#(4)  arqos;    Bit#(4)  arregion;
   Bool     rvalid;   Bool     rready;  Bit#(4) rid;     Bit#(32) rdata;
   Bit#(2)  rresp;    Bool     rlast;
} AXI4_MonSigs deriving (Bits, FShow);

typedef struct {
   Bit#(4) id; Bit#(8) len; Bit#(32) addr; Bit#(3) size; Bit#(2) burst;
} AXI4_MonWEntry deriving (Bits, FShow);

interface AXI4_ProtocolChecker_IFC;
   method Action observe (AXI4_MonSigs s);
endinterface

// W4 — legal strobe lanes for a beat at `addr` of `size` (32-bit data bus)
function Bit#(4) fn_strb_mask (Bit#(32) addr, Bit#(3) size);
   Bit#(3) lo   = zeroExtend(addr[1:0]);
   Bit#(3) span = (size == 0) ? 3'd1 : ((size == 1) ? 3'd2 : 3'd4);
   Bit#(3) base = lo & ~(span - 1);
   Bit#(3) hi   = base + span - 1;
   Bit#(4) m    = 0;
   for (Integer i = 0; i < 4; i = i + 1)
      if ((fromInteger(i) >= lo) && (fromInteger(i) <= hi))
         m[i] = 1'b1;
   return m;
endfunction

// Next beat address: FIXED repeats, INCR steps aligned, WRAP wraps in-container
function Bit#(32) fn_next_addr (Bit#(32) addr, Bit#(3) size, Bit#(2) burst,
                                Bit#(8) len);
   Bit#(32) span      = 32'h1 << size;
   Bit#(32) incr      = (addr & ~(span - 1)) + span;
   Bit#(32) container = (zeroExtend(len) + 32'h1) << size;
   return (burst == 2'b00) ? addr
        : (burst == 2'b10) ? ((addr & ~(container - 1)) | (incr & (container - 1)))
        : incr;
endfunction

// B1-B6 + X1 — address-channel legality (applies to AW and AR alike)
function Action fa_check_addr_channel (String msg_pfx, Bit#(32) addr,
                                       Bit#(8) len, Bit#(3) size,
                                       Bit#(2) burst, Bit#(1) lock);
   action
      dynamicAssert(burst != 2'b11,
                    strConcat(msg_pfx, "B1: reserved burst type 2'b11"));
      dynamicAssert(size <= 3'd2,
                    strConcat(msg_pfx, "B5: AxSIZE exceeds 32-bit data bus"));
      if (burst != 2'b01)
         dynamicAssert(len[7:4] == 4'h0,
                       strConcat(msg_pfx, "B2: FIXED/WRAP burst longer than 16 beats"));
      if (burst == 2'b10) begin
         dynamicAssert((len == 8'd1) || (len == 8'd3) || (len == 8'd7) || (len == 8'd15),
                       strConcat(msg_pfx, "B3: WRAP length not 2/4/8/16"));
         dynamicAssert((addr & ((32'h1 << size) - 1)) == 0,
                       strConcat(msg_pfx, "B4: WRAP address not size-aligned"));
      end
      if (burst == 2'b01) begin
         Bit#(16) nbytes = (zeroExtend(len) + 16'h1) << size;
         dynamicAssert(({4'h0, addr[11:0]} + nbytes) <= 16'd4096,
                       strConcat(msg_pfx, "B6: burst crosses a 4KB boundary"));
      end
      dynamicAssert(lock == 1'b0,
                    strConcat(msg_pfx, "X1: exclusive access not supported by this monitor"));
   endaction
endfunction

// ----------------------------------------------------------------------------
// Shared rule engine — mirrors formal/checkers/axi4_checker_rules.vh
// (capacity: 4 outstanding write bursts, 2 read bursts per ID)
// ----------------------------------------------------------------------------
module mkAXI4_ProtocolChecker #(String tag) (AXI4_ProtocolChecker_IFC);

   Reg#(Maybe#(AXI4_MonSigs)) rg_prev <- mkReg(tagged Invalid);

   // Write-side tracking: in-order queue of accepted AWs + active burst
   Vector#(4, Reg#(AXI4_MonWEntry)) vrg_wq <- replicateM(mkRegU);
   Reg#(Bit#(3))        rg_wq_cnt  <- mkReg(0);
   Reg#(Bool)           rg_w_active <- mkReg(False);
   Reg#(AXI4_MonWEntry) rg_w_cur   <- mkRegU;   // .addr = next-beat address
   Reg#(Bit#(9))        rg_w_beat  <- mkReg(0);
   Vector#(16, Reg#(Bit#(8))) vrg_wr_pend <- replicateM(mkReg(0));

   // Read-side tracking: per-ID queue (depth 2) + per-ID active burst
   Vector#(16, Vector#(2, Reg#(Bit#(8)))) vrg_rq_len <- replicateM(replicateM(mkRegU));
   Vector#(16, Reg#(Bit#(2))) vrg_rq_cnt   <- replicateM(mkReg(0));
   Vector#(16, Reg#(Bool))    vrg_r_active <- replicateM(mkReg(False));
   Vector#(16, Reg#(Bit#(8))) vrg_r_len    <- replicateM(mkRegU);
   Vector#(16, Reg#(Bit#(9))) vrg_r_beat   <- replicateM(mkReg(0));

   method Action observe (AXI4_MonSigs s);
      // ---------- H1/H2 — VALID hold + payload stability vs previous cycle
      if (rg_prev matches tagged Valid .p) begin
         if (p.awvalid && !p.awready) begin
            dynamicAssert(s.awvalid, strConcat(tag, " H1: AWVALID dropped while stalled"));
            dynamicAssert((s.awid == p.awid) && (s.awaddr == p.awaddr)
                       && (s.awlen == p.awlen) && (s.awsize == p.awsize)
                       && (s.awburst == p.awburst) && (s.awlock == p.awlock)
                       && (s.awcache == p.awcache) && (s.awprot == p.awprot)
                       && (s.awqos == p.awqos) && (s.awregion == p.awregion),
                          strConcat(tag, " H2: AW payload changed while stalled"));
         end
         if (p.wvalid && !p.wready) begin
            dynamicAssert(s.wvalid, strConcat(tag, " H1: WVALID dropped while stalled"));
            dynamicAssert((s.wdata == p.wdata) && (s.wstrb == p.wstrb)
                       && (s.wlast == p.wlast),
                          strConcat(tag, " H2: W payload changed while stalled"));
         end
         if (p.bvalid && !p.bready) begin
            dynamicAssert(s.bvalid, strConcat(tag, " H1: BVALID dropped while stalled"));
            dynamicAssert((s.bid == p.bid) && (s.bresp == p.bresp),
                          strConcat(tag, " H2: B payload changed while stalled"));
         end
         if (p.arvalid && !p.arready) begin
            dynamicAssert(s.arvalid, strConcat(tag, " H1: ARVALID dropped while stalled"));
            dynamicAssert((s.arid == p.arid) && (s.araddr == p.araddr)
                       && (s.arlen == p.arlen) && (s.arsize == p.arsize)
                       && (s.arburst == p.arburst) && (s.arlock == p.arlock)
                       && (s.arcache == p.arcache) && (s.arprot == p.arprot)
                       && (s.arqos == p.arqos) && (s.arregion == p.arregion),
                          strConcat(tag, " H2: AR payload changed while stalled"));
         end
         if (p.rvalid && !p.rready) begin
            dynamicAssert(s.rvalid, strConcat(tag, " H1: RVALID dropped while stalled"));
            dynamicAssert((s.rid == p.rid) && (s.rdata == p.rdata)
                       && (s.rresp == p.rresp) && (s.rlast == p.rlast),
                          strConcat(tag, " H2: R payload changed while stalled"));
         end
      end
      rg_prev <= tagged Valid s;

      Bool aw_acc = s.awvalid && s.awready;
      Bool w_acc  = s.wvalid  && s.wready;
      Bool b_acc  = s.bvalid  && s.bready;
      Bool ar_acc = s.arvalid && s.arready;
      Bool r_acc  = s.rvalid  && s.rready;

      // ---------- B1-B6 / X1 — address-channel legality
      if (s.awvalid)
         fa_check_addr_channel(strConcat(tag, " AW "), s.awaddr, s.awlen,
                               s.awsize, s.awburst, s.awlock);
      if (s.arvalid)
         fa_check_addr_channel(strConcat(tag, " AR "), s.araddr, s.arlen,
                               s.arsize, s.arburst, s.arlock);

      // ---------- Write transaction rules (W1/W2/W4/W5/W6/W7)
      AXI4_MonWEntry live_aw = AXI4_MonWEntry { id: s.awid, len: s.awlen,
                                                addr: s.awaddr, size: s.awsize,
                                                burst: s.awburst };
      Bool w_head_valid = rg_w_active || (rg_wq_cnt != 0) || aw_acc;
      AXI4_MonWEntry w_cur = rg_w_active ? rg_w_cur
                           : ((rg_wq_cnt != 0) ? vrg_wq[0] : live_aw);
      Bit#(9) w_beat_idx = rg_w_active ? rg_w_beat : 0;

      dynamicAssert(!(s.awvalid && (rg_wq_cnt == 4)),
                    strConcat(tag, " capacity: >4 outstanding write bursts (raise monitor depth)"));

      if (s.wvalid) begin
         dynamicAssert(w_head_valid,
                       strConcat(tag, " W2/W3: write data with no accepted write address"));
         if (w_head_valid) begin
            dynamicAssert(s.wlast == (w_beat_idx == zeroExtend(w_cur.len)),
                          strConcat(tag, " W1: WLAST does not match AWLEN"));
            dynamicAssert((s.wstrb & ~fn_strb_mask(w_cur.addr, w_cur.size)) == 0,
                          strConcat(tag, " W4: WSTRB outside the addressed byte lanes"));
         end
      end

      Bool w_burst_done = w_acc && s.wlast && w_head_valid;

      if (s.bvalid) begin
         Bit#(8) pend_bid = readVReg(vrg_wr_pend)[s.bid];
         dynamicAssert((pend_bid != 0) || (w_burst_done && (w_cur.id == s.bid)),
                       strConcat(tag, " W5/W6: B response with no completed write of that ID"));
         dynamicAssert(s.bresp != 2'b01,
                       strConcat(tag, " P2: EXOKAY response without exclusive access"));
      end

      // Write-side state updates
      if (w_acc && w_head_valid) begin
         if (s.wlast) begin
            rg_w_active <= False;
            rg_w_beat   <= 0;
         end else begin
            let nxt = w_cur;
            nxt.addr = fn_next_addr(w_cur.addr, w_cur.size, w_cur.burst, w_cur.len);
            rg_w_active <= True;
            rg_w_beat   <= w_beat_idx + 1;
            rg_w_cur    <= nxt;
         end
      end
      Bool w_pop  = w_acc && !rg_w_active && (rg_wq_cnt != 0);
      Bool w_push = aw_acc && !(w_acc && !rg_w_active && (rg_wq_cnt == 0));
      Bit#(3) w_push_idx = w_pop ? rg_wq_cnt - 1 : rg_wq_cnt;
      for (Integer i = 0; i < 4; i = i + 1) begin
         AXI4_MonWEntry nv = vrg_wq[i];
         if (w_pop && (i < 3)) nv = vrg_wq[i + 1];
         if (w_push && (w_push_idx == fromInteger(i))) nv = live_aw;
         if (w_pop || w_push) vrg_wq[i] <= nv;
      end
      rg_wq_cnt <= rg_wq_cnt - (w_pop ? 1 : 0) + (w_push ? 1 : 0);
      for (Integer i = 0; i < 16; i = i + 1) begin
         Bit#(8) nv = vrg_wr_pend[i];
         if (w_burst_done && (w_cur.id == fromInteger(i))) nv = nv + 1;
         if (b_acc && (s.bid == fromInteger(i)))           nv = nv - 1;
         vrg_wr_pend[i] <= nv;
      end

      // ---------- Read transaction rules (RD1-RD5), per ID
      dynamicAssert(!(s.arvalid && (readVReg(vrg_rq_cnt)[s.arid] == 2)),
                    strConcat(tag, " capacity: >2 outstanding read bursts on one ID (raise monitor depth)"));

      Vector#(16, Vector#(2, Bit#(8))) rq_vals = map(readVReg, vrg_rq_len);
      Bool    r_active_rid = readVReg(vrg_r_active)[s.rid];
      Bit#(2) rq_cnt_rid   = readVReg(vrg_rq_cnt)[s.rid];
      Bool    r_head_valid = r_active_rid || (rq_cnt_rid != 0)
                          || (ar_acc && (s.arid == s.rid));
      Bit#(8) r_cur_len  = r_active_rid ? readVReg(vrg_r_len)[s.rid]
                         : ((rq_cnt_rid != 0) ? rq_vals[s.rid][0] : s.arlen);
      Bit#(9) r_beat_idx = r_active_rid ? readVReg(vrg_r_beat)[s.rid] : 0;

      if (s.rvalid) begin
         dynamicAssert(r_head_valid,
                       strConcat(tag, " RD3: read data with no accepted read of that ID"));
         if (r_head_valid)
            dynamicAssert(s.rlast == (r_beat_idx == zeroExtend(r_cur_len)),
                          strConcat(tag, " RD1: RLAST does not match ARLEN"));
         dynamicAssert(s.rresp != 2'b01,
                       strConcat(tag, " P2: EXOKAY response without exclusive access"));
      end

      // Read-side state updates
      Bool r_pop   = r_acc && !r_active_rid && (rq_cnt_rid != 0);
      Bool r_samec = r_acc && !r_active_rid && (rq_cnt_rid == 0);
      Bool r_push  = ar_acc && !(r_samec && (s.arid == s.rid));
      for (Integer i = 0; i < 16; i = i + 1) begin
         Bool    popi  = r_pop  && (s.rid  == fromInteger(i));
         Bool    pushi = r_push && (s.arid == fromInteger(i));
         // active burst progress
         Bool    nact  = vrg_r_active[i];
         Bit#(9) nbeat = vrg_r_beat[i];
         Bit#(8) nlen  = vrg_r_len[i];
         if (r_acc && r_head_valid && (s.rid == fromInteger(i))) begin
            if (s.rlast) begin
               nact  = False;
               nbeat = 0;
            end else begin
               nact  = True;
               nbeat = r_beat_idx + 1;
               nlen  = r_cur_len;
            end
         end
         vrg_r_active[i] <= nact;
         vrg_r_beat[i]   <= nbeat;
         vrg_r_len[i]    <= nlen;
         // per-ID length queue
         Bit#(8) q0 = vrg_rq_len[i][0];
         Bit#(8) q1 = vrg_rq_len[i][1];
         Bit#(2) nc = vrg_rq_cnt[i];
         if (popi) q0 = q1;
         if (pushi) begin
            Bit#(2) idx = popi ? nc - 1 : nc;
            if (idx == 0) q0 = s.arlen;
            else          q1 = s.arlen;
         end
         nc = nc - (popi ? 1 : 0) + (pushi ? 1 : 0);
         vrg_rq_len[i][0] <= q0;
         vrg_rq_len[i][1] <= q1;
         vrg_rq_cnt[i]    <= nc;
      end
   endmethod

endmodule

// ----------------------------------------------------------------------------
// Pass-through tap for a DUT AXI4 SLAVE port. The environment (master) side
// calls the returned interface exactly as it would the DUT's; every signal
// is forwarded unchanged and observed by the checker.
// ----------------------------------------------------------------------------
module mkAXI4_SlaveMonitor #(String tag, AXI4_Slave_IFC#(4,32,32,0) s)
                            (AXI4_Slave_IFC#(4,32,32,0));

   AXI4_ProtocolChecker_IFC chk <- mkAXI4_ProtocolChecker(tag);

   // Master-driven signals, captured by the forwarding Action methods
   Wire#(Bool)     w_awvalid  <- mkDWire(False);
   Wire#(Bit#(4))  w_awid     <- mkDWire(0);
   Wire#(Bit#(32)) w_awaddr   <- mkDWire(0);
   Wire#(Bit#(8))  w_awlen    <- mkDWire(0);
   Wire#(Bit#(3))  w_awsize   <- mkDWire(0);
   Wire#(Bit#(2))  w_awburst  <- mkDWire(0);
   Wire#(Bit#(1))  w_awlock   <- mkDWire(0);
   Wire#(Bit#(4))  w_awcache  <- mkDWire(0);
   Wire#(Bit#(3))  w_awprot   <- mkDWire(0);
   Wire#(Bit#(4))  w_awqos    <- mkDWire(0);
   Wire#(Bit#(4))  w_awregion <- mkDWire(0);
   Wire#(Bool)     w_wvalid   <- mkDWire(False);
   Wire#(Bit#(32)) w_wdata    <- mkDWire(0);
   Wire#(Bit#(4))  w_wstrb    <- mkDWire(0);
   Wire#(Bool)     w_wlast    <- mkDWire(False);
   Wire#(Bool)     w_bready   <- mkDWire(False);
   Wire#(Bool)     w_arvalid  <- mkDWire(False);
   Wire#(Bit#(4))  w_arid     <- mkDWire(0);
   Wire#(Bit#(32)) w_araddr   <- mkDWire(0);
   Wire#(Bit#(8))  w_arlen    <- mkDWire(0);
   Wire#(Bit#(3))  w_arsize   <- mkDWire(0);
   Wire#(Bit#(2))  w_arburst  <- mkDWire(0);
   Wire#(Bit#(1))  w_arlock   <- mkDWire(0);
   Wire#(Bit#(4))  w_arcache  <- mkDWire(0);
   Wire#(Bit#(3))  w_arprot   <- mkDWire(0);
   Wire#(Bit#(4))  w_arqos    <- mkDWire(0);
   Wire#(Bit#(4))  w_arregion <- mkDWire(0);
   Wire#(Bool)     w_rready   <- mkDWire(False);

   (* fire_when_enabled, no_implicit_conditions *)
   rule rl_observe;
      chk.observe(AXI4_MonSigs {
         awvalid:  w_awvalid,  awready:  s.m_awready,
         awid:     w_awid,     awaddr:   w_awaddr,   awlen:  w_awlen,
         awsize:   w_awsize,   awburst:  w_awburst,  awlock: w_awlock,
         awcache:  w_awcache,  awprot:   w_awprot,   awqos:  w_awqos,
         awregion: w_awregion,
         wvalid:   w_wvalid,   wready:   s.m_wready,
         wdata:    w_wdata,    wstrb:    w_wstrb,    wlast:  w_wlast,
         bvalid:   s.m_bvalid, bready:   w_bready,
         bid:      s.m_bid,    bresp:    s.m_bresp,
         arvalid:  w_arvalid,  arready:  s.m_arready,
         arid:     w_arid,     araddr:   w_araddr,   arlen:  w_arlen,
         arsize:   w_arsize,   arburst:  w_arburst,  arlock: w_arlock,
         arcache:  w_arcache,  arprot:   w_arprot,   arqos:  w_arqos,
         arregion: w_arregion,
         rvalid:   s.m_rvalid, rready:   w_rready,
         rid:      s.m_rid,    rdata:    s.m_rdata,
         rresp:    s.m_rresp,  rlast:    s.m_rlast });
   endrule

   method Action m_awvalid (Bool awvalid, Bit#(4) awid, Bit#(32) awaddr,
                            Bit#(8) awlen, AXI4_Size awsize, Bit#(2) awburst,
                            Bit#(1) awlock, Bit#(4) awcache, Bit#(3) awprot,
                            Bit#(4) awqos, Bit#(4) awregion, Bit#(0) awuser);
      s.m_awvalid(awvalid, awid, awaddr, awlen, awsize, awburst, awlock,
                  awcache, awprot, awqos, awregion, awuser);
      w_awvalid  <= awvalid;  w_awid    <= awid;    w_awaddr <= awaddr;
      w_awlen    <= awlen;    w_awsize  <= awsize;  w_awburst <= awburst;
      w_awlock   <= awlock;   w_awcache <= awcache; w_awprot <= awprot;
      w_awqos    <= awqos;    w_awregion <= awregion;
   endmethod
   method m_awready = s.m_awready;

   method Action m_wvalid (Bool wvalid, Bit#(32) wdata, Bit#(4) wstrb,
                           Bool wlast, Bit#(0) wuser);
      s.m_wvalid(wvalid, wdata, wstrb, wlast, wuser);
      w_wvalid <= wvalid; w_wdata <= wdata; w_wstrb <= wstrb; w_wlast <= wlast;
   endmethod
   method m_wready = s.m_wready;

   method m_bvalid = s.m_bvalid;
   method m_bid    = s.m_bid;
   method m_bresp  = s.m_bresp;
   method m_buser  = s.m_buser;
   method Action m_bready (Bool bready);
      s.m_bready(bready);
      w_bready <= bready;
   endmethod

   method Action m_arvalid (Bool arvalid, Bit#(4) arid, Bit#(32) araddr,
                            Bit#(8) arlen, AXI4_Size arsize, Bit#(2) arburst,
                            Bit#(1) arlock, Bit#(4) arcache, Bit#(3) arprot,
                            Bit#(4) arqos, Bit#(4) arregion, Bit#(0) aruser);
      s.m_arvalid(arvalid, arid, araddr, arlen, arsize, arburst, arlock,
                  arcache, arprot, arqos, arregion, aruser);
      w_arvalid  <= arvalid;  w_arid    <= arid;    w_araddr <= araddr;
      w_arlen    <= arlen;    w_arsize  <= arsize;  w_arburst <= arburst;
      w_arlock   <= arlock;   w_arcache <= arcache; w_arprot <= arprot;
      w_arqos    <= arqos;    w_arregion <= arregion;
   endmethod
   method m_arready = s.m_arready;

   method m_rvalid = s.m_rvalid;
   method m_rid    = s.m_rid;
   method m_rdata  = s.m_rdata;
   method m_rresp  = s.m_rresp;
   method m_rlast  = s.m_rlast;
   method m_ruser  = s.m_ruser;
   method Action m_rready (Bool rready);
      s.m_rready(rready);
      w_rready <= rready;
   endmethod

endmodule

// ----------------------------------------------------------------------------
// Pass-through tap for a DUT AXI4 MASTER port. The environment (slave) side
// calls the returned interface; DUT-driven signals are read directly.
// ----------------------------------------------------------------------------
module mkAXI4_MasterMonitor #(String tag, AXI4_Master_IFC#(4,32,32,0) m)
                             (AXI4_Master_IFC#(4,32,32,0));

   AXI4_ProtocolChecker_IFC chk <- mkAXI4_ProtocolChecker(tag);

   // Slave-driven signals, captured by the forwarding Action methods
   Wire#(Bool)     w_awready <- mkDWire(False);
   Wire#(Bool)     w_wready  <- mkDWire(False);
   Wire#(Bool)     w_bvalid  <- mkDWire(False);
   Wire#(Bit#(4))  w_bid     <- mkDWire(0);
   Wire#(Bit#(2))  w_bresp   <- mkDWire(0);
   Wire#(Bool)     w_arready <- mkDWire(False);
   Wire#(Bool)     w_rvalid  <- mkDWire(False);
   Wire#(Bit#(4))  w_rid     <- mkDWire(0);
   Wire#(Bit#(32)) w_rdata   <- mkDWire(0);
   Wire#(Bit#(2))  w_rresp   <- mkDWire(0);
   Wire#(Bool)     w_rlast   <- mkDWire(False);

   (* fire_when_enabled, no_implicit_conditions *)
   rule rl_observe;
      chk.observe(AXI4_MonSigs {
         awvalid:  m.m_awvalid,  awready:  w_awready,
         awid:     m.m_awid,     awaddr:   m.m_awaddr,  awlen:  m.m_awlen,
         awsize:   m.m_awsize,   awburst:  m.m_awburst, awlock: m.m_awlock,
         awcache:  m.m_awcache,  awprot:   m.m_awprot,  awqos:  m.m_awqos,
         awregion: m.m_awregion,
         wvalid:   m.m_wvalid,   wready:   w_wready,
         wdata:    m.m_wdata,    wstrb:    m.m_wstrb,   wlast:  m.m_wlast,
         bvalid:   w_bvalid,     bready:   m.m_bready,
         bid:      w_bid,        bresp:    w_bresp,
         arvalid:  m.m_arvalid,  arready:  w_arready,
         arid:     m.m_arid,     araddr:   m.m_araddr,  arlen:  m.m_arlen,
         arsize:   m.m_arsize,   arburst:  m.m_arburst, arlock: m.m_arlock,
         arcache:  m.m_arcache,  arprot:   m.m_arprot,  arqos:  m.m_arqos,
         arregion: m.m_arregion,
         rvalid:   w_rvalid,     rready:   m.m_rready,
         rid:      w_rid,        rdata:    w_rdata,
         rresp:    w_rresp,      rlast:    w_rlast });
   endrule

   method m_awvalid  = m.m_awvalid;
   method m_awid     = m.m_awid;
   method m_awaddr   = m.m_awaddr;
   method m_awlen    = m.m_awlen;
   method m_awsize   = m.m_awsize;
   method m_awburst  = m.m_awburst;
   method m_awlock   = m.m_awlock;
   method m_awcache  = m.m_awcache;
   method m_awprot   = m.m_awprot;
   method m_awqos    = m.m_awqos;
   method m_awregion = m.m_awregion;
   method m_awuser   = m.m_awuser;
   method Action m_awready (Bool awready);
      m.m_awready(awready);
      w_awready <= awready;
   endmethod

   method m_wvalid = m.m_wvalid;
   method m_wdata  = m.m_wdata;
   method m_wstrb  = m.m_wstrb;
   method m_wlast  = m.m_wlast;
   method m_wuser  = m.m_wuser;
   method Action m_wready (Bool wready);
      m.m_wready(wready);
      w_wready <= wready;
   endmethod

   method Action m_bvalid (Bool bvalid, Bit#(4) bid, Bit#(2) bresp,
                           Bit#(0) buser);
      m.m_bvalid(bvalid, bid, bresp, buser);
      w_bvalid <= bvalid; w_bid <= bid; w_bresp <= bresp;
   endmethod
   method m_bready = m.m_bready;

   method m_arvalid  = m.m_arvalid;
   method m_arid     = m.m_arid;
   method m_araddr   = m.m_araddr;
   method m_arlen    = m.m_arlen;
   method m_arsize   = m.m_arsize;
   method m_arburst  = m.m_arburst;
   method m_arlock   = m.m_arlock;
   method m_arcache  = m.m_arcache;
   method m_arprot   = m.m_arprot;
   method m_arqos    = m.m_arqos;
   method m_arregion = m.m_arregion;
   method m_aruser   = m.m_aruser;
   method Action m_arready (Bool arready);
      m.m_arready(arready);
      w_arready <= arready;
   endmethod

   method Action m_rvalid (Bool rvalid, Bit#(4) rid, Bit#(32) rdata,
                           Bit#(2) rresp, Bool rlast, Bit#(0) ruser);
      m.m_rvalid(rvalid, rid, rdata, rresp, rlast, ruser);
      w_rvalid <= rvalid; w_rid <= rid; w_rdata <= rdata;
      w_rresp <= rresp;   w_rlast <= rlast;
   endmethod
   method m_rready = m.m_rready;

endmodule

endpackage
