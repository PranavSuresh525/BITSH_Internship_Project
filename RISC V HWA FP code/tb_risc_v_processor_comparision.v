`timescale 1ns / 1ps

// =========================================================================
// COMBINED timing testbench. Loads a unified firmware, runs the SW matmul
// followed immediately by the HWA matmul.
// Compares both to golden reference and outputs side-by-side performance metrics.
// =========================================================================
module tb_combined_timing;
    `include "bf16_ref.vh"

    // Set to 16 to match your hardware, change back to 2 if testing small
    parameter N = 2; 
    parameter ARCH_TYPE = "WS";
    
    // Limit large enough to encompass both SW + HWA sequential runs
    parameter CYCLE_LIMIT_TOTAL = (N*N*N*400) + (N*N*10) + 60000;
    parameter VERBOSE = 0;

    reg clk;
    reg reset;

    // Instantiate the cleanly wrapped top module
    RISC_V_SOC_TOP #(
        .N(N),
        .ARCH_TYPE(ARCH_TYPE)
    ) dut (
        .clk(clk),
        .reset(reset)
    );

    always #10 clk = ~clk;

    // ---- Unified Memory Map (MUST mirror risc_code_combined.c) ----
    localparam ABASE         = 0;
    localparam BBASE         = N * N * 4;
    localparam CBASE_SW      = N * N * 8;
    localparam CBASE_HWA     = N * N * 12;
    localparam DONE_SW_ADDR  = N * N * 16;
    localparam DONE_HWA_ADDR = N * N * 16 + 4;
    localparam [31:0] DONE_TOKEN_SW  = 32'hDEADBEEF;
    localparam [31:0] DONE_TOKEN_HWA = 32'hCAFEBBAE;

    integer i, j, x;
    real MASSIVE_A[0:N-1][0:N-1];
    real MASSIVE_B[0:N-1][0:N-1];
    real GOLDEN_RESULT[0:N-1][0:N-1];
    real SW_RESULT[0:N-1][0:N-1];
    real HWA_RESULT[0:N-1][0:N-1];

    real abserr_sw, relerr_sw, sum_ape_sw, sw_mapd;
    real abserr_hwa, relerr_hwa, sum_ape_hwa, hwa_mapd;
    integer sw_fails, hwa_fails;
    integer cyc, absolute_sw_done_cyc, absolute_hwa_done_cyc;
    integer sw_duration, hwa_duration;

    generate
        if (VERBOSE) begin : TRACE
            always @(negedge clk)
                $display("t=%0t pc=%h instr=%h unrecognized=%b wb_data=%h",
                          $time, dut.processor.pc_out, dut.processor.instruction_in, 
                          dut.processor.unrecognized, dut.processor.wb_data);
        end
    endgenerate
    
    integer mem_file;
    
    initial begin
        clk = 0;
        reset = 1;
        sw_fails = 0;
        hwa_fails = 0;
        absolute_sw_done_cyc = -1;
        absolute_hwa_done_cyc = -1;

        // 1. Generate Input Data
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                MASSIVE_A[i][j] = ($random % 1000) / 1000.0;
                MASSIVE_B[i][j] = ($random % 1000) / 1000.0;
            end
        end
        /*for(i=0; i<N; i=i+1) begin
            for(j=0; j<N; j=j+1) begin
                MASSIVE_A[i][j] = 1.0*(i+j);
                MASSIVE_B[i][j] = 1.0*(i-j);
            end
        end*/
        // --- AUTO-GENERATE MEMORY FILE FOR HARDWARE ---
        mem_file = $fopen("data_memory.mem", "w");
        
        // Write Matrix A to addresses 0 to (N*N-1)
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                $fdisplay(mem_file, "%08x", {16'd0, real_to_bf16(MASSIVE_A[i][j])});
            end
        end
        
        // Write Matrix B to addresses N*N to (2*N*N-1)
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                $fdisplay(mem_file, "%08x", {16'd0, real_to_bf16(MASSIVE_B[i][j])});
            end
        end
        
        // Pad the rest of the memory with zeros (for C_SW, C_HWA, and tokens)
        // Adjust the loop count if your physical RAM is larger
        for (i = 0; i < (N*N*2 + 10); i = i + 1) begin 
            $fdisplay(mem_file, "00000000");
        end
        
        $fclose(mem_file);
        $display("[SYSTEM] data_memory.mem generated successfully for hardware synthesis.");
        // ----------------------------------------------
        // 2. Compute Golden Result
        $display("Computing golden reference matmul (%0dx%0d)...", N, N);
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                GOLDEN_RESULT[i][j] = 0.0;
                for (x = 0; x < N; x = x + 1)
                    GOLDEN_RESULT[i][j] = GOLDEN_RESULT[i][j] + (MASSIVE_A[i][x] * MASSIVE_B[x][j]);
            end
        end

        reset = 1;
        @(posedge clk);

        // 3. Load Memory using the hierarchical path
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                dut.processor.data_memory.memory[(ABASE>>2) + i*N + j] = {16'd0, real_to_bf16(MASSIVE_A[i][j])};
                dut.processor.data_memory.memory[(BBASE>>2) + i*N + j] = {16'd0, real_to_bf16(MASSIVE_B[i][j])};
            end
        end
        dut.processor.data_memory.memory[DONE_SW_ADDR >> 2]  = 32'h0;
        dut.processor.data_memory.memory[DONE_HWA_ADDR >> 2] = 32'h0;
        @(posedge clk);
        reset = 0;

        // 4. Run Cycle Monitoring
        $display("Running combined SW -> HWA matmul. Awaiting completion tokens...");
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
        sum_ape_sw = 0.0;
        sum_ape_hwa = 0.0;

        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                // Extract from simulated memory
                SW_RESULT[i][j]  = bf16_to_real(dut.processor.data_memory.memory[(CBASE_SW >> 2)  + i*N + j][15:0]);
                HWA_RESULT[i][j] = bf16_to_real(dut.processor.data_memory.memory[(CBASE_HWA >> 2) + i*N + j][15:0]);

                // Check SW
                abserr_sw = SW_RESULT[i][j] - GOLDEN_RESULT[i][j];
                if (abserr_sw < 0) abserr_sw = -abserr_sw;
                relerr_sw = (GOLDEN_RESULT[i][j] == 0.0) ?
                    abserr_sw : abserr_sw / ((GOLDEN_RESULT[i][j] < 0) ? -GOLDEN_RESULT[i][j] : GOLDEN_RESULT[i][j]);
                sum_ape_sw = sum_ape_sw + relerr_sw;
                if (abserr_sw > 0.10 * ((GOLDEN_RESULT[i][j] < 0) ? -GOLDEN_RESULT[i][j] : GOLDEN_RESULT[i][j]) && abserr_sw > 1.0)
                    sw_fails = sw_fails + 1;

                // Check HWA
                abserr_hwa = HWA_RESULT[i][j] - GOLDEN_RESULT[i][j];
                if (abserr_hwa < 0) abserr_hwa = -abserr_hwa;
                relerr_hwa = (GOLDEN_RESULT[i][j] == 0.0) ?
                    abserr_hwa : abserr_hwa / ((GOLDEN_RESULT[i][j] < 0) ? -GOLDEN_RESULT[i][j] : GOLDEN_RESULT[i][j]);
                sum_ape_hwa = sum_ape_hwa + relerr_hwa;
                if (abserr_hwa > 0.10 * ((GOLDEN_RESULT[i][j] < 0) ? -GOLDEN_RESULT[i][j] : GOLDEN_RESULT[i][j]) && abserr_hwa > 1.0)
                    hwa_fails = hwa_fails + 1;
            end
        end

        sw_mapd = 100.0 * sum_ape_sw / (N * N);
        hwa_mapd = 100.0 * sum_ape_hwa / (N * N);

        // 7. Final Report
        $display("\n=========================================================================");
        $display("                   COMBINED MATMUL EXECUTION REPORT                      ");
        $display("=========================================================================");
        $display(" MATRIX SIZE            : %0dx%0d", N, N);
        $display("-------------------------------------------------------------------------");
        $display(" [SOFTWARE PATH]");
        $display(" Cycles elapsed         : %0d", sw_duration);
        $display(" Accuracy (MAPD)        : %f%%", sw_mapd);
        $display(" Mismatches vs Golden   : %0d / %0d", sw_fails, N*N);
        $display("-------------------------------------------------------------------------");
        $display(" [HARDWARE ACCELERATOR PATH]");
        $display(" Cycles elapsed         : %0d", hwa_duration);
        $display(" Accuracy (MAPD)        : %f%%", hwa_mapd);
        $display(" Mismatches vs Golden   : %0d / %0d", hwa_fails, N*N);
        $display("-------------------------------------------------------------------------");
        if (sw_duration > 0 && hwa_duration > 0)
            $display(" SPEEDUP (SW/HWA)       : %.2fx", $itor(sw_duration) / $itor(hwa_duration));
        $display("=========================================================================");
        
        if (sw_fails == 0 && hwa_fails == 0)
            $display(" >>> ALL PATHS PASSED ACCURACY CHECKS <<<");
        else
            $display(" >>> WARNING: ACCURACY FAILURE(S) DETECTED <<<");
        
        $finish;
    end
endmodule