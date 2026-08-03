`timescale 1ns / 1ps

module RISC_V_SOC_TOP #(
    parameter N = 2,
    parameter ARCH_TYPE = "DIP",
    parameter DATA_MEM_WORDS = 8192
)(
    input  sys_clk,     // Single-ended 200 MHz clock from board
    input  reset
);

    wire clk;           // Internal global 100 MHz system clock
    wire sys_reset;     // Internal system reset
    wire unrecognized;
    wire [31:0] wb_data;
    wire [31:0] pc, instruction;

`ifdef __ICARUS__
    // =========================================================================
    // SIMULATION PATH
    // =========================================================================
    assign clk = sys_clk;
    assign sys_reset = reset;

`else
    // =========================================================================
    // SYNTHESIS / HARDWARE PATH (Vivado)
    // =========================================================================
    wire clk_mmcm_out;
    wire clk_fb;
    wire mmcm_locked;

    // MMCM configured to take 100 MHz in, output 50 MHz out
         MMCME2_BASE #(
        .CLKIN1_PERIOD     (5.000),   // 200 MHz input period
        .DIVCLK_DIVIDE     (1),
        .CLKFBOUT_MULT_F   (5.000),   // VCO = 200 * 5 = 1000 MHz 
        .CLKOUT0_DIVIDE_F  (20.000),  // Out = 1000 / 20 = 50 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .STARTUP_WAIT      ("FALSE")
    ) sysclk_mmcm (
        .CLKIN1  (sys_clk),
        .CLKFBIN (clk_fb),
        .CLKFBOUT(clk_fb),
        .CLKOUT0 (clk_mmcm_out),
        .PWRDWN  (1'b0),
        .RST     (reset),
        .LOCKED  (mmcm_locked)
    );
 
    BUFG clk_bufg (
        .I(clk_mmcm_out),
        .O(clk)
    );

     ila_0 ila(
        .clk(clk),
        .probe0(wb_data),
        .probe1(pc)
    );
 
    // Hold system in reset until the MMCM clock is stable
    assign sys_reset = reset | ~mmcm_locked;
`endif


    RISC_V_PROCESSOR #(.N(N), .ARCH_TYPE(ARCH_TYPE), .DATA_MEM_WORDS(DATA_MEM_WORDS)) processor(
        .clk(clk),
        .reset(sys_reset),
        .unrecognized(unrecognized),
        .wb_data(wb_data),
        .pc_out(pc),
        .instruction_in(instruction)
    );

    INSTRUCTION_MEMORY instruction_memory(
        .clk(clk),
        .reset(sys_reset),
        .pc(pc),
        .instruction(instruction)
    );
    

endmodule