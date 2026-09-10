#!/usr/bin/env bash
# Build, upload, then drop into the serial terminal — everything in one go.
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

./build.sh
./upload.sh
echo
echo "Bitfile loaded. Opening terminal (Ctrl-A Ctrl-X to exit)..."
sleep 1   # give the FPGA a moment to boot the design before we open the port
./connect.sh
