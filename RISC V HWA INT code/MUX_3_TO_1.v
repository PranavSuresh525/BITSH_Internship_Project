`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 06:53:24 PM
// Design Name: 
// Module Name: MUX_3_TO_1
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


module MUX_3_TO_1(
input [31:0]input_1,
input [31:0]input_2,
input [31:0]input_3,

input [1:0]control,

output reg [31:0]selected_output
    );
    
    always @(*)
    begin
        case(control)
            0:selected_output=input_1;
            1:selected_output=input_2;
            2:selected_output=input_3;
            default:selected_output=0;
        endcase
    end
endmodule
