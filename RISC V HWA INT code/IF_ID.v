`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 03:46:20 AM
// Design Name: 
// Module Name: IF_ID
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


module IF_ID(
input clk,
input reset,

input [31:0]if_pc,
input [31:0]if_instruction,

input stall,
input branch,

output reg [31:0]id_pc,
output reg [31:0]id_instruction
    );
    
    always @(posedge clk)
    begin
        if(reset)
        begin
            id_pc<=0;
            id_instruction<=0;
        end
        else
        begin
            if(!stall)
            begin
                if(branch)
                begin
                    id_pc<=0;
                    id_instruction<=0;
                end
                else if(!branch)
                begin
                    id_pc<=if_pc;
                    id_instruction<=if_instruction;
                end
            end
        end
    end
endmodule
