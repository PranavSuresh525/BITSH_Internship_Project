`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 10:00:05 PM
// Design Name: 
// Module Name: EX_MEM
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


module EX_MEM(
input clk,
input reset,

input [4:0]ex_rd,

input [1:0]ex_mem_control,
input [1:0]ex_wb_control,

input ex_branch,

input [31:0]ex_rs2,
input [31:0]ex_result,
input [31:0]ex_branch_address,

output reg [4:0]mem_rd,

output reg [1:0]mem_mem_control,
output reg [1:0]mem_wb_control,

output reg mem_branch,

output reg [31:0]mem_write_data,
output reg [31:0]mem_result,
output reg [31:0]mem_branch_address
    );
    
    always @(posedge clk)
    begin
    if(reset)
    begin
        mem_rd<=0;
        
        mem_mem_control<=0;
        mem_wb_control<=0;
        
        mem_branch<=0;
        
        mem_write_data<=0;
        mem_result<=0;
        mem_branch_address<=0;
    
    end
    
    else
    begin
        mem_rd<=ex_rd;
        
        mem_mem_control<=ex_mem_control;
        mem_wb_control<=ex_wb_control;
        
        mem_branch<=ex_branch;
        
        mem_write_data<=ex_rs2;
        mem_result<=ex_result;
        mem_branch_address<=ex_branch_address;
    
    end
    end
endmodule
