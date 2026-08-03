`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2024 04:17:51 AM
// Design Name: 
// Module Name: FORWARDING_MUXES
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


module FORWARDING_MUXES(
input [31:0]a,
input [31:0]b,
input [31:0]c,
input [1:0]control,

output reg [31:0]result
    );
    always @(*)
    begin
    case(control)
    0:result=a;
    1:result=b;
    2:result=c;
    default:result=a;
    endcase
    end
endmodule
