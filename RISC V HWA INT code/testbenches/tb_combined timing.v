`timescale 1ns / 1ps

// =========================================================================
// COMBINED INTEGER SOC TESTBENCH -- INSTRUMENTED FOR 14-CYCLE TRACE
//
// Adds a per-cycle diagnostic trace, active only while the accelerator
// wrapper (matrix_multiply_hardware) is busy, to isolate exactly where
// the unexplained constant overhead (beyond 3N^2 + array-drain-latency)
// is coming from.
//
// Hierarchy used for probes (confirmed from RTL):
//   dut.processor.hwa_inst              -- matrix_multiply_hardware
//   dut.processor.hwa_inst.u_dip        -- ws_top or dip_top (same instance
//                                          name in both generate branches)
//   dut.processor.hwa_inst.u_dip.u_fsm  -- ws_fsm or dip_fsm
//   dut.processor.hwa_inst.u_dip.u_array-- ws_array or dip_array
//
// RECOMMENDATION: run this with a SMALL N first (e.g. N=4) so the trace
// is short enough to read by eye and pinpoint the exact gap. Once you
// know what to look for, re-run at N=32 to confirm the same gap appears
// (just further down the log).
// =========================================================================
module tb_combined_integer_timing;

    // ----------------------------------------------------
    // PARAMETERS
    // ----------------------------------------------------
    parameter N = 4;              // <-- reduced from 32 for a readable trace.
                                   //     Bump back to 32 once the gap is found.
    parameter ARCH_TYPE = "WS";
    
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
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk; // 100MHz clock

    // ---- Unified Memory Map (MUST mirror your integer C code) ----
    localparam ABASE         = 0;
    localparam BBASE         = N * N * 4;
    localparam CBASE_SW      = N * N * 8;
    localparam CBASE_HWA     = N * N * 12;
    localparam DONE_SW_ADDR  = N * N * 16;
    localparam DONE_HWA_ADDR = N * N * 16 + 4;
    
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
    // INSTRUMENTATION STATE (for the diagnostic trace)
    // ----------------------------------------------------
    reg        trace_active;      // gates printing to only the HWA-busy window
    reg [2:0]  hwa_state_prev;
    reg        array_start_prev;
    reg        array_done_prev;
    integer    hwa_window_cyc;    // cycle counter local to the CURRENT hwa call
    integer    phase_start_cyc;   // absolute cyc when the current phase's
                                   // hwa_rise fired (for computing per-phase duration)

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

    // ----------------------------------------------------
    // ARCHITECTURE PROBES (Auto-switches based on ARCH_TYPE)
    // ----------------------------------------------------
    wire [31:0] probe_fsm_state;
    wire [31:0] probe_fsm_cyc;
    wire        probe_array_out_valid;
    wire [31:0] probe_out_cnt;

    generate
        if (ARCH_TYPE == "WS") begin
            assign probe_fsm_state       = dut.processor.hwa_inst.gen_ws.u_dip.u_fsm.state;
            assign probe_fsm_cyc         = dut.processor.hwa_inst.gen_ws.u_dip.u_fsm.cyc;
            assign probe_array_out_valid = dut.processor.hwa_inst.gen_ws.u_dip.array_out_valid;
            assign probe_out_cnt         = dut.processor.hwa_inst.gen_ws.u_dip.u_fsm.out_cnt;
        end else begin
            assign probe_fsm_state       = dut.processor.hwa_inst.gen_dip.u_dip.u_fsm.state;
            assign probe_fsm_cyc         = dut.processor.hwa_inst.gen_dip.u_dip.u_fsm.cyc;
            assign probe_array_out_valid = dut.processor.hwa_inst.gen_dip.u_dip.array_out_valid;
            assign probe_out_cnt         = dut.processor.hwa_inst.gen_dip.u_dip.u_fsm.out_cnt;
        end
    endgenerate
    initial begin
        clk = 0;
        reset = 1;
        sw_fails = 0;
        hwa_fails = 0;
        absolute_sw_done_cyc = -1;
        absolute_hwa_done_cyc = -1;
        trace_active = 1'b0;
        hwa_state_prev = 3'd0;
        array_start_prev = 1'b0;
        array_done_prev = 1'b0;
        hwa_window_cyc = 0;
        phase_start_cyc = 0;

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
        dut.processor.data_memory.memory[DONE_SW_ADDR >> 2]  = 32'h0;
        dut.processor.data_memory.memory[DONE_HWA_ADDR >> 2] = 32'h0;
        
        #10;
        reset = 0;

        // 4. Run Cycle Monitoring (Dynamic Intercept) + DIAGNOSTIC TRACE
        $display("[SYSTEM] Running combined SW -> HWA matmul. Awaiting completion tokens...");
        $display("[TRACE ] N=%0d, ARCH_TYPE=%s -- HWA-window trace begins below.", N, ARCH_TYPE);
        $display("[TRACE ] Columns: cyc | hwa_st | a_start | a_busy | a_done | fsm_st | fsm_cyc | arr_valid | out_cnt | note");
        cyc = 0;
        while ((absolute_sw_done_cyc == -1 || absolute_hwa_done_cyc == -1) && cyc < CYCLE_LIMIT_TOTAL) begin
            @(negedge clk);
            cyc = cyc + 1;

            // ---- DIAGNOSTIC TRACE BLOCK ----
            // Fires only while the HWA wrapper is not idle, so SW-only
            // cycles don't flood the log.
            if (dut.processor.hwa_inst.state != 3'd0) begin
                if (!trace_active) begin
                    // Just became active this cycle -- mark the start of a
                    // new phase (LOAD_A / LOAD_B+COMPUTE / STORE_C).
                    trace_active = 1'b1;
                    phase_start_cyc = cyc;
                    hwa_window_cyc = 0;
                    $display("[TRACE ] ---- New HWA phase begins at absolute cyc=%0d (state=%0d) ----",
                              cyc, dut.processor.hwa_inst.state);
                end else begin
                    hwa_window_cyc = hwa_window_cyc + 1;
                end

                $display("[TRACE ] cyc=%0d (+%0d) | hwa_st=%0d | a_start=%b | a_busy=%b | a_done=%b | fsm_st=%0d | fsm_cyc=%0d | arr_valid=%b | out_cnt=%0d%s%s",
                    cyc, hwa_window_cyc,
                    dut.processor.hwa_inst.state,
                    dut.processor.hwa_inst.array_start_r,
                    dut.processor.hwa_inst.array_busy,       
                    dut.processor.hwa_inst.array_done,       
                    probe_fsm_state,          // <-- Uses auto-switching probe
                    probe_fsm_cyc,            // <-- Uses auto-switching probe
                    probe_array_out_valid,    // <-- Uses auto-switching probe
                    probe_out_cnt,            // <-- Uses auto-switching probe
                    (dut.processor.hwa_inst.array_start_r && !array_start_prev) ? "  <-- array_start_r RISING EDGE" : "",
                    (dut.processor.hwa_inst.array_done && !array_done_prev)     ? "  <-- array u_dip.done RISING EDGE" : ""
                );
            end else if (trace_active) begin
                // Just went idle -- phase complete, print duration summary.
                trace_active = 1'b0;
                $display("[TRACE ] ---- HWA phase ended at absolute cyc=%0d. Phase duration = %0d cycles ----\n",
                          cyc, cyc - phase_start_cyc + 1);
            end

            array_start_prev = dut.processor.hwa_inst.array_start_r;
            array_done_prev  = dut.processor.hwa_inst.array_done;
            // ---- END DIAGNOSTIC TRACE BLOCK ----

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
                SW_RESULT[i][j]  = dut.processor.data_memory.memory[(CBASE_SW >> 2)  + i*N + j];
                HWA_RESULT[i][j] = dut.processor.data_memory.memory[(CBASE_HWA >> 2) + i*N + j];

                if (SW_RESULT[i][j] !== GOLDEN_RESULT[i][j]) begin
                    sw_fails = sw_fails + 1;
                    if (VERBOSE) $display("SW MISMATCH [%0d][%0d]: Got %0d, Exp %0d", i, j, SW_RESULT[i][j], GOLDEN_RESULT[i][j]);
                end

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