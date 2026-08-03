`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 06:52:46 PM
// Design Name: 
// Module Name: ALU
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


module ALU(
input [31:0]a,//input 1
input [31:0]b,//input 2
input [3:0]control,
output reg [31:0]c //result 
    );

    always @(*)
    begin
    case(control)
    0:c=a+b;
    1:c=a-b;
    2:c=a^b;
    3:c=a|b;
    4:c=a&b;
    5:c=a<<b;
    6:c=a>>b;
    7:c=a>>>b;
    8:c=($signed(a)<($signed(b)));
    9:c=(a<b);
    default: c=0;
    endcase
    end
  
endmodule
