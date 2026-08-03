`timescale 1ns/1ps

module DATA_MEMORY #(
    parameter MEMORY_SIZE = 4096   
)(
    input clk,
    input hwa_active,

    input [31:0] cpu_address,
    input [31:0] cpu_write_data,
    input cpu_mem_write,
    input cpu_mem_read,

    input [31:0] hwa_address,
    input [31:0] hwa_write_data,
    input hwa_mem_write,
    input hwa_mem_read,

    output [31:0] read_data
);

    wire active_mem_write         = hwa_active ? hwa_mem_write    : cpu_mem_write;
    wire active_mem_read          = hwa_active ? hwa_mem_read     : cpu_mem_read;
    wire [31:0] active_address    = hwa_active ? hwa_address      : cpu_address;
    wire [31:0] active_write_data = hwa_active ? hwa_write_data   : cpu_write_data;

    wire [31:0] word_index = active_address >> 2;
    wire [$clog2(MEMORY_SIZE)-1:0] bram_addr = word_index[$clog2(MEMORY_SIZE)-1:0];
    
  

`ifndef SYNTHESIS
    // -------------------------------------------------------------------------
    // SIMULATION MODEL
    // -------------------------------------------------------------------------
    reg [31:0] memory [0:MEMORY_SIZE-1];
    reg [31:0] dout_reg;

    integer i;
    initial begin
        for (i = 0; i < MEMORY_SIZE; i = i + 1)
            memory[i] = 32'h00000000;
    end

    always @(posedge clk) begin
        if (active_mem_write && (word_index < MEMORY_SIZE)) begin
            memory[word_index] <= active_write_data;
        end

        if (active_mem_read && (word_index < MEMORY_SIZE)) begin
            dout_reg <= memory[word_index];
        end else begin
            dout_reg <= 32'b0;
        end
    end

    assign read_data = dout_reg;

`else
    // -------------------------------------------------------------------------
    // SYNTHESIS MODEL: Vivado XPM Macro (Single Port RAM)
    // -------------------------------------------------------------------------
    wire [31:0] bram_dout;
    reg         read_valid_q;

    // Pipeline register to track when a read was requested
    always @(posedge clk) begin
        read_valid_q <= active_mem_read;
    end

    xpm_memory_spram #(
        .MEMORY_SIZE(MEMORY_SIZE * 32),  // Total size in bits
        .MEMORY_PRIMITIVE("block"),      // Strictly force BRAM mapping
        .MEMORY_INIT_FILE("data_memory.mem"), // <--- THIS LOADS YOUR FILE
        .MEMORY_INIT_PARAM("0"),              // <--- Sets uninitialized bits to 0
        .READ_LATENCY_A(1),              // 1 cycle latency (matches simulation)
        .ADDR_WIDTH_A($clog2(MEMORY_SIZE)),
        .READ_DATA_WIDTH_A(32),
        .WRITE_DATA_WIDTH_A(32),
        .BYTE_WRITE_WIDTH_A(32),         // No byte-enables, write the whole 32-bit word
        .WRITE_MODE_A("read_first")
    ) data_bram_inst (
        .sleep(1'b0),
        .clka(clk),
        .ena(active_mem_write | active_mem_read), // Enable RAM only on active operations
        .wea(active_mem_write),
        .addra(bram_addr),
        .dina(active_write_data),
        .douta(bram_dout),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .sbiterra(),
        .dbiterra()
    );

    // Mux outside the BRAM to guarantee the '0' output behavior your CPU expects
    assign read_data = read_valid_q ? bram_dout : 32'b0;

`endif
endmodule 