#!/usr/bin/env bash
# Flash audio_recorder.bit to the Anvyl board over JTAG (FT2232H).
# Uses openFPGALoader (apt: openfpgaloader). NB: ISE's settings64.sh injects
# old libstdc++ on LD_LIBRARY_PATH which breaks openFPGALoader; run with a
# clean env to avoid that.
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

BIT="${1:-audio_recorder.bit}"
[ -f "$BIT" ] || { echo "ERROR: $BIT not found. Run ./build.sh first." >&2; exit 1; }

if ! command -v openFPGALoader >/dev/null 2>&1; then
    echo "ERROR: openFPGALoader not installed. sudo apt install openfpgaloader" >&2
    exit 1
fi

# Run with a sanitized environment so ISE's bundled libs do not shadow system ones.
exec env -i PATH=/usr/bin:/bin HOME="$HOME" \
    openFPGALoader -c ft2232 "$BIT"
