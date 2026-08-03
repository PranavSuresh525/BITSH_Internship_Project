`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 03:56:33 AM
// Design Name: 
// Module Name: DECODE
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


module DECODE(
input clk,
input reset,

input [31:0]instruction,

input wb_reg_write,
input [4:0]wb_rd,
input [31:0]wb_data,

input stall,

//input from forwarding_unit




output [6:0]ex_control,
output [1:0]mem_control,
output [1:0]wb_control,

output [31:0]rs1,
output [31:0]rs2,
output [31:0]immediate,

output unrecognized
    );
    
    wire [6:0]ex_control_temp;
    wire [1:0]mem_control_temp;
    wire [1:0]wb_control_temp;

    wire [4:0]s1=instruction[19:15];
    wire [4:0]s2=instruction[24:20];
    
    REGFILE r1(clk,reset,s1,s2,wb_reg_write,wb_rd,wb_data,rs1,rs2);
    
    CONTROL_UNIT c1(instruction[6:0],ex_control_temp,mem_control_temp,wb_control_temp,unrecognized);
    
    stalling_mux st_unit(ex_control_temp,mem_control_temp,wb_control_temp,stall,ex_control,mem_control,wb_control);
    
    SIGN_EXTEND se_unit(instruction,immediate);
    
endmodule
