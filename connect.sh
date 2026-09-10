#!/usr/bin/env bash
# Open a serial terminal to the Anvyl UART.
# Anvyl exposes two FT2232H interfaces; data UART is /dev/ttyUSB1.
# Override with: PORT=/dev/ttyUSB0 ./connect.sh
#
# picocom shortcuts:
#   Ctrl-A Ctrl-X   exit
#   Ctrl-A Ctrl-C   toggle local echo
#   Ctrl-A Ctrl-U   toggle CR/LF translation
set -e

PORT="${PORT:-/dev/ttyUSB1}"
BAUD="${BAUD:-9600}"

[ -e "$PORT" ] || { echo "ERROR: $PORT not present. Plug in the Anvyl?" >&2; exit 1; }

if ! command -v picocom >/dev/null 2>&1; then
    echo "picocom not installed; falling back to screen." >&2
    exec screen "$PORT" "$BAUD"
fi

# --omap crlf : when *we* press Enter, send CR (firmware expects 0x0D).
# --imap lfcrlf : when firmware sends a bare LF, render as CRLF for the terminal.
# --echo : local echo on (so what you type is visible).
exec picocom --baud "$BAUD" --omap crlf --imap lfcrlf --echo "$PORT"
