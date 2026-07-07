#!/usr/bin/env python3
"""Structural CDC analysis over a Yosys JSON netlist (stage 2 of `make cdc`).

Reads the flattened JSON netlist dumped by cdc/cdc_check.tcl, groups every
flip-flop by the net driving its clock pin, then walks the combinational
fan-in of each flop's D pin. A path whose source flop belongs to a different
clock domain is reported as a potential CDC crossing.

Limitations (by design — this is a structural early check, not signoff):
  - It cannot verify synchronizer correctness (2-FF depth, gray coding, ...).
  - It does not analyze reset domain crossings.
  - For production CDC signoff use a commercial tool (SpyGlass CDC, Meridian).

Exit status: 0 if no crossings found (or single-clock design), 1 otherwise.
"""
import argparse
import json
import sys
from collections import defaultdict

# Yosys generic FF cell types and their clock/data pin names
FF_TYPES = {
    "$dff": ("CLK", "D"),
    "$dffe": ("CLK", "D"),
    "$sdff": ("CLK", "D"),
    "$sdffe": ("CLK", "D"),
    "$sdffce": ("CLK", "D"),
    "$adff": ("CLK", "D"),
    "$adffe": ("CLK", "D"),
    "$aldff": ("CLK", "D"),
    "$aldffe": ("CLK", "D"),
    "$dffsr": ("CLK", "D"),
    "$dffsre": ("CLK", "D"),
}


def bits(conn):
    """Normalize a connection bit list (ints and '0'/'1'/'x' strings)."""
    return [b for b in conn if isinstance(b, int)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", required=True, help="Yosys JSON netlist")
    ap.add_argument("--out", required=True, help="report file to write")
    args = ap.parse_args()

    with open(args.json) as f:
        design = json.load(f)

    # After `flatten` there is a single top module left with cells.
    top_name, top = max(
        design["modules"].items(), key=lambda kv: len(kv[1].get("cells", {}))
    )
    cells = top.get("cells", {})
    netnames = top.get("netnames", {})

    # bit -> human-readable net name (first name that carries the bit)
    bit_names = {}
    for name, nn in netnames.items():
        for b in bits(nn["bits"]):
            bit_names.setdefault(b, name)

    def name_of(bit):
        return bit_names.get(bit, f"<bit {bit}>")

    # Index: which cell drives each bit (via its output ports)
    driver_of = {}
    for cname, cell in cells.items():
        dirs = cell.get("port_directions", {})
        for port, conn in cell.get("connections", {}).items():
            if dirs.get(port) == "output":
                for b in bits(conn):
                    driver_of[b] = (cname, cell)

    # Collect flops: cell -> (clock bit, D bits, Q bits)
    flops = {}
    for cname, cell in cells.items():
        if cell["type"] in FF_TYPES:
            clk_pin, d_pin = FF_TYPES[cell["type"]]
            conns = cell["connections"]
            clk_bits = bits(conns.get(clk_pin, []))
            if not clk_bits:
                continue
            flops[cname] = {
                "clk": clk_bits[0],
                "d": bits(conns.get(d_pin, [])),
                "q": bits(conns.get("Q", [])),
            }

    # Group flops by clock net
    domains = defaultdict(list)
    for cname, ff in flops.items():
        domains[ff["clk"]].append(cname)

    # Map: Q bit -> owning flop (for source lookup during fan-in walk)
    q_owner = {}
    for cname, ff in flops.items():
        for b in ff["q"]:
            q_owner[b] = cname

    def trace_sources(start_bits):
        """Walk combinational fan-in from bits; return set of source flops."""
        sources, seen, stack = set(), set(), list(start_bits)
        while stack:
            b = stack.pop()
            if b in seen:
                continue
            seen.add(b)
            if b in q_owner:
                sources.add(q_owner[b])
                continue  # stop at a flop boundary
            drv = driver_of.get(b)
            if drv is None:
                continue  # primary input or constant
            _, cell = drv
            dirs = cell.get("port_directions", {})
            for port, conn in cell.get("connections", {}).items():
                if dirs.get(port) == "input":
                    stack.extend(bits(conn))
        return sources

    # Find crossings
    crossings = []
    if len(domains) > 1:
        for cname, ff in flops.items():
            for src in trace_sources(ff["d"]):
                if flops[src]["clk"] != ff["clk"]:
                    crossings.append((src, cname))

    # ── Report ──────────────────────────────────────────────────────────────
    lines = []
    lines.append("=" * 66)
    lines.append(f"CDC Analysis Report — {top_name}")
    lines.append("=" * 66)
    lines.append("")
    lines.append(f"Flip-flops found : {len(flops)}")
    lines.append(f"Clock domains    : {len(domains)}")
    for clk_bit, members in sorted(domains.items(), key=lambda kv: -len(kv[1])):
        lines.append(f"  clock '{name_of(clk_bit)}' — {len(members)} flop(s)")
    lines.append("")

    if len(domains) <= 1:
        lines.append("Single clock domain — no CDC paths possible.")
        rc = 0
    elif not crossings:
        lines.append("Multiple clock domains, no flop-to-flop crossings found.")
        rc = 0
    else:
        lines.append(f"POTENTIAL CDC CROSSINGS: {len(crossings)}")
        lines.append("(source flop -> destination flop; verify each has a")
        lines.append(" proper synchronizer — this tool cannot check that)")
        for src, dst in sorted(set(crossings)):
            lines.append(
                f"  {src} [{name_of(flops[src]['clk'])}] -> "
                f"{dst} [{name_of(flops[dst]['clk'])}]"
            )
        rc = 1

    lines.append("")
    lines.append("NOTE: structural best-effort check only. For signoff use a")
    lines.append("commercial CDC tool (SpyGlass CDC, Meridian CDC).")
    lines.append("=" * 66)

    report = "\n".join(lines) + "\n"
    with open(args.out, "w") as f:
        f.write(report)
    print(report)
    sys.exit(rc)


if __name__ == "__main__":
    main()
