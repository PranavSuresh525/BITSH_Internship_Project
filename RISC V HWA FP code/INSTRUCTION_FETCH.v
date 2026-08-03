`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 03:19:57 AM
// Design Name: 
// Module Name: INSTRUCTION_FETCH
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


module INSTRUCTION_FETCH(
input clk,
input reset,

input stall,

input branch,
input [31:0]branch_address,

output reg [31:0]pc,
output [31:0]instruction
    );
    
    
 
    wire [31:0]next_pc;
    wire jump;
    wire [31:0]jump_address;
   
   
   //pc register
    
    always @(posedge clk)
    begin
    if(reset) pc<=0;
    else
    begin
    
    if(!stall) pc<=next_pc;
    end
    end
    
    
    //pc mux
    PC_MUX m1(pc,branch_address,jump_address,branch,jump,next_pc);
    
    
    //jump detection module
    jump_detector_and_jump_address j1(pc,instruction,jump,jump_address);
    //instruction memory
    INSTRUCTION_MEMORY i_mem(clk,reset,pc,instruction);
endmodule
