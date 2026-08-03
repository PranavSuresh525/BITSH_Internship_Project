`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 06:52:35 PM
// Design Name: 
// Module Name: ALU_CONTROL
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


module ALU_CONTROL(
input [1:0]alu_op,
input [2:0]funct_3,
input  [6:0]funct_7,
output reg [3:0]alu_control
    );
    
    always @(*)
    begin
        case(alu_op)
            2'b00:
            begin
                alu_control=4'b0;
            end
            
            2'b01:
            begin
               alu_control=10;
            end
            
            2'b10:
            begin
                case(funct_3)
                0:
                begin
                     case(funct_7)
                        7'b0000000:alu_control=0;
                        7'b0100000:alu_control=1;
                        default: alu_control=0;
                      endcase
                end 
                4:alu_control=2;
                6:alu_control=3;
                7:alu_control=4;
                1:alu_control=5;
                5:
                begin
                     case(funct_7)
                        7'b0000000:alu_control=6;
                        7'b0100000:alu_control=7;
                        default:alu_control=0;
                     endcase
                end 
                2:alu_control=8;
                3:alu_control=9;
                default:alu_control=10;
                endcase
            end
        
        2'b11:
            begin
            case(funct_3)
            0:alu_control=0;
            4:alu_control=2;
            6:alu_control=3;
            7:alu_control=4;
            1:alu_control=5;
            5:
            begin
                 case(funct_7)
                    7'b0000000:alu_control=6;
                    7'b0100000:alu_control=7;
                    default:alu_control=0;
                 endcase
            end 
            2:alu_control=8;
            3:alu_control=9;
            default:alu_control=0;
            endcase
        end
        endcase
    end
endmodule   
