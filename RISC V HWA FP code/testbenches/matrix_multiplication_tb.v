`timescale 1ns/1ps

module matrix_multiply_hardware_tb;

    parameter N = 32;
    parameter ARCH_TYPE = "DIP"; 
    localparam TOTAL_COMPUTECYCLES = (ARCH_TYPE == "WS") ? (4*N) : (3*N + 1);

    localparam MEM_SIZE = 4 * N * N;

    reg         clk;
    reg         reset;
    reg [31:0]  configure_data;
    reg         hwa;
    reg [2:0]   funct3;

    wire        hwa_mem_write;
    wire        hwa_mem_read;
    wire        stall_request;
    wire [31:0] next_address;
    wire [31:0] output_data; 
    wire        load_done;

    reg [31:0]  data;

    reg [31:0]  mock_data_memory [0:MEM_SIZE-1];
    reg [31:0]  captured_C_mem   [0:MEM_SIZE-1]; 
    reg [31:0]  expected_C       [0:N*N-1];
    
    integer r, c, k_idx, i;
    reg [31:0] temp_sum;

    matrix_multiply_hardware #(
        .ARCH_TYPE(ARCH_TYPE),
        .N(N)
    ) uut (
        .clk(clk),
        .reset(reset),
        .configure_data(configure_data),
        .hwa(hwa),
        .data(data),
        .hwa_mem_write(hwa_mem_write),
        .hwa_mem_read(hwa_mem_read),
        .funct3(funct3),
        .stall_request(stall_request),
        .next_address(next_address),
        .output_data(output_data),
        .load_done(load_done)
    );

    always #5 clk = ~clk;

    always @(*) begin
        if (hwa_mem_read)
            data = mock_data_memory[next_address >> 2];
        else
            data = 32'b0;
    end

    always @(posedge clk) begin
        if (hwa_mem_write) begin
            captured_C_mem[next_address >> 2] <= output_data;   
        end
    end

    initial begin
        clk = 1;
        reset = 1;
        configure_data = 32'd0;
        hwa = 0;
        funct3 = 3'b000;

        for (i = 0; i < N*N; i = i + 1) begin
            mock_data_memory[i]       = (i % 4) + 1; 
            mock_data_memory[i + N*N] = (i % 3) + 1; 
            captured_C_mem[i]         = 32'b0;
            expected_C[i]             = 32'b0;
        end

        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                temp_sum = 0;
                for (k_idx = 0; k_idx < N; k_idx = k_idx + 1) begin
                    temp_sum = temp_sum + (mock_data_memory[r * N + k_idx] * mock_data_memory[N*N + (k_idx * N + c)]);
                end
                expected_C[r * N + c] = temp_sum;
            end
        end

        #20;
        reset = 0;
        #10;

        // STEP 1: LOAD A
        configure_data = 32'd0; 
        funct3 = 3'b000;        
        hwa = 1;                
        #10; hwa = 0; 
        while (stall_request) #10;

        // STEP 2: LOAD B & COMPUTE
        configure_data = N * N * 4; 
        funct3 = 3'b001;         
        hwa = 1;
        #10; hwa = 0;
        while (stall_request) #10;

        // STEP 3: STREAM OUTPUT C
        configure_data = 2 * N * N * 4; 
        funct3 = 3'b011;          
        hwa = 1;
        #10; hwa = 0;
        while (stall_request) #10;

        // STEP 4: VERIFICATION
        #100;
        $display("\n============= TEST RECAP =============");
        $display("Architecture Profile Target: %s", ARCH_TYPE);
        $display("Matrix Dimension (N): %0d x %0d", N, N);
        $display("Expected Processing Latency Window: %0d Cycles", TOTAL_COMPUTECYCLES);
        $display("Checking computed block footprints directly from memory spaces...");
        
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                if (captured_C_mem[(2*N*N) + (r*N+c)] == expected_C[r * N + c]) begin
                    $display("MATCH: Cell [%0d][%0d] -> Got: %0d, Expected: %0d", r, c, captured_C_mem[(2 * N * N) + (r * N + c)], expected_C[r * N + c]);
                end else begin
                    $display("MISMATCH ALERT! Cell [%0d][%0d] -> Got: %0d, Expected: %0d", r, c, captured_C_mem[(2 * N * N) + (r * N + c)], expected_C[r * N + c]);
                end
            end
        end
        
        $display("=======================================");
        $finish;
    end
endmodule