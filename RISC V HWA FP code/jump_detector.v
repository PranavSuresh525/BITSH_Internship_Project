`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 03:32:42 AM
// Design Name: 
// Module Name: jump_detector_and_jump_address
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


module jump_detector_and_jump_address(
input [31:0]pc,
input [31:0]instruction,
output jump,
output [31:0] jump_address
    );
    
    wire [31:0]immediate;
    
    assign jump=            (instruction[6:0]==7'b1101111);
    assign immediate=       {{12{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
    assign jump_address=    pc+immediate;
endmodule
