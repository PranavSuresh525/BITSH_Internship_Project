`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 06:18:06 PM
// Design Name: 
// Module Name: stalling_mux
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


module stalling_mux(
input [6:0]ex_control_temp,
input [1:0]mem_control_temp,
input [1:0]wb_control_temp,

input stall,

output [6:0]ex_control,
output [1:0]mem_control,
output [1:0]wb_control
    );
    
    assign ex_control=  stall?0:ex_control_temp;
    assign mem_control= stall?0:mem_control_temp;
    assign wb_control=  stall?0:wb_control_temp;

endmodule
