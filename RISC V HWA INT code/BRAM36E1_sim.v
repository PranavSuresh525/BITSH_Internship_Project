`timescale 1ns/1ps

// Behavioral stub for Xilinx BRAM36E1 primitive
// Only implements SDP mode (Simple Dual Port) which is what we use
module BRAM36E1 #(
    parameter READ_WIDTH_A       = 36,
    parameter WRITE_WIDTH_A      = 36,
    parameter READ_WIDTH_B       = 36,
    parameter WRITE_WIDTH_B      = 36,
    parameter RAM_MODE           = "SDP",
    parameter DOA_REG            = 0,
    parameter DOB_REG            = 0,
    parameter WRITE_MODE_A       = "WRITE_FIRST",
    parameter WRITE_MODE_B       = "WRITE_FIRST",
    parameter SIM_COLLISION_CHECK = "NONE"
)(
    // Port A — Read port (SDP mode)
    input  wire        CLKARDCLK,
    input  wire        ENARDEN,
    input  wire [14:0] ADDRARDADDR,
    output reg  [31:0] DOADO,
    output wire [3:0]  DOPADOP,

    // Port B — Write port (SDP mode)
    input  wire        CLKBWRCLK,
    input  wire        ENBWREN,
    input  wire [14:0] ADDRBWRADDR,
    input  wire [31:0] DIADI,
    input  wire [3:0]  DIPADIP,
    input  wire [7:0]  WEBWE,
    input  wire [3:0]  WEA,

    // Unused in SDP mode
    input  wire [31:0] DIBDI,
    input  wire [3:0]  DIPBDIP,
    output wire [31:0] DOBDO,
    output wire [3:0]  DOPBDOP,

    // Reset/register control (tied off in our usage)
    input  wire        RSTRAMARSTRAM,
    input  wire        RSTRAMB,
    input  wire        RSTREGARSTREG,
    input  wire        RSTREGB,
    input  wire        REGCEAREGCE,
    input  wire        REGCEB
);

    // 32-deep × 32-bit memory (matches our N=32 bank)
    reg [31:0] mem [0:31];

    // Extract actual address from padded 15-bit address
    // In x36 SDP mode, address bits [14:10] are used for 32-deep memory
    wire [4:0] rd_addr = ADDRARDADDR[14:10];
    wire [4:0] wr_addr = ADDRBWRADDR[14:10];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            mem[i] = 32'h0;
    end

    // Synchronous write (Port B)
    always @(posedge CLKBWRCLK) begin
        if (ENBWREN) begin
            if (WEBWE[0]) mem[wr_addr][ 7: 0] <= DIADI[ 7: 0];
            if (WEBWE[1]) mem[wr_addr][15: 8] <= DIADI[15: 8];
            if (WEBWE[2]) mem[wr_addr][23:16] <= DIADI[23:16];
            if (WEBWE[3]) mem[wr_addr][31:24] <= DIADI[31:24];
        end
    end

    // Synchronous read (Port A)
    always @(posedge CLKARDCLK) begin
        if (ENARDEN)
            DOADO <= mem[rd_addr];
    end

    // Tie off unused outputs
    assign DOPADOP = 4'b0;
    assign DOBDO   = 32'b0;
    assign DOPBDOP = 4'b0;

endmodule