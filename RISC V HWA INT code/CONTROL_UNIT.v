`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 04:11:56 AM
// Design Name: 
// Module Name: CONTROL_UNIT
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


module CONTROL_UNIT(
input [6:0]opcode,

output reg [6:0]ex_control,//{pc_or_reg_or_0_select[2bits],imm_or_4_sel[2 bits],alu_op[2 bits],branch}
output reg [1:0]mem_control,//{mem_read,mem_write}
output reg [1:0]wb_control, //{mem_data_select,reg_write}
output reg unrecognized
    );
    
    //alu input 1
    parameter pc=     2'b00;
    parameter zero=   2'b01;
    parameter reg_s1= 2'b10;
   
    //alu input 2
    parameter reg_s2= 2'b00;
    parameter imm=    2'b01;
    parameter four=   2'b10;
    
    //alu op
    parameter ld_str= 2'b00;
    parameter brch=   2'b01; 
    parameter arith=  2'b10;
    parameter im_op = 2'b11;
    always@(*)
    begin
        case(opcode)
         7'b0110011://R type
         begin
         ex_control=   {reg_s1,reg_s2,arith,1'b0};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b1};
         unrecognized=1'b0;
         end
         
         7'b0010011://I type
         begin
         ex_control=   {reg_s1,imm,im_op,1'b0};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b1};
         unrecognized=1'b0;
         end
         
         7'b0000011://I type - Load
         begin
         ex_control=   {reg_s1,imm,ld_str,1'b0};
         mem_control=  {1'b1,1'b0};
         wb_control=   {1'b1,1'b1};  
         unrecognized=0;  
         end
         
         7'b0100011://S type
         begin
         ex_control=   {reg_s1,imm,ld_str,1'b0};
         mem_control=  {1'b0,1'b1};
         wb_control=   {1'b0,1'b0}; 
         unrecognized=0;  
         end
         
         7'b1100011://Branch type
         begin
         ex_control=   {reg_s1,reg_s2,brch,1'b1};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b0};    
         unrecognized=0;
         end
         
         7'b1101111://Jump and link
         begin
         ex_control=   {pc,four,ld_str,1'b0};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b1};   
         unrecognized=0;
         end
         
         7'b0110111://lui
         begin
         ex_control=   {zero,imm,ld_str,1'b0};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b1};      
         unrecognized=0;    
         end
         
         7'b0010111://AUIPC
         begin
         ex_control=   {pc,imm,ld_str,1'b0};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b1};   
         unrecognized=0;
         end

         7'b0001011:// Custom HWA Configure Instruction
         begin
         ex_control=   {reg_s1,reg_s2,ld_str,1'b0};
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b1};   
         unrecognized=1'b0;
         end
         
         default:
         begin
         ex_control= 0;
         mem_control=  {1'b0,1'b0};
         wb_control=   {1'b0,1'b0}; 
         unrecognized=1'b1;   
         end   
        endcase
    end
    
endmodule

