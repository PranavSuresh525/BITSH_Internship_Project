`timescale 1ns / 1ps
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
    parameter N = 12,
    parameter ARCH_TYPE = "DIP"
)(
    input clk,
    input reset,
    
    output reg unrecognized,
    //output ex_result,
    output [31:0] wb_data,
    output wb_valid,

    output [31:0] pc_out,
    input  [31:0] instruction_in
    );
    
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
    
    wire raw_stall;
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

    // =========================================================================
    // FP 2-CYCLE STALL LOGIC
    // =========================================================================
    wire ex_is_fp_arith = (ex_opcode == 7'b1010011);
    reg [1:0] fp_stall_count;

    always @(posedge clk) begin
        if (reset) begin
            fp_stall_count <= 2'd0;
        end else if (ex_is_fp_arith) begin
            if (fp_stall_count == 2'd2)
                fp_stall_count <= 2'd0; // Release pipeline on 3rd cycle
            else
                fp_stall_count <= fp_stall_count + 1'b1; // Hold stall
        end else begin
            fp_stall_count <= 2'd0;
        end
    end

    // Assert stall while FP op is in EX and counter hasn't reached 2
    wire fp_stall_req = (ex_is_fp_arith && (fp_stall_count != 2'd2));
    
    wire hwa_stall_req_out; // We will grab this from hwa_inst now
    wire combined_stall_request = hwa_stall_req_out | fp_stall_req;

    STALLING_UNIT stalling_unit(
        id_opcode,
        ex_rd,
        ex_mem_control[1],
        id_s1,
        id_s2,
        combined_stall_request, // Feed the merged stall request here
        raw_stall
    );

    // =========================================================================
    // MEM-STAGE LOAD LATENCY HOLD
    // DATA_MEMORY's read is registered (1-cycle latency): cpu_mem_read/
    // cpu_address sampled during cycle T produce valid read_data only from
    // cycle T+1 onward. The base pipeline assumed a combinational (0-latency)
    // memory, so MEM_WB was capturing read_data one cycle too early for every
    // load. This holds EX_MEM and MEM_WB (and freezes everything upstream via
    // `stall`) for exactly one extra cycle whenever a load is in the MEM
    // stage, so DATA_MEMORY has time to produce the correct value first.
    // =========================================================================
    reg mem_load_wait_given;
    always @(posedge clk) begin
        if (reset)
            mem_load_wait_given <= 1'b0;
        else if (mem_mem_control[1] && !mem_load_wait_given)
            mem_load_wait_given <= 1'b1;
        else
            mem_load_wait_given <= 1'b0;
    end
    wire hold_mem = mem_mem_control[1] && !mem_load_wait_given;

    assign stall = raw_stall | hold_mem;
    
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
   
  
    always @(posedge clk)
    begin
    ex_unrecognized<=id_unrecognized;
    mem_unrecognized<=ex_unrecognized;
    unrecognized<=mem_unrecognized;
    end
    
    // ID EX PIPELINING REGISTERS
    ID_EX p2(
    clk,reset,
    stall,
    ex_branch,
    id_instruction[11:7],id_pc,id_rs1,id_rs2,id_imm,
    id_instruction[14:12],id_instruction[31:25],
    id_ex_control,id_mem_control,id_wb_control,
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
    ex_opcode,           // NEW: needed by ALU_CONTROL to detect OP-FP
    ex_result,
    ex_branch_address,
    ex_branch
    );
    
    EX_MEM p3(
    clk,reset,
    hold_mem,
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
    DATA_MEMORY data_memory(
        .clk(clk),
        .hwa_active(hwa_active),
        .cpu_address(mem_result),
        .cpu_write_data(mem_write_data),
        .cpu_mem_write(mem_mem_control[0]),
        .cpu_mem_read(mem_mem_control[1]),
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
        .stall_request(hwa_stall_req_out), 
        .hwa_mem_write(hwa_mem_write),
        .hwa_mem_read(hwa_mem_read),
        .hwa_active_out(hwa_active_out)
    );

    MEM_WB P4(
    clk,reset,
    hold_mem,
    mem_rd,
    mem_wb_control,
    mem_result,mem_read_data,
    wb_rd,
    wb_control,
    wb_result,wb_read_data
    );
    
    
    // =========================================================================
    // WRITE BACK & AXI-STREAM STAGE
    // =========================================================================
    
    // 1. Normal CPU write-back data
    wire [31:0] cpu_wb_data = wb_control[1] ? wb_read_data : wb_result;
    assign wb_data = hwa_mem_write ? hwa_write_data : cpu_wb_data;
    assign wb_valid = hwa_mem_write;

endmodule