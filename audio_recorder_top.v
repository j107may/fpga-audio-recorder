`timescale 1ns / 1ps
// CDA 4203 Final Project -- Audio Message Recorder
// Anvyl Board (Spartan-6 XC6SLX45-3-CSG484)
//
// Clock hierarchy:
//   OSC_100MHz -> ram_interface_wrapper.clk
//   ram_interface_wrapper.clkout (37.5 MHz) -> clk_wiz_37to100 -> pb_clk (100 MHz)
//   pb_clk -> clk_wiz_v3_6 -> main_clk (50 MHz) + audio_clk (11.2896 MHz)
//
// PicoBlaze I/O port map:
//   RD 0x00: UART RX data
//   RD 0x01: uart_data_present [bit 0]
//   RD 0x02: uart_buffer_full  [bit 0]
//   WR 0x03: UART TX data
//   WR 0x04: LED register (8-bit)
//   WR 0x05: FSM command (see CMD_* constants below)
//   RD 0x06: FSM status  (bit0=ram_rdy, 1=playing, 2=recording, 3=paused, 4=done)
//   RD 0x07: valid_slots [bits 3:0]
//   WR 0x08: slot select [bits 1:0]  (write before issuing PLAY/RECORD/DELETE cmd)
//   WR 0x09: volume      [bits 2:0]  (write before issuing SET_VOLUME cmd)
//   RD 0x0A: button states BTN[3:0]

module audio_recorder_top (
    input  OSC_100MHz,
    input  RESET_BTN,       // E6, active-high when pressed

    input  [3:0] BTN,       // pushbuttons V5,U4,V3,P4 (active-high)
    input  [3:0] SW,        // slide switches P8,P5,P6,R4

    output [7:0] LED,

    input  rs232_rx,
    output rs232_tx,

    // Audio CODEC (SSM2603)
    inout  AUD_ADCLRCK,
    input  AUD_ADCDAT,
    inout  AUD_DACLRCK,
    output AUD_DACDAT,
    output AUD_XCK,
    inout  AUD_BCLK,
    output AUD_I2C_SCLK,
    inout  AUD_I2C_SDAT,
    output AUD_MUTE,

    // DDR2 RAM
    output        hw_ram_rasn,
    output        hw_ram_casn,
    output        hw_ram_wen,
    output [2:0]  hw_ram_ba,
    inout         hw_ram_udqs_p,
    inout         hw_ram_udqs_n,
    inout         hw_ram_ldqs_p,
    inout         hw_ram_ldqs_n,
    output        hw_ram_udm,
    output        hw_ram_ldm,
    output        hw_ram_ck,
    output        hw_ram_ckn,
    output        hw_ram_cke,
    output        hw_ram_odt,
    output [12:0] hw_ram_ad,
    inout  [15:0] hw_ram_dq,
    inout         hw_rzq_pin,
    inout         hw_zio_pin
);

// ─────────────────────────────────────────────────────────────
// Reset
// ─────────────────────────────────────────────────────────────
wire reset = RESET_BTN;   // active-high

// ─────────────────────────────────────────────────────────────
// Clocks
// ─────────────────────────────────────────────────────────────
wire ram_clk;      // 37.5 MHz from RAM PLL output
wire pb_clk;       // 100 MHz for PicoBlaze + UART
wire main_clk;     // 50 MHz for I2C codec config
wire audio_clk;    // 11.2896 MHz for audio codec

clk_wiz_37to100 cwiz (
    .CLK_IN  (ram_clk),
    .CLK_OUT (pb_clk),
    .LOCKED  ()
);

clk_wiz_v3_6 audio_pll (
    .CLK_IN1 (pb_clk),
    .CLK_OUT1(main_clk),
    .CLK_OUT2(audio_clk),
    .RESET   (reset),
    .LOCKED  ()
);

// ─────────────────────────────────────────────────────────────
// DDR2 RAM
// Each slot is 4 MB = 2^22 bytes.
// slot_base(i) = i << 22  (26-bit address)
// ─────────────────────────────────────────────────────────────
localparam SLOT_BYTES = 26'h400000;   // 4 MB per slot

reg  [25:0] ram_addr;
reg  [7:0]  ram_din;
reg         ram_wen;
reg         ram_rreq;
reg         ram_rack;
wire [7:0]  ram_dout;
wire        ram_rdy;
wire        ram_data_pres;

ram_interface_wrapper #(.DATA_BYTE_WIDTH(1)) RAM (
    .address      (ram_addr),
    .data_in      (ram_din),
    .write_enable (ram_wen),
    .read_request (ram_rreq),
    .read_ack     (ram_rack),
    .data_out     (ram_dout),
    .reset        (reset),
    .clk          (OSC_100MHz),   // raw 100 MHz to RAM PLL input
    .sys_clk      (ram_clk),      // 37.5 MHz from clkout (feedback)
    .clkout       (ram_clk),
    .hw_ram_rasn  (hw_ram_rasn),
    .hw_ram_casn  (hw_ram_casn),
    .hw_ram_wen   (hw_ram_wen),
    .hw_ram_ba    (hw_ram_ba),
    .hw_ram_udqs_p(hw_ram_udqs_p),
    .hw_ram_udqs_n(hw_ram_udqs_n),
    .hw_ram_ldqs_p(hw_ram_ldqs_p),
    .hw_ram_ldqs_n(hw_ram_ldqs_n),
    .hw_ram_udm   (hw_ram_udm),
    .hw_ram_ldm   (hw_ram_ldm),
    .hw_ram_ck    (hw_ram_ck),
    .hw_ram_ckn   (hw_ram_ckn),
    .hw_ram_cke   (hw_ram_cke),
    .hw_ram_odt   (hw_ram_odt),
    .hw_ram_ad    (hw_ram_ad),
    .hw_ram_dq    (hw_ram_dq),
    .hw_rzq_pin   (hw_rzq_pin),
    .hw_zio_pin   (hw_zio_pin),
    .rdy          (ram_rdy),
    .rd_data_pres (ram_data_pres),
    .max_ram_address(),
    .ledRAM       ()
);

// ─────────────────────────────────────────────────────────────
// Audio CODEC
// ─────────────────────────────────────────────────────────────
wire [1:0]  sample_end;
wire [1:0]  sample_req;
wire [15:0] audio_input;
reg  [15:0] audio_output_r;    // driven by FSM (ram_clk domain)

assign AUD_XCK  = audio_clk;
assign AUD_MUTE = 1'b1;        // 1 = mute disabled

i2c_av_config codec_cfg (
    .clk     (main_clk),
    .reset   (reset),
    .i2c_sclk(AUD_I2C_SCLK),
    .i2c_sdat(AUD_I2C_SDAT),
    .status  ()
);

audio_codec codec (
    .clk         (audio_clk),
    .reset       (reset),
    .sample_end  (sample_end),
    .sample_req  (sample_req),
    .audio_output(audio_output_r),
    .audio_input (audio_input),
    .channel_sel (2'b10),
    .AUD_ADCLRCK (AUD_ADCLRCK),
    .AUD_ADCDAT  (AUD_ADCDAT),
    .AUD_DACLRCK (AUD_DACLRCK),
    .AUD_DACDAT  (AUD_DACDAT),
    .AUD_BCLK    (AUD_BCLK)
);

// ─────────────────────────────────────────────────────────────
// Clock-domain crossing: audio <-> ram_clk (37.5 MHz)
// Toggle synchronisers ensure single-cycle pulses are captured.
// ─────────────────────────────────────────────────────────────

// --- Microphone capture (audio_clk -> ram_clk) ---
reg [15:0] rec_sample;          // stable ~22 µs after each sample_end
reg        rec_toggle_aud;      // toggles on each new sample

always @(posedge audio_clk) begin
    if (sample_end[1]) begin
        rec_sample     <= audio_input;
        rec_toggle_aud <= ~rec_toggle_aud;
    end
end

reg [2:0] rec_sync;
always @(posedge ram_clk) rec_sync <= {rec_sync[1:0], rec_toggle_aud};
wire new_rec_sample = rec_sync[1] ^ rec_sync[2];

// --- DAC request (audio_clk -> ram_clk) ---
reg req_toggle_aud;
always @(posedge audio_clk) begin
    if (sample_req[1]) req_toggle_aud <= ~req_toggle_aud;
end

reg [2:0] req_sync;
always @(posedge ram_clk) req_sync <= {req_sync[1:0], req_toggle_aud};
wire sample_req_pulse = req_sync[1] ^ req_sync[2];

// ─────────────────────────────────────────────────────────────
// PicoBlaze port registers (pb_clk, 100 MHz)
// ─────────────────────────────────────────────────────────────
wire [7:0]  pb_port_id;
wire [7:0]  pb_out_port;
reg  [7:0]  pb_in_port;
wire        pb_read_strobe;
wire        pb_write_strobe;

// Command path to FSM (CDC: pb_clk -> ram_clk)
reg [7:0]   pb_cmd;
reg [1:0]   pb_slot;
reg [2:0]   pb_volume;
reg         cmd_toggle_pb;

always @(posedge pb_clk or posedge reset) begin
    if (reset) begin
        pb_cmd <= 8'h00; pb_slot <= 2'd0;
        pb_volume <= 3'd5; cmd_toggle_pb <= 1'b0;
    end else if (pb_write_strobe) begin
        case (pb_port_id)
            8'h05: begin pb_cmd <= pb_out_port;
                         if (pb_out_port != 8'h00)
                             cmd_toggle_pb <= ~cmd_toggle_pb; end
            8'h08: pb_slot   <= pb_out_port[1:0];
            8'h09: pb_volume <= pb_out_port[2:0];
            default: ;
        endcase
    end
end

// Sync command data to ram_clk (3 stages for toggle, 2 for data)
reg [2:0] cmd_tog_sync;
reg [7:0] cmd_d1, cmd_d2;
reg [1:0] slot_d1, slot_d2;
reg [2:0] vol_d1, vol_d2;

always @(posedge ram_clk) begin
    cmd_tog_sync <= {cmd_tog_sync[1:0], cmd_toggle_pb};
    cmd_d1  <= pb_cmd;    cmd_d2  <= cmd_d1;
    slot_d1 <= pb_slot;   slot_d2 <= slot_d1;
    vol_d1  <= pb_volume; vol_d2  <= vol_d1;
end
wire new_cmd   = cmd_tog_sync[1] ^ cmd_tog_sync[2];
wire [7:0] cmd = cmd_d2;
wire [1:0] sel = slot_d2;
wire [2:0] vol = vol_d2;

// ─────────────────────────────────────────────────────────────
// Message metadata (volatile FPGA registers)
// ─────────────────────────────────────────────────────────────
reg [3:0]  msg_valid;
reg [25:0] msg_len [0:3];

// ─────────────────────────────────────────────────────────────
// Main FSM (ram_clk, 37.5 MHz)
// ─────────────────────────────────────────────────────────────
localparam ST_INIT       = 4'd0;
localparam ST_IDLE       = 4'd1;
localparam ST_REC_WAIT   = 4'd2;
localparam ST_REC_WR_HI  = 4'd3;
localparam ST_REC_WR_LO  = 4'd4;
localparam ST_PLAY_RD_HI = 4'd5;
localparam ST_PLAY_WD_HI = 4'd6;
localparam ST_PLAY_RD_LO = 4'd7;
localparam ST_PLAY_WD_LO = 4'd8;
localparam ST_PLAY_WAIT  = 4'd9;
localparam ST_PAUSED     = 4'd10;

// Command constants
localparam CMD_PLAY   = 8'h01;
localparam CMD_RECORD = 8'h02;
localparam CMD_STOP   = 8'h03;
localparam CMD_PAUSE  = 8'h04;
localparam CMD_RESUME = 8'h05;
localparam CMD_DEL    = 8'h06;
localparam CMD_DELALL = 8'h07;
localparam CMD_SETVOL = 8'h08;

reg [3:0]  state;
reg [25:0] cur_addr;
reg [25:0] play_end;
reg [1:0]  active_slot;
reg [2:0]  volume;
reg [7:0]  hi_byte;
reg [15:0] play_sample;
reg        fsm_playing, fsm_recording, fsm_paused, fsm_done;

// Helper: slot base address (each slot = 2^22 bytes)
function [25:0] slot_base;
    input [1:0] s;
    slot_base = {2'b00, s, 22'b0};
endfunction

always @(posedge ram_clk or posedge reset) begin
    if (reset) begin
        state        <= ST_INIT;
        cur_addr     <= 26'h0;
        play_end     <= 26'h0;
        active_slot  <= 2'd0;
        volume       <= 3'd5;
        hi_byte      <= 8'h0;
        play_sample  <= 16'h0;
        fsm_playing  <= 1'b0;
        fsm_recording<= 1'b0;
        fsm_paused   <= 1'b0;
        fsm_done     <= 1'b0;
        msg_valid    <= 4'b0;
        msg_len[0]   <= 26'h0;
        msg_len[1]   <= 26'h0;
        msg_len[2]   <= 26'h0;
        msg_len[3]   <= 26'h0;
        audio_output_r <= 16'h0;
        ram_wen      <= 1'b0;
        ram_rreq     <= 1'b0;
        ram_rack     <= 1'b0;
        ram_addr     <= 26'h0;
        ram_din      <= 8'h0;
    end else begin
        // Default de-assert
        ram_wen  <= 1'b0;
        ram_rreq <= 1'b0;
        ram_rack <= 1'b0;
        fsm_done <= 1'b0;

        case (state)

        ST_INIT: begin
            if (ram_rdy) state <= ST_IDLE;
        end

        //----------------------------------------------
        ST_IDLE: begin
            fsm_recording <= 1'b0;
            fsm_playing   <= 1'b0;
            fsm_paused    <= 1'b0;
            audio_output_r <= 16'h0;

            if (new_cmd) begin
                case (cmd)
                CMD_PLAY: begin
                    if (msg_valid[sel] && msg_len[sel] > 26'h0) begin
                        active_slot <= sel;
                        cur_addr    <= slot_base(sel);
                        play_end    <= slot_base(sel) + msg_len[sel];
                        fsm_playing <= 1'b1;
                        state       <= ST_PLAY_RD_HI;
                    end
                end
                CMD_RECORD: begin
                    active_slot  <= sel;
                    cur_addr     <= slot_base(sel);
                    msg_valid[sel] <= 1'b0;
                    msg_len[sel]   <= 26'h0;
                    fsm_recording  <= 1'b1;
                    state          <= ST_REC_WAIT;
                end
                CMD_DEL: begin
                    msg_valid[sel] <= 1'b0;
                    msg_len[sel]   <= 26'h0;
                end
                CMD_DELALL: begin
                    msg_valid  <= 4'b0;
                    msg_len[0] <= 26'h0; msg_len[1] <= 26'h0;
                    msg_len[2] <= 26'h0; msg_len[3] <= 26'h0;
                end
                CMD_SETVOL: volume <= vol;
                default: ;
                endcase
            end
        end

        //----------------------------------------------
        ST_REC_WAIT: begin
            if (new_cmd && cmd == CMD_STOP) begin
                msg_valid[active_slot] <= (msg_len[active_slot] > 26'h0) ? 1'b1 : 1'b0;
                fsm_recording <= 1'b0;
                fsm_done      <= 1'b1;
                state <= ST_IDLE;
            end else if (msg_len[active_slot] >= SLOT_BYTES - 2) begin
                // Slot full
                msg_valid[active_slot] <= 1'b1;
                fsm_recording <= 1'b0;
                fsm_done      <= 1'b1;
                state <= ST_IDLE;
            end else if (new_rec_sample) begin
                state <= ST_REC_WR_HI;
            end
        end

        ST_REC_WR_HI: begin
            ram_addr <= cur_addr;
            ram_din  <= rec_sample[15:8];
            ram_wen  <= 1'b1;
            state    <= ST_REC_WR_LO;
        end

        ST_REC_WR_LO: begin
            ram_addr <= cur_addr + 26'h1;
            ram_din  <= rec_sample[7:0];
            ram_wen  <= 1'b1;
            cur_addr <= cur_addr + 26'h2;
            msg_len[active_slot] <= msg_len[active_slot] + 26'h2;
            state <= ST_REC_WAIT;
        end

        //----------------------------------------------
        ST_PLAY_RD_HI: begin
            if (cur_addr >= play_end) begin
                audio_output_r <= 16'h0;
                fsm_playing    <= 1'b0;
                fsm_done       <= 1'b1;
                state <= ST_IDLE;
            end else begin
                ram_addr <= cur_addr;
                ram_rreq <= 1'b1;
                state    <= ST_PLAY_WD_HI;
            end
        end

        ST_PLAY_WD_HI: begin
            if (ram_data_pres) begin
                hi_byte  <= ram_dout;
                ram_rack <= 1'b1;
                state    <= ST_PLAY_RD_LO;
            end
        end

        ST_PLAY_RD_LO: begin
            ram_addr <= cur_addr + 26'h1;
            ram_rreq <= 1'b1;
            state    <= ST_PLAY_WD_LO;
        end

        ST_PLAY_WD_LO: begin
            if (ram_data_pres) begin
                play_sample <= {hi_byte, ram_dout};
                ram_rack    <= 1'b1;
                cur_addr    <= cur_addr + 26'h2;
                state       <= ST_PLAY_WAIT;
            end
        end

        ST_PLAY_WAIT: begin
            // Output pre-fetched sample with volume scaling
            case (volume)
                3'd0: audio_output_r <= {{7{play_sample[15]}}, play_sample[15:7]};
                3'd1: audio_output_r <= {{6{play_sample[15]}}, play_sample[15:6]};
                3'd2: audio_output_r <= {{5{play_sample[15]}}, play_sample[15:5]};
                3'd3: audio_output_r <= {{4{play_sample[15]}}, play_sample[15:4]};
                3'd4: audio_output_r <= {{3{play_sample[15]}}, play_sample[15:3]};
                3'd5: audio_output_r <= {{2{play_sample[15]}}, play_sample[15:2]};
                3'd6: audio_output_r <= {play_sample[15], play_sample[15:1]};
                3'd7: audio_output_r <= play_sample;
            endcase

            if (new_cmd) begin
                if (cmd == CMD_STOP) begin
                    audio_output_r <= 16'h0;
                    fsm_playing <= 1'b0;
                    state <= ST_IDLE;
                end else if (cmd == CMD_PAUSE) begin
                    audio_output_r <= 16'h0;
                    fsm_paused  <= 1'b1;
                    fsm_playing <= 1'b0;
                    state       <= ST_PAUSED;
                end else if (cmd == CMD_SETVOL) begin
                    volume <= vol;
                end
            end else if (sample_req_pulse) begin
                state <= ST_PLAY_RD_HI;
            end
        end

        ST_PAUSED: begin
            audio_output_r <= 16'h0;
            if (new_cmd) begin
                if (cmd == CMD_RESUME) begin
                    fsm_playing <= 1'b1;
                    fsm_paused  <= 1'b0;
                    state       <= ST_PLAY_RD_HI;
                end else if (cmd == CMD_STOP) begin
                    fsm_paused <= 1'b0;
                    state      <= ST_IDLE;
                end
            end
        end

        default: state <= ST_IDLE;
        endcase
    end
end

// ─────────────────────────────────────────────────────────────
// Status to PicoBlaze (ram_clk -> pb_clk sync)
// ─────────────────────────────────────────────────────────────
wire [7:0] fsm_status_raw  = {3'b0, fsm_done, fsm_paused, fsm_recording, fsm_playing, ram_rdy};
wire [3:0] valid_slots_raw = msg_valid;

reg [7:0] stat_s1, stat_s2;
reg [3:0] vld_s1, vld_s2;
always @(posedge pb_clk) begin
    stat_s1 <= fsm_status_raw; stat_s2 <= stat_s1;
    vld_s1  <= valid_slots_raw; vld_s2  <= vld_s1;
end

reg [3:0] btn_s1, btn_s2;
always @(posedge pb_clk) begin
    btn_s1 <= BTN; btn_s2 <= btn_s1;
end

// ─────────────────────────────────────────────────────────────
// PicoBlaze + UART (pb_clk, 100 MHz)
// ─────────────────────────────────────────────────────────────
wire       uart_data_present, uart_buffer_full;
wire [7:0] uart_rx_data;
wire       uart_write_en;
reg        uart_read_ack;
reg  [7:0] led_r;

rs232_uart UART (
    .tx_data_in      (pb_out_port),
    .write_tx_data   (uart_write_en),
    .tx_buffer_full  (uart_buffer_full),
    .rx_data_out     (uart_rx_data),
    .read_rx_data_ack(uart_read_ack),
    .rx_data_present (uart_data_present),
    .rs232_tx        (rs232_tx),
    .rs232_rx        (rs232_rx),
    .reset           (reset),
    .clk             (pb_clk)
);

wire [11:0] pb_addr;
wire [17:0] pb_instr;
wire        pb_bram_en;

kcpsm6 CPU (
    .address       (pb_addr),
    .instruction   (pb_instr),
    .bram_enable   (pb_bram_en),
    .port_id       (pb_port_id),
    .write_strobe  (pb_write_strobe),
    .k_write_strobe(),
    .out_port      (pb_out_port),
    .read_strobe   (pb_read_strobe),
    .in_port       (pb_in_port),
    .interrupt     (1'b0),
    .interrupt_ack (),
    .reset         (reset),
    .sleep         (1'b0),
    .clk           (pb_clk)
);

program ROM (
    .enable     (pb_bram_en),
    .address    (pb_addr),
    .instruction(pb_instr),
    .clk        (pb_clk)
);

// Output port decoding
assign uart_write_en = pb_write_strobe & (pb_port_id == 8'h03);

always @(posedge pb_clk or posedge reset) begin
    if (reset) begin
        led_r         <= 8'h00;
        uart_read_ack <= 1'b0;
    end else begin
        uart_read_ack <= pb_read_strobe & (pb_port_id == 8'h00);
        if (pb_write_strobe && pb_port_id == 8'h04)
            led_r <= pb_out_port;
    end
end

// Input port mux
always @(*) begin
    case (pb_port_id)
        8'h00:  pb_in_port = uart_rx_data;
        8'h01:  pb_in_port = {7'b0, uart_data_present};
        8'h02:  pb_in_port = {7'b0, uart_buffer_full};
        8'h06:  pb_in_port = stat_s2;
        8'h07:  pb_in_port = {4'h0, vld_s2};
        8'h0A:  pb_in_port = {4'h0, ~btn_s2};   // BTNs active-low on Anvyl
        default:pb_in_port = 8'h00;
    endcase
end

assign LED = led_r;

endmodule
