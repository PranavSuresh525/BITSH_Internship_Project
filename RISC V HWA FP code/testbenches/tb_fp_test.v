`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_fp_test.v  --  FP32 pipeline integration test
//
// Tests fmul.s / fadd.s / fsub.s / fmin.s / fmax.s / feq.s / flt.s / fle.s
// through the full RISC-V pipeline.
//
// HOW TO RUN:
//   1. Assemble:  python3 assembly.py   (with fp_test.s renamed to firmware.s)
//                 OR directly use the pre-built fp_test.hex if provided.
//   2. Simulate:  iverilog -g2012 -o fp_sim \
//                   tb_fp_test.v RISC_V_PROCESSOR.v INSTRUCTION_MEMORY.v \
//                   DATA_MEMORY.v ... (all your pipeline files) \
//                 vvp fp_sim
//
// Expected register values after execution (read from regfile):
//   x3  = 0x40400000  (3.0)
//   x5  = 0x40600000  (3.5)
//   x6  = 0x40200000  (2.5)
//   x7  = 0x40100000  (2.25)
//   x8  = 0x3FC00000  (1.5  -- fmin)
//   x9  = 0x40000000  (2.0  -- fmax)
//   x10 = 32'd1       (feq true)
//   x11 = 32'd1       (flt true)
//   x12 = 32'd0       (fle false)
//////////////////////////////////////////////////////////////////////////////
module tb_fp_test;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg         clk, reset;
    wire [31:0] pc;
    wire [31:0] instruction;
    wire        unrecognized;
    wire [31:0] wb_data;

    INSTRUCTION_MEMORY imem (
        .clk        (clk),
        .reset      (reset),
        .pc         (pc),
        .instruction(instruction)
    );

    RISC_V_PROCESSOR cpu (
        .clk           (clk),
        .reset         (reset),
        .unrecognized  (unrecognized),
        .wb_data       (wb_data),
        .pc_out        (pc),
        .instruction_in(instruction)
    );

    always #5 clk = ~clk;   // 100 MHz

    // ----------------------------------------------------------------
    // Expected values
    // ----------------------------------------------------------------
    // FP32 bit patterns
    localparam [31:0] EXP_X3  = 32'h40400000; // 3.0
    localparam [31:0] EXP_X5  = 32'h40600000; // 3.5
    localparam [31:0] EXP_X6  = 32'h40200000; // 2.5
    localparam [31:0] EXP_X7  = 32'h40100000; // 2.25
    localparam [31:0] EXP_X8  = 32'h3FC00000; // 1.5 (fmin)
    localparam [31:0] EXP_X9  = 32'h40000000; // 2.0 (fmax)
    localparam [31:0] EXP_X10 = 32'd1;        // feq true
    localparam [31:0] EXP_X11 = 32'd1;        // flt true
    localparam [31:0] EXP_X12 = 32'd0;        // fle false

    // ----------------------------------------------------------------
    // Helpers: read register directly from the regfile
    // (path: cpu.decode_stage.regfile_inst.registers[n] -- adjust if
    //  your hierarchy uses a different instance name)
    // ----------------------------------------------------------------
    function [31:0] read_reg;
    input integer n;
    begin
        read_reg = cpu.dc_s.r1.GPP[n];
    end
endfunction

    // ----------------------------------------------------------------
    // Test logic
    // ----------------------------------------------------------------
    integer cycle;
    integer pass_count, fail_count;

    task check;
        input [4:0]  reg_num;
        input [31:0] got;
        input [31:0] expected;
        input [63:0] test_name; // up to 8 chars as ASCII
        begin
            if (got === expected) begin
                $display("  PASS  x%-2d | got 0x%08h | expected 0x%08h | %s",
                          reg_num, got, expected, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  x%-2d | got 0x%08h | expected 0x%08h | %s",
                          reg_num, got, expected, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Simulation entry point
    // ----------------------------------------------------------------
    initial begin
        clk = 0; reset = 1;
        pass_count = 0; fail_count = 0;

        // Reset for 4 cycles
        repeat(4) @(posedge clk);
        reset = 0;

        // Run for enough cycles for all 9 FP instructions to retire.
        // Each li expands to 2 instructions; worst case with stalls: 
        // 3*li(6) + 9 FP + 5-stage pipeline depth + some stall margin = ~60 cycles.
        repeat(200) @(posedge clk);

        // ---- check results ----
        $display("");
        $display("================================================================");
        $display("  FP32 PIPELINE TEST RESULTS");
        $display("================================================================");

        check(3,  read_reg(3),  EXP_X3,  "fmul 1.5*2.0=3.0 ");
        check(5,  read_reg(5),  EXP_X5,  "fadd 3.0+0.5=3.5 ");
        check(6,  read_reg(6),  EXP_X6,  "fsub 3.0-0.5=2.5 ");
        check(7,  read_reg(7),  EXP_X7,  "fmul 1.5*1.5=2.25");
        check(8,  read_reg(8),  EXP_X8,  "fmin(1.5,2.0)=1.5");
        check(9,  read_reg(9),  EXP_X9,  "fmax(1.5,2.0)=2.0");
        check(10, read_reg(10), EXP_X10, "feq 1.5==1.5 -> 1");
        check(11, read_reg(11), EXP_X11, "flt 1.5< 2.0 -> 1");
        check(12, read_reg(12), EXP_X12, "fle 2.0<=1.5 -> 0");

        $display("================================================================");
        $display("  PASSED: %0d / 9    FAILED: %0d / 9", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0)
            $display("  >>> ALL FP32 TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED -- check regfile hierarchy path <<<");

        $finish;
    end

    // ----------------------------------------------------------------
    // Optional: print register file dump every 20 cycles for debugging
    // ----------------------------------------------------------------
    // Uncomment the block below if results look wrong and you need
    // a cycle-by-cycle trace of what the pipeline is doing.
    //
    // initial begin
    //     #0; reset = 1;
    //     forever begin
    //         @(posedge clk);
    //         if (!reset)
    //             $display("t=%0t pc=%0h x1=%h x2=%h x3=%h x4=%h x5=%h x6=%h",
    //                      $time, pc,
    //                      read_reg(1), read_reg(2), read_reg(3),
    //                      read_reg(4), read_reg(5), read_reg(6));
    //     end
    // end

endmodule