`timescale 1ns /1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/12/2024 04:38:48 AM
// Design Name: 
// Module Name: RISC_V_PROCESSOR
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


module RISC_V_PROCESSOR #(
    parameter ARCH_TYPE      = "WS",   // "DIP" or "WS"
    parameter N              = 16,      // systolic array dimension (2, 4, 8, 16, 32, 64, ...)
    parameter DATA_MEM_WORDS = 8192        // 0 = auto-size to fit A+B+C matrices (3*N*N), floor 4096
)(
    input clk,
    input reset,
    
    output reg unrecognized,
    //output ex_result,
    output [31:0] wb_data,

    output [31:0] pc_out,
    input  [31:0] instruction_in
    );

    // Auto-size data memory so 3 full NxN matrices (A, B, C) always fit,
    // unless the caller explicitly overrides DATA_MEM_WORDS.
    localparam ACTUAL_DATA_MEM_WORDS =
        (DATA_MEM_WORDS != 0) ? DATA_MEM_WORDS :
        (3*N*N > 4096)        ? 3*N*N          : 4096;
    
    //IF STAGE SIGNALS
    wire [31:0] if_pc,if_instruction;

    assign pc_out = if_pc;
    //assign if_instruction = instruction_in;
    
    //DECODE SIGNALS
    wire [31:0]id_pc,id_instruction;
    
    wire [6:0]id_ex_control;
    wire [1:0]id_mem_control,id_wb_control ;
    
    wire [31:0]id_rs1,id_rs2,id_imm;
    
    
    //STALLING CONTROL STAGE
    
    wire stall;
    
    
    //EXECUTE STAGE SIGNALS;
    
    wire [2:0]ex_funct_3;
    wire [6:0]ex_funct_7;
    
    wire [31:0]ex_pc,ex_rs1,ex_rs2,ex_imm;
    wire [4:0]ex_rd;
    wire [6:0]ex_ex_control;
    wire [1:0]ex_mem_control;
    wire [1:0]ex_wb_control;
    wire [4:0]ex_Rs1;
    wire [4:0]ex_Rs2;
    wire [6:0]ex_opcode;
    
    wire [31:0]ex_result,ex_branch_address;
    wire ex_branch;
    
    //forwarding signals
    wire [1:0]forward_m1;
    wire [1:0]forward_m2;
    
    wire [31:0]ex_input1;
    wire [31:0]ex_input2;
    
    //MEMORY STAGE SIGNALS
    
    wire [4:0]mem_rd;
    wire [31:0]mem_branch_address;
    wire [1:0]mem_mem_control,mem_wb_control;
    wire [31:0]mem_result,mem_write_data;
    wire mem_branch;
    wire [31:0]mem_read_data;
    
   // HWA declarations
    wire [31:0] hwa_address;
    wire [31:0] hwa_write_data;
    wire        hwa_mem_write;
    wire        hwa_mem_read;
    wire        hwa_stall_request;
    wire        hwa_load_done;  // intentionally unused - load_done is status-only
    wire        hwa_active_out;
    wire        hwa_active;        // driven by assign below, only declared ONCE
    
    //WRITE BACK SIGNALS
    
    wire [4:0]wb_rd;
    wire [1:0]wb_control;
    wire [31:0]wb_result;
    wire [31:0]wb_read_data;

    // Bubble-insertion signals (control fields zeroed by stalling_mux while stall=1)
    wire [6:0]id_ex_control_bub;
    wire [1:0]id_mem_control_bub;
    wire [1:0]id_wb_control_bub;
    /////////////////////////////////////////////////////////////////////////////////////////////
    //IF STAGE
    INSTRUCTION_FETCH if_s(
    clk,reset,
    stall,
    ex_branch,ex_branch_address,
    if_pc,if_instruction
    );
  
    //IF ID PIPELINING REGISTERS
   
    IF_ID p1(
    clk,reset,
    if_pc,if_instruction,
    stall,
    ex_branch,
    id_pc,id_instruction
    );
    
    //STALLING STAGE
    wire [4:0]id_s1=id_instruction[19:15];
    wire [4:0]id_s2=id_instruction[24:20];
    wire [6:0]id_opcode=id_instruction[6:0];
    
    STALLING_UNIT stalling_unit(
    id_opcode,
    ex_rd,
    ex_mem_control[1],
    id_s1,
    id_s2,
    hwa_stall_request,
    stall
    );
    
    //DECODE STAGE
     wire id_unrecognized;
     reg  ex_unrecognized,mem_unrecognized;
    
    DECODE dc_s(
    clk,reset,
    id_instruction,
    wb_control[0],wb_rd,wb_data,
    stall,
    id_ex_control,id_mem_control,id_wb_control,
    id_rs1,id_rs2,id_imm,id_unrecognized
    );

    // Insert a bubble (zeroed control) into ID_EX whenever the pipeline stalls
    // (load-use hazard or HWA busy), instead of the real decoded control.
    stalling_mux smux(
    id_ex_control,id_mem_control,id_wb_control,
    stall,
    id_ex_control_bub,id_mem_control_bub,id_wb_control_bub
    );
   
  
    always @(posedge clk)
    begin
    ex_unrecognized<=id_unrecognized;
    mem_unrecognized<=ex_unrecognized;
    unrecognized<=mem_unrecognized;
    end
    
    // ID EX PIPELINING REGISTERS
    ID_EX p2(
    clk,reset,
    1'b0,        // always latch normally; bubble comes from stalling_mux above
    ex_branch,   // flush on the cycle the branch actually resolves in EX
    id_instruction[11:7],id_pc,id_rs1,id_rs2,id_imm,
    id_instruction[14:12],id_instruction[31:25],
    id_ex_control_bub,id_mem_control_bub,id_wb_control_bub,
    id_s1,id_s2,id_instruction[6:0],
    ex_rd,ex_pc,ex_rs1,ex_rs2,ex_imm,
    ex_funct_3,ex_funct_7,
    ex_ex_control,ex_mem_control,ex_wb_control,
    ex_Rs1,ex_Rs2,ex_opcode
    );
    
    //EXECUTE STAGE
    
   //FORWARDING UNIT
    
    FORWARDING_UNIT forwarding_unit(
    mem_wb_control[0],wb_control[0],
    mem_rd,wb_rd,
    ex_Rs1,ex_Rs2,
    ex_opcode,
    
    forward_m1,forward_m2
    
    );
    
   //FORWARDING MUXES 
    FORWARDING_MUXES m1(ex_rs1,mem_result,wb_data,forward_m1,ex_input1);
    FORWARDING_MUXES m2(ex_rs2,mem_result,wb_data,forward_m2,ex_input2);
    
   //EXECUTION UNIT
   
    EXECUTE_STAGE ex_s(
    ex_pc,
    ex_input1,ex_input2,
    ex_imm,
    ex_ex_control,
    ex_funct_3,ex_funct_7,
    ex_result,
    ex_branch_address,
    ex_branch
    );
    
    EX_MEM p3(
    clk,reset,
    ex_rd,
    ex_mem_control,ex_wb_control,
    ex_branch,
    ex_input2,
    ex_result,
    ex_branch_address,
    mem_rd,
    mem_mem_control,mem_wb_control,
    mem_branch,
    mem_write_data,
    mem_result,
    mem_branch_address
    );
    
    
    /**MEM_STAGE mr_s(
    clk,reset,
    mem_result,
    mem_mem_control,
    mem_write_data,
    mem_read_data
    );**/
    // NOTE: DATA_MEMORY's read port is synchronous (1-cycle registered
    // output) -- confirmed by the HWA's own "mem_valid" handshake comment
    // ("Wait 1 cycle for the RISC-V memory to output Data"). The CPU side
    // must therefore present its address/data/control ONE CYCLE EARLY (from
    // EX, where forwarding is already fully resolved) rather than from the
    // registered EX_MEM/MEM-stage signals. Otherwise DATA_MEMORY's output
    // becomes valid the same cycle MEM_WB samples it, which is one cycle too
    // late relative to mem_rd/mem_wb_control -- every load's data then lands
    // in the NEXT instruction's destination register instead of its own.
    DATA_MEMORY #(
        .MEMORY_SIZE(ACTUAL_DATA_MEM_WORDS)
    ) data_memory(
        .clk(clk),
        .hwa_active(hwa_active),
        .cpu_address(ex_result),
        .cpu_write_data(ex_input2),
        .cpu_mem_write(ex_mem_control[0]),
        .cpu_mem_read(ex_mem_control[1]),
        .hwa_address(hwa_address),
        .hwa_write_data(hwa_write_data),
        .hwa_mem_write(hwa_mem_write),
        .hwa_mem_read(hwa_mem_read),
        .read_data(mem_read_data)                                       
    );

    wire hwa_trigger  = (ex_opcode == 7'b0001011);
    assign hwa_active = hwa_active_out | hwa_trigger;

    matrix_multiply_hardware #(.ARCH_TYPE(ARCH_TYPE), .N(N)) hwa_inst (
        .clk(clk),
        .reset(reset),
        .configure_data(ex_input1), 
        .hwa(hwa_trigger),
        .data(mem_read_data),
        .funct3(ex_funct_3),
        .next_address(hwa_address),        
        .output_data(hwa_write_data),      
        .load_done(hwa_load_done),
        .stall_request(hwa_stall_request),
        .hwa_mem_write(hwa_mem_write),
        .hwa_mem_read(hwa_mem_read),
        .hwa_active_out(hwa_active_out)
    );

    MEM_WB P4(
    clk,reset,
    mem_rd,
    mem_wb_control,
    mem_result,mem_read_data,
    wb_rd,
    wb_control,
    wb_result,wb_read_data
    );
    
    
    //WRITE BACK STAGE
    
    assign wb_data=wb_control[1]?wb_read_data:wb_result;

endmodule