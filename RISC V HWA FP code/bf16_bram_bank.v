`timescale 1ns / 1ps

module bf16_bram_bank #(
    parameter DEPTH = 16
)(
    input  wire                     clk,
    input  wire                     we,
    input  wire [$clog2(DEPTH)-1:0] wr_addr,
    input  wire [15:0]              din,
    input  wire [$clog2(DEPTH)-1:0] rd_addr,
    output wire [15:0]              dout
);
    localparam ADDR_W = $clog2(DEPTH);

`ifndef SYNTHESIS
    // Simulation Model
    reg [15:0] ram [0:DEPTH-1];
    reg [15:0] dout_reg;
    
    always @(posedge clk) begin
        if (we) ram[wr_addr] <= din;
        dout_reg <= ram[rd_addr];
    end
    assign dout = dout_reg;
`else
    // Synthesis Model: Vivado XPM Macro
    xpm_memory_sdpram #(
        .MEMORY_SIZE(DEPTH * 16), 
        .MEMORY_PRIMITIVE("block"), 
        .CLOCKING_MODE("common_clock"), 
        .WRITE_DATA_WIDTH_A(16), 
        .BYTE_WRITE_WIDTH_A(16), 
        .ADDR_WIDTH_A(ADDR_W),
        .READ_DATA_WIDTH_B(16), 
        .ADDR_WIDTH_B(ADDR_W), 
        .READ_LATENCY_B(1), 
        .WRITE_MODE_B("read_first")
    ) bram_inst (
        .sleep(1'b0), 
        .clka(clk), 
        .ena(1'b1), 
        .wea(we), 
        .addra(wr_addr), 
        .dina(din),
        .clkb(clk), 
        .rstb(1'b0), 
        .enb(1'b1), 
        .regceb(1'b1), 
        .addrb(rd_addr), 
        .doutb(dout),
        .injectsbiterra(1'b0), 
        .injectdbiterra(1'b0), 
        .sbiterrb(), 
        .dbiterrb()
    );
`endif

endmodule