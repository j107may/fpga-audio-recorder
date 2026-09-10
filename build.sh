#!/usr/bin/env bash
# Build the audio recorder bitfile from source.
# Anvyl Board (Spartan-6 XC6SLX45-3-CSG484) using Xilinx ISE 14.7.
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

ISE_ROOT="${ISE_ROOT:-/home/theguy920/Xilinx/14.7/ISE_DS}"
PART="xc6slx45-3-csg484"
TOP="audio_recorder_top"
BIT="audio_recorder.bit"

# 1) Source the ISE environment (xst, ngdbuild, map, par, bitgen on PATH).
if [ -f "$ISE_ROOT/settings64.sh" ]; then
    source "$ISE_ROOT/settings64.sh" >/dev/null
elif [ -f "$ISE_ROOT/settings32.sh" ]; then
    source "$ISE_ROOT/settings32.sh" >/dev/null
else
    echo "ERROR: ISE settings not found at $ISE_ROOT" >&2
    exit 1
fi

step() { echo; echo "=== $* ==="; }

# 2) Assemble PicoBlaze firmware if PSM is newer than program.v.
if [ ! -f program.v ] || [ recorder_ui.psm -nt program.v ]; then
    step "Assemble PicoBlaze (recorder_ui.psm -> program.v)"
    rm -f recorder_ui.v program.v
    WINEDEBUG=-all wine assembler.exe recorder_ui.psm 2>&1 | tail -1
    [ -f recorder_ui.v ] || { echo "ERROR: assembler did not produce recorder_ui.v"; exit 1; }
    # KCPSM6 names the output module after the .psm filename and emits CRLF;
    # rename to "program" so kcpsm6 instantiation in the top module matches.
    tr -d '\r' < recorder_ui.v | sed 's/^module recorder_ui/module program/' > program.v
fi

# 3) Synthesize.
step "XST synthesis"
mkdir -p xst/projnav.tmp _ngo
xst -ifn audio_recorder.xst -ofn audio_recorder.syr 2>&1 | tail -3

# 4) NGDBuild — turn .ngc + .ucf into a placed netlist (.ngd).
step "NGDBuild"
ngdbuild -dd _ngo -nt timestamp -uc audio_recorder.ucf -p "$PART" \
    audio_recorder.ngc audio_recorder.ngd 2>&1 | tail -3

# 5) MAP — pack logic into Spartan-6 slices.
step "MAP"
map -p "$PART" -w -logic_opt off -o audio_recorder_map.ncd \
    audio_recorder.ngd audio_recorder.pcf 2>&1 | tail -3

# 6) PAR — place and route.
step "PAR (place & route)"
par -w -ol high audio_recorder_map.ncd audio_recorder.ncd audio_recorder.pcf 2>&1 | tail -3

# 7) BitGen — write the bitstream.
step "BitGen"
bitgen -w audio_recorder.ncd "$BIT" audio_recorder.pcf 2>&1 | tail -3

echo
echo "Built $BIT ($(stat -c%s "$BIT") bytes)."
echo "Now run ./upload.sh to flash, then ./connect.sh for the terminal."
