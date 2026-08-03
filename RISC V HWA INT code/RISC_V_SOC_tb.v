`timescale 1ns / 1ps

// =========================================================================
// COMBINED INTEGER SOC TESTBENCH
// Loads a unified firmware, runs the SW matmul followed by the HWA matmul.
// Compares both against an exact integer golden reference.
// =========================================================================
module tb_combined_integer_timing;

    // ----------------------------------------------------
    // PARAMETERS
    // ----------------------------------------------------
    parameter N = 2; 
    parameter ARCH_TYPE = "DIP";
    
    // Limit large enough to encompass both SW + HWA sequential runs
    parameter CYCLE_LIMIT_TOTAL = (N*N*N*400) + (N*N*10) + 60000;
    parameter VERBOSE = 0; // Set to 1 to print specific mismatch coordinates

    reg clk;
    reg reset;

    // Instantiate the cleanly wrapped top module
    RISC_V_SOC_TOP #(
        .N(N),
        .ARCH_TYPE(ARCH_TYPE),
        .DATA_MEM_WORDS(8192)
    ) dut (
        .sys_clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk; // 100MHz clock

    // ---- Unified Memory Map (MUST mirror your integer C code) ----
    // Note: These are BYTE offsets. We shift by 2 (>> 2) to index the 32-bit word array.
    localparam ABASE         = 0;
    localparam BBASE         = N * N * 4;
    localparam CBASE_SW      = N * N * 8;
    localparam CBASE_HWA     = N * N * 12;
    localparam DONE_SW_ADDR  = N * N * 16;
    localparam DONE_HWA_ADDR = N * N * 16 + 4;
    
    // Tokens expected from the C firmware when a phase completes
    localparam [31:0] DONE_TOKEN_SW  = 32'hDEADBEEF;
    localparam [31:0] DONE_TOKEN_HWA = 32'hCAFEBBAE;

    // Internal Variables for Verification
    integer i, j, x;
    integer MASSIVE_A[0:N-1][0:N-1];
    integer MASSIVE_B[0:N-1][0:N-1];
    integer GOLDEN_RESULT[0:N-1][0:N-1];
    integer SW_RESULT[0:N-1][0:N-1];
    integer HWA_RESULT[0:N-1][0:N-1];

    integer sw_fails, hwa_fails;
    integer cyc, absolute_sw_done_cyc, absolute_hwa_done_cyc;
    integer sw_duration, hwa_duration;

    // ----------------------------------------------------
    // THREAD 1: THE PARALLEL WATCHDOG
    // ----------------------------------------------------
    initial begin
        #(CYCLE_LIMIT_TOTAL * 10);
        $display("\n[!!!] FATAL ERROR: Watchdog Timeout Reached. Simulation killed to prevent infinite hang.");
        $finish;
    end
    
    // ----------------------------------------------------
    // THREAD 2: MAIN SYSTEM EXECUTION
    // ----------------------------------------------------
    initial begin
        clk = 0;
        reset = 1;
        sw_fails = 0;
        hwa_fails = 0;
        absolute_sw_done_cyc = -1;
        absolute_hwa_done_cyc = -1;

        $dumpfile("combined_soc_trace.vcd");
        $dumpvars(0, tb_combined_integer_timing);
        $dumpflush;

        // 1. Generate Integer Input Data
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                MASSIVE_A[i][j] = ((i * N + j) % 5) + 3;
                MASSIVE_B[i][j] = ((i * N + j) % 6) + 7;
            end
        end

        // 2. Compute Exact Golden Result
        $display("[SYSTEM] Computing golden reference integer matmul (%0dx%0d)...", N, N);
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                GOLDEN_RESULT[i][j] = 0;
                for (x = 0; x < N; x = x + 1)
                    GOLDEN_RESULT[i][j] = GOLDEN_RESULT[i][j] + (MASSIVE_A[i][x] * MASSIVE_B[x][j]);
            end
        end

        // 3. Load Memory using the hierarchical path
        #20;
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                dut.processor.data_memory.memory[(ABASE>>2) + i*N + j] = MASSIVE_A[i][j];
                dut.processor.data_memory.memory[(BBASE>>2) + i*N + j] = MASSIVE_B[i][j];
            end
        end
        // Clear completion tokens to prevent false positives
        dut.processor.data_memory.memory[DONE_SW_ADDR >> 2]  = 32'h0;
        dut.processor.data_memory.memory[DONE_HWA_ADDR >> 2] = 32'h0;
        
        #10;
        reset = 0;

        // 4. Run Cycle Monitoring (Dynamic Intercept)
        $display("[SYSTEM] Running combined SW -> HWA matmul. Awaiting completion tokens...");
        cyc = 0;
        while ((absolute_sw_done_cyc == -1 || absolute_hwa_done_cyc == -1) && cyc < CYCLE_LIMIT_TOTAL) begin
            @(negedge clk);
            cyc = cyc + 1;
            
            // Check for SW finish
            if (absolute_sw_done_cyc == -1 && dut.processor.data_memory.memory[DONE_SW_ADDR >> 2] == DONE_TOKEN_SW) begin
                absolute_sw_done_cyc = cyc;
                $display("  -> SW matmul completed at cycle %0d", cyc);
            end
            
            // Check for HWA finish
            if (absolute_hwa_done_cyc == -1 && dut.processor.data_memory.memory[DONE_HWA_ADDR >> 2] == DONE_TOKEN_HWA) begin
                absolute_hwa_done_cyc = cyc;
                $display("  -> HWA matmul completed at cycle %0d", cyc);
            end
        end

        if (absolute_hwa_done_cyc == -1 || absolute_sw_done_cyc == -1) begin
            $display("TIMEOUT waiting for execution to finish (limit=%0d cycles).", CYCLE_LIMIT_TOTAL);
            $finish;
        end

        // 5. Calculate Durations
        sw_duration = absolute_sw_done_cyc;
        hwa_duration = absolute_hwa_done_cyc - absolute_sw_done_cyc;

        // 6. Extract Results & Verify Errors
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                // Extract from simulated memory
                SW_RESULT[i][j]  = dut.processor.data_memory.memory[(CBASE_SW >> 2)  + i*N + j];
                HWA_RESULT[i][j] = dut.processor.data_memory.memory[(CBASE_HWA >> 2) + i*N + j];

                // Check SW
                if (SW_RESULT[i][j] !== GOLDEN_RESULT[i][j]) begin
                    sw_fails = sw_fails + 1;
                    if (VERBOSE) $display("SW MISMATCH [%0d][%0d]: Got %0d, Exp %0d", i, j, SW_RESULT[i][j], GOLDEN_RESULT[i][j]);
                end

                // Check HWA
                if (HWA_RESULT[i][j] !== GOLDEN_RESULT[i][j]) begin
                    hwa_fails = hwa_fails + 1;
                    if (VERBOSE) $display("HWA MISMATCH [%0d][%0d]: Got %0d, Exp %0d", i, j, HWA_RESULT[i][j], GOLDEN_RESULT[i][j]);
                end
            end
        end

        // 7. Final Report
        $display("\n=========================================================================");
        $display("                   COMBINED INTEGER MATMUL EXECUTION REPORT              ");
        $display("=========================================================================");
        $display(" MATRIX SIZE            : %0dx%0d", N, N);
        $display(" ARCHITECTURE           : %s", ARCH_TYPE);
        $display("-------------------------------------------------------------------------");
        $display(" [SOFTWARE PATH]");
        $display(" Cycles elapsed         : %0d", sw_duration);
        $display(" Mismatches vs Golden   : %0d / %0d", sw_fails, N*N);
        $display("-------------------------------------------------------------------------");
        $display(" [HARDWARE ACCELERATOR PATH]");
        $display(" Cycles elapsed         : %0d", hwa_duration);
        $display(" Mismatches vs Golden   : %0d / %0d", hwa_fails, N*N);
        $display("-------------------------------------------------------------------------");
        if (sw_duration > 0 && hwa_duration > 0)
            $display(" SPEEDUP (SW/HWA)       : %.2fx", $itor(sw_duration) / $itor(hwa_duration));
        $display("=========================================================================");
        
        if (sw_fails == 0 && hwa_fails == 0)
            $display(" >>> ALL PATHS PASSED EXACT ACCURACY CHECKS <<<");
        else
            $display(" >>> WARNING: ACCURACY FAILURE(S) DETECTED <<<");
        
        $finish;
    end
endmodule