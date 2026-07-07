#!/usr/bin/env bash
# =============================================================================
# scripts/check_env.sh
# Probe for all OSS and CSS tools used in the flow.
# Exits 0 if all required OSS tools are present; exits 1 otherwise.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'

pass() { printf "  ${GRN}✔${NC}  %-30s %s\n" "$1" "$2"; }
warn() { printf "  ${YLW}⚠${NC}  %-30s %s\n" "$1" "$2"; }
fail() { printf "  ${RED}✘${NC}  %-30s %s\n" "$1" "$2"; }

check() {
  local name="$1" cmd="$2" req="$3"    # req=required|optional|css
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$(${cmd} --version 2>&1 | head -1 || true)
    pass "$name" "$ver"
    return 0
  else
    case "$req" in
      required) fail "$name" "NOT FOUND (required)" ;;
      css)      warn "$name" "not found (closed-source, optional)" ;;
      *)        warn "$name" "not found (optional)" ;;
    esac
    return 1
  fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HDL Unit Environment Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "── Open-Source Tools (primary) ──────────────────────────"

REQUIRED_MISSING=0

check "Python 3"         python3          required  || ((REQUIRED_MISSING++))
check "pip"              pip              required  || ((REQUIRED_MISSING++))
check "pre-commit"       pre-commit       required  || ((REQUIRED_MISSING++))
check "svlint"           svlint           required  || ((REQUIRED_MISSING++))
check "Verible lint"     verible-verilog-lint optional
check "Verilator"        verilator        required  || ((REQUIRED_MISSING++))
check "iverilog"         iverilog         optional
check "cocotb (pip)"     cocotb           optional
check "Yosys"            yosys            required  || ((REQUIRED_MISSING++))
check "SymbiYosys (sby)" sby              optional
check "OpenROAD"         openroad         optional
check "OpenSTA"          sta              optional
check "Magic"            magic            optional
check "KLayout"          klayout          optional
check "Netgen"           netgen           optional
check "PeakRDL"          peakrdl          optional
check "bsc (Bluespec)"   bsc              optional

echo ""
echo "── Closed-Source Tools (secondary, licence required) ────"
check "Synopsys VCS"     vcs              css
check "Cadence Xcelium"  xrun             css
check "Siemens Questa"   vsim             css
check "Synopsys DC"      dc_shell         css
check "Cadence Genus"    genus            css
check "Cadence Innovus"  innovus          css
check "Synopsys ICC2"    icc2_shell       css
check "Synopsys PT"      pt_shell         css
check "Synopsys SpyGlass" spyglass        css
check "Calibre"          calibre          css
check "JasperGold"       jg               css

echo ""
echo "── Python packages ──────────────────────────────────────"
python3 -c "import cocotb"       2>/dev/null && pass "cocotb"        "" || warn "cocotb"        "pip install cocotb"
python3 -c "import peakrdl"      2>/dev/null && pass "peakrdl"       "" || warn "peakrdl"       "pip install peakrdl"
python3 -c "import pytest"       2>/dev/null && pass "pytest"        "" || warn "pytest"        "pip install pytest"
python3 -c "import jinja2"       2>/dev/null && pass "jinja2"        "" || warn "jinja2"        "pip install jinja2"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if (( REQUIRED_MISSING > 0 )); then
  printf "${RED}  ✘  %d required tool(s) missing — fix before proceeding${NC}\n" "$REQUIRED_MISSING"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  exit 1
else
  printf "${GRN}  ✔  All required OSS tools present${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  exit 0
fi
