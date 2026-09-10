# FPGA Audio Message Recorder

Verilog/VHDL design for a standalone audio message recorder/player built on a
Digilent Anvyl board (Xilinx Spartan-6 XC6SLX45). Records audio from an
onboard codec into RAM slots and plays them back, controlled via pushbuttons
and a UART command interface, with status shown on LEDs.

Group project for CDA 4203 (4 members). We were given some starter files and
had to design, integrate, and get the full audio pipeline working ourselves.
Some low-level modules (`kcpsm6.v` PicoBlaze soft core, `uart_rx6.v` /
`uart_tx6.v` / `rs232_uart.v`) are Xilinx reference/vendor IP used as
building blocks, not authored by the team. The system integration, I2C audio
codec configuration, RAM interface, top-level FSM/control logic, and the
PicoBlaze assembly firmware were built by the group.

## Architecture

- **Top level** (`audio_recorder_top.v`) — clocking hierarchy, I/O mapping,
  and instantiation of all subsystems.
- **Audio codec interface** (`audio_codec.v`, `i2c_av_config.v`,
  `i2c_av_config_loud.v`, `i2c_controller.v`) — configures and streams
  to/from the onboard SSM2603 audio codec over I2C.
- **RAM interface** (`ram_interface_wrapper.v`) — manages audio sample
  storage/retrieval for record/playback slots.
- **Control firmware** (`program.v`, `recorder_ui.psm`, `ROM_form.v`,
  `kcpsm6.v`) — PicoBlaze-based control FSM handling buttons, switches,
  UART commands, and recorder state (idle/recording/playing/paused).
- **UART** (`rs232_uart.v`, `uart_rx6.v`, `uart_tx6.v`) — serial command
  interface.
- **Clocking** (`clk_wiz_v3_6.vhd`, `clk_wiz_37to100.v`) — clock generation
  for the PicoBlaze core and audio sample clock.

PicoBlaze I/O port map and clock hierarchy are documented in the header
comment of `audio_recorder_top.v`.

## Build

Originally built with Xilinx ISE for the Anvyl (Spartan-6) board. Shell
scripts document the toolchain flow:

- `build.sh` — synthesize/implement/generate bitstream
- `upload.sh` — program the board
- `connect.sh` — open a UART session to the board
- `clean.sh` — clean build outputs

Generated build artifacts (netlists, place-and-route reports, bitstreams,
IP-core generated output) are intentionally not included in this repo — only
the authored source.

## Files

- `Final_Project_Report.docx` — full project write-up submitted for the course
