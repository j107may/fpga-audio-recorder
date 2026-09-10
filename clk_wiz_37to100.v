// Clock Wizard: 37.5 MHz input -> 100 MHz output
// Spartan-6 PLL_BASE
// DIVCLK_DIVIDE=1 (Fpfd=37.5MHz, must be >=19MHz for Spartan-6)
// VCO = 37.5 * 16 / 1 = 600 MHz (in valid 400-1080 range)
// Output = VCO / 6 = 100 MHz
`timescale 1ns / 1ps
module clk_wiz_37to100 (
    input  CLK_IN,    // 37.5 MHz from RAM clkout
    output CLK_OUT,   // 100 MHz
    output LOCKED
);
    wire CLKFB;
    wire CLKOUT0_raw;

    PLL_BASE #(
        .BANDWIDTH         ("OPTIMIZED"),
        .CLK_FEEDBACK      ("CLKFBOUT"),
        .COMPENSATION      ("INTERNAL"),
        .DIVCLK_DIVIDE     (1),
        .CLKFBOUT_MULT     (16),
        .CLKFBOUT_PHASE    (0.000),
        .CLKOUT0_DIVIDE    (6),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE     (0.000),
        .CLKIN_PERIOD      (26.667),
        .REF_JITTER        (0.010),
        .RESET_ON_LOSS_OF_LOCK("FALSE")
    ) pll_inst (
        .CLKFBIN  (CLKFB),
        .CLKIN    (CLK_IN),
        .RST      (1'b0),
        .CLKFBOUT (CLKFB),
        .CLKOUT0  (CLKOUT0_raw),
        .LOCKED   (LOCKED),
        .CLKOUT1  (),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  ()
    );

    BUFG clkout_buf (
        .I (CLKOUT0_raw),
        .O (CLK_OUT)
    );

endmodule
