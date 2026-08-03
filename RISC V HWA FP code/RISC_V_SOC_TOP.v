`timescale 1ns / 1ps

module RISC_V_SOC_TOP #(
    parameter N = 2,
    parameter ARCH_TYPE = "DIP"
)(
    input  wire clk,   // Single-ended clock input for Z-board
    input  wire reset  // Single-ended reset
);

    // =========================================================================
    // CLOCK GENERATION: 100 MHz (Board) -> 50 MHz (CPU)
    // =========================================================================
    wire cpu_clk;
    wire sys_reset;

`ifdef __ICARUS__
   // -------------------------------------------------------------------------
    // ICARUS VERILOG / SIMULATION: Direct Clock
    // -------------------------------------------------------------------------
    assign cpu_clk = clk;     // <-- Direct pass-through, just like the working version
    assign sys_reset = reset; // No MMCM lock signal in simulation

`else
    // -------------------------------------------------------------------------
    // SYNTHESIS (VIVADO): Xilinx Hardware Primitives
    // -------------------------------------------------------------------------
    wire clk_fb, clk_fb_buf, clk_50mhz_unbuf, mmcm_locked;
    assign sys_reset = reset | ~mmcm_locked;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.000),
        .CLKFBOUT_MULT_F(10.000),
        .CLKOUT0_DIVIDE_F(20.000),
        .DIVCLK_DIVIDE(1)
    ) clk_divider (
        .CLKIN1(clk),
        .CLKFBIN(clk_fb_buf),
        .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_50mhz_unbuf),
        .LOCKED(mmcm_locked),
        .RST(reset),
        .PWRDWN(1'b0)
    );

    BUFG clkfb_bufg (.I(clk_fb), .O(clk_fb_buf));
    BUFG clk_bufg   (.I(clk_50mhz_unbuf), .O(cpu_clk));
`endif

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    wire [31:0] pc, instruction;
    wire [31:0] wb_data;
    wire unrecognized;

    // =========================================================================
    // CORE INSTANTIATIONS
    // =========================================================================
    
    // --> FIX: Parameters are now successfully passed down to the processor <--
    RISC_V_PROCESSOR #(
        .N(N),
        .ARCH_TYPE(ARCH_TYPE)
    ) processor (
        .clk(cpu_clk),         
        .reset(sys_reset),
        .unrecognized(unrecognized),
        .wb_data(wb_data),
        .pc_out(pc),
        .instruction_in(instruction)
    );

    INSTRUCTION_MEMORY instruction_memory (
        .clk(cpu_clk),         
        .reset(sys_reset),
        .pc(pc),
        .instruction(instruction)
    );
    
`ifndef __ICARUS__
    // -------------------------------------------------------------------------
    // SYNTHESIS ONLY: Integrated Logic Analyzer
    // -------------------------------------------------------------------------
    // The ILA consumes wb_data and pc, preventing Vivado from optimizing them away!
    ila_1 ILA (
        .clk(cpu_clk),         
        .probe0(wb_data),
        .probe1(pc)
    );
`endif

endmodule