`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 04:04:51 AM
// Design Name: 
// Module Name: REGFILE
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module REGFILE(
    input clk,
    input reset,

    input [4:0] s1,
    input [4:0] s2,

    input reg_write,
    input [4:0] rd,
    input [31:0] wb_data,

    output [31:0] RS1,
    output [31:0] RS2
);
    
    // 1. Declare 32 registers (indices 0 to 31)
    (* ram_style = "distributed" *) reg [31:0] GPP [0:31];  
    
    // 2. RISC-V Specification: Register 0 is always hardwired to 0
    assign RS1 = (s1 == 5'b0) ? 32'b0 : GPP[s1];
    assign RS2 = (s2 == 5'b0) ? 32'b0 : GPP[s2];
    
    // 3. Clean synchronous write block without the illegal reset loop
    always @(negedge clk) begin
        if (reg_write && (rd != 5'b0)) begin
            GPP[rd] <= wb_data; // Force non-blocking assignment
        end
    end
    
endmodule
