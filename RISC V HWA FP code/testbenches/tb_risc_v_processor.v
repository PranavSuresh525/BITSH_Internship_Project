`timescale 1ns /1ps

module tb_risc_v_processor;
    `include "bf16_ref.vh"

    parameter CYCLE_LIMIT = 10000;
    parameter VERBOSE     = 0;
    parameter N = 4;

    reg clk, reset;
    wire [31:0] pc;
    wire [31:0] instruction;
    wire        unrecognized;
    wire [31:0] wb_data;

    INSTRUCTION_MEMORY imem (
        .clk(clk), .reset(reset),
        .pc(pc), .instruction(instruction)
    );

    RISC_V_PROCESSOR cpu (
        .clk(clk), .reset(reset),
        .unrecognized(unrecognized),
        .wb_data(wb_data),
        .pc_out(pc),
        .instruction_in(instruction)
    );

    always #10 clk = ~clk;

    // CPU Memory Map Base Addresses
    localparam ABASE = 0;
    localparam BBASE = N * N * 4;  
    localparam CBASE = N * N * 8;

    localparam M = 69;
    localparam K = 67;

    integer i, j, x, m_idx, n_idx, k_idx;
    real MASSIVE_A[0:M-1][0:N-1];
    real MASSIVE_B[0:N-1][0:K-1];
    real MASSIVE_C[0:M-1][0:K-1];
    real MASSIVE_GOLD[0:M-1][0:K-1]; 
    
    real tile_a, tile_b, got;
    real abserr, relerr, maxrelerr, sum_ape, mapd, sum_absgold, avg_absgold;
    
    integer fails, cyc, load_done_count;
    reg [31:0] read_back_val;

    // =========================================================================
    // POST-IMPL MEMORY INJECTION TASKS (HIDDEN FROM ICARUS)
    // =========================================================================
`ifndef __ICARUS__
    task write_mem(input [31:0] w_addr, input [31:0] w_data);
    begin
        force cpu.data_memory.cpu_mem_write = 1'b1;      
        force cpu.data_memory.cpu_address = w_addr << 2;  
        force cpu.data_memory.cpu_write_data = w_data;   
        @(posedge clk);
        #1; 
        release cpu.data_memory.cpu_mem_write;
        release cpu.data_memory.cpu_address;
        release cpu.data_memory.cpu_write_data;
    end
    endtask

    task read_mem(input [31:0] r_addr, output [31:0] r_data);
    begin
        force cpu.data_memory.cpu_mem_write = 1'b0;
        force cpu.data_memory.cpu_mem_read = 1'b1;      
        force cpu.data_memory.cpu_address = r_addr << 2;
        @(posedge clk);
        @(posedge clk); 
        #1;
        r_data = cpu.data_memory.read_data;        
        release cpu.data_memory.cpu_mem_write;
        release cpu.data_memory.cpu_mem_read;
        release cpu.data_memory.cpu_address;
    end
    endtask
`endif
    // =========================================================================

    generate
        if (VERBOSE) begin : TRACE
            always @(negedge clk)
                $display("t=%0t pc=%0d instr=%h unrecognized=%b wb_data=%h hwa=%b funct3=%b",
                          $time, pc, instruction, unrecognized, wb_data,
                          cpu.hwa_trigger, cpu.ex_funct_3);
        end
    endgenerate

    initial begin
        clk = 0; reset = 1;
        fails = 0; maxrelerr = 0.0;

        // 1. Initialize Massive Matrices & Calculate Golden Reference
        for (i = 0; i < M; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                MASSIVE_A[i][j] = ($random % 1000) / 1000.0;

        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < K; j = j + 1)
                MASSIVE_B[i][j] = ($random % 1000) / 1000.0;

        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                MASSIVE_C[i][j] = 0.0; 
                MASSIVE_GOLD[i][j] = 0.0;
                for (x = 0; x < N; x = x + 1) begin
                    MASSIVE_GOLD[i][j] = MASSIVE_GOLD[i][j] + (MASSIVE_A[i][x] * MASSIVE_B[x][j]);
                end
            end
        end

        $display("Starting Host-Driven Matrix Tiling (%0dx%0d * %0dx%0d = %0dx%0d Output)...", M, N, N, K, M, K);

        for (m_idx = 0; m_idx < M; m_idx = m_idx + N) begin
            for (k_idx = 0; k_idx < K; k_idx = k_idx + N) begin
                for (n_idx = 0; n_idx < N; n_idx = n_idx + N) begin
                    
                    // --- STEP A: Halt CPU and Inject Tiles ---
                    reset = 1; 
                    @(posedge clk);
                    
                    for (i = 0; i < N; i = i + 1) begin
                        for (j = 0; j < N; j = j + 1) begin
                            if ((m_idx+i < M) && (n_idx+j < N)) tile_a = MASSIVE_A[m_idx+i][n_idx+j];
                            else tile_a = 0.0;
                            
                            if ((n_idx+i < N) && (k_idx+j < K)) tile_b = MASSIVE_B[n_idx+i][k_idx+j];
                            else tile_b = 0.0;

`ifdef __ICARUS__
                            // ICARUS RTL FAST PATH
                            cpu.data_memory.memory[(ABASE>>2) + i*N + j] = {16'd0, real_to_bf16(tile_a)};
                            cpu.data_memory.memory[(BBASE>>2) + i*N + j] = {16'd0, real_to_bf16(tile_b)};
`else
                            // VIVADO NETLIST PATH
                            write_mem( (ABASE>>2) + i*N + j, {16'd0, real_to_bf16(tile_a)} );
                            write_mem( (BBASE>>2) + i*N + j, {16'd0, real_to_bf16(tile_b)} );
`endif
                        end
                    end

                    // --- STEP B: Release CPU to run C Code ---
                    @(posedge clk);
                    reset = 0;

                    // --- STEP C: Wait for Hardware to Finish ---
                    load_done_count = 0;
                    cyc = 0;
                    while (load_done_count < 3 && cyc < (N*N*4 + 1000)) begin
                        @(negedge clk);
                        cyc = cyc + 1;
                        if (cpu.hwa_inst.load_done) load_done_count = load_done_count + 1;
                    end

                    if (cyc >= (N*N*4 + 1000)) begin
                        $display("TIMEOUT at Tile m=%0d, k=%0d, n=%0d. Hardware hung.", m_idx, k_idx, n_idx);
                        $finish;
                    end

                    // --- STEP D: Read Back and Accumulate ---
                    reset = 1; 
                    @(negedge clk); 
                    
                    for (i = 0; i < N; i = i + 1) begin
                        for (j = 0; j < N; j = j + 1) begin
                            if ((m_idx+i < M) && (k_idx+j < K)) begin
`ifdef __ICARUS__
                                // ICARUS RTL FAST PATH
                                got = bf16_to_real(cpu.data_memory.memory[(CBASE>>2) + i*N + j][15:0]);
`else
                                // VIVADO NETLIST PATH
                                read_mem( (CBASE>>2) + i*N + j, read_back_val );
                                got = bf16_to_real(read_back_val[15:0]);
`endif
                                MASSIVE_C[m_idx+i][k_idx+j] = MASSIVE_C[m_idx+i][k_idx+j] + got;
                            end
                        end
                    end

                end
            end
        end

       // 3. Automated Verification and Printout
        sum_ape = 0.0; sum_absgold = 0.0;
        $display("\n=========================================================================");
        $display("                     DETAILED MATRIX RESULTS                             ");
        $display("=========================================================================");
        
        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                abserr = MASSIVE_C[i][j] - MASSIVE_GOLD[i][j]; 
                if (abserr < 0) abserr = -abserr;
                
                relerr = (MASSIVE_GOLD[i][j] == 0.0) ? abserr : abserr / ((MASSIVE_GOLD[i][j] < 0) ? -MASSIVE_GOLD[i][j] : MASSIVE_GOLD[i][j]);
                if (relerr > maxrelerr) maxrelerr = relerr;
                
                sum_ape = sum_ape + relerr;
                sum_absgold = sum_absgold + ((MASSIVE_GOLD[i][j] < 0) ? -MASSIVE_GOLD[i][j] : MASSIVE_GOLD[i][j]);
            end
        end

        mapd = 100.0 * sum_ape / (M * K);
        avg_absgold = sum_absgold / (M * K);

        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                abserr = MASSIVE_C[i][j] - MASSIVE_GOLD[i][j]; 
                if (abserr < 0) abserr = -abserr;
                relerr = (MASSIVE_GOLD[i][j] == 0.0) ? abserr : abserr / ((MASSIVE_GOLD[i][j] < 0) ? -MASSIVE_GOLD[i][j] : MASSIVE_GOLD[i][j]);

                // MODIFIED: Print every element, tagging as [MISMATCH] or [OK]
                if (abserr > 0.10 * avg_absgold && abserr > 1.0) begin
                    fails = fails + 1;
                    $display("[MISMATCH] Row %2d, Col %2d | Got: %8.4f | Expected: %8.4f | Error: %6.2f%%", 
                              i, j, MASSIVE_C[i][j], MASSIVE_GOLD[i][j], relerr * 100.0);
                end else begin
                    $display("[OK]       Row %2d, Col %2d | Got: %8.4f | Expected: %8.4f | Error: %6.2f%%", 
                              i, j, MASSIVE_C[i][j], MASSIVE_GOLD[i][j], relerr * 100.0);
                end
            end
        end

        $display("=========================================================================");
        $display(" OVERALL MAPD (Mean Absolute Percentage Error) : %f%%", mapd);
        $display(" TOTAL ELEMENT MISMATCHES                      : %0d / %0d", fails, M*K);
        $display("=========================================================================");
        
        if (fails == 0) $display(" >>> HOST TILING VERIFICATION COMPLETE: PASSED <<<");
        else $display(" >>> HOST TILING VERIFICATION COMPLETE: FAILED <<<");
        $finish;
    end
endmodule