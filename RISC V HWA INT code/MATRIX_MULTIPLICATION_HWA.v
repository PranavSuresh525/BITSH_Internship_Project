`timescale 1ns / 1ps

module matrix_multiply_hardware #(
    parameter ARCH_TYPE = "DIP",   
    parameter N = 16
)(
    input         clk,
    input         reset,

    input  [31:0] configure_data,
    input         hwa,
    input  [31:0] data,
    input  [2:0]  funct3,

    output [31:0] next_address,
    output [31:0] output_data,
    output        load_done,
    output        stall_request,
    output        hwa_mem_write,
    output        hwa_mem_read,
    output        hwa_active_out
);

    localparam EL    = N*N;                 
    localparam IDX_W = $clog2(EL);

    localparam CMD_LOAD_A      = 3'b000;
    localparam CMD_LOAD_B_COMP = 3'b001;
    localparam CMD_OUTPUT_C    = 3'b011;

    // ST_COMPUTE_GO restored to prevent BRAM Read-After-Write hazards
    localparam ST_IDLE         = 3'd0;
    localparam ST_LOAD_A       = 3'd1; 
    localparam ST_LOAD_B       = 3'd2;
    localparam ST_COMPUTE_GO   = 3'd3;
    localparam ST_COMPUTE_WAIT = 3'd4;
    localparam ST_STORE_C      = 3'd5;

    reg [2:0] state;
    
    reg [IDX_W:0] req_idx; 
    reg [IDX_W:0] cap_idx; 
    
    reg [31:0] base_reg;          
    reg        hwa_prev;
    wire       hwa_rise = hwa & ~hwa_prev;

    reg        load_done_r;
    reg        weight_wr_en_r, input_wr_en_r;
    reg [15:0] weight_wr_data_r, input_wr_data_r;
    reg [IDX_W-1:0] weight_wr_addr_r, input_wr_addr_r;
    reg        array_start_r;

    wire array_busy, array_done;
    wire [15:0] array_output_rd_data;

    generate 
        if(ARCH_TYPE=="DIP") begin: gen_dip
            dip_top #(.N(N)) u_dip (
                .clk(clk), .rst(reset),
                .weight_wr_en(weight_wr_en_r), .weight_wr_addr(weight_wr_addr_r), .weight_wr_data(weight_wr_data_r),
                .input_wr_en(input_wr_en_r),   .input_wr_addr(input_wr_addr_r),   .input_wr_data(input_wr_data_r),
                .start(array_start_r), .busy(array_busy), .done(array_done),
                .output_rd_addr(req_idx[IDX_W-1:0]), .output_rd_data(array_output_rd_data)
            );
        end else begin: gen_ws
            ws_top #(.N(N)) u_dip (
                .clk(clk), .rst(reset),
                .weight_wr_en(weight_wr_en_r), .weight_wr_addr(weight_wr_addr_r), .weight_wr_data(weight_wr_data_r),
                .input_wr_en(input_wr_en_r),   .input_wr_addr(input_wr_addr_r),   .input_wr_data(input_wr_data_r),
                .start(array_start_r), .busy(array_busy), .done(array_done),
                .output_rd_addr(req_idx[IDX_W-1:0]), .output_rd_data(array_output_rd_data)
            );
        end
    endgenerate

    wire [31:0] req_byte_off = {req_idx[IDX_W-1:0], 2'b00}; 
    wire [31:0] cap_byte_off = {cap_idx[IDX_W-1:0], 2'b00};

    // PREFETCH: issue element-0's read during the ST_IDLE cycle where hwa_rise
    // fires, instead of waiting for state to register into ST_LOAD_A/ST_LOAD_B
    // first. hwa_active already goes high combinationally off hwa_trigger the
    // same cycle (see RISC_V_PROCESSOR.v: hwa_active = hwa_active_out |
    // hwa_trigger), so the memory arbiter is already routing the bus to this
    // module that cycle -- the old code just wasn't using it. This removes the
    // 1-cycle "wait for req_idx>0" warm-up bubble at the start of each phase,
    // the same trick dip_fsm.v / ws_fsm.v already use for their weight loads.
    wire load_issue = (state == ST_IDLE) && hwa_rise &&
                       ((funct3 == CMD_LOAD_A) || (funct3 == CMD_LOAD_B_COMP));

    assign next_address  = load_issue ? configure_data :
                           ((state == ST_LOAD_A) || (state == ST_LOAD_B)) ? (base_reg + req_byte_off) :
                           (state == ST_STORE_C) ? (base_reg + cap_byte_off) : 32'd0;

    assign hwa_mem_read  = load_issue ||
                           (((state == ST_LOAD_A) || (state == ST_LOAD_B)) && (req_idx < EL));
    
    // STORE_C's internal output-BRAM read (req_idx -> output_rd_addr, wired at
    // the array instantiation above) has been sitting at req_idx==0 throughout
    // ST_IDLE ever since the previous phase reset it, so array_output_rd_data
    // for element 0 is already settled by the time we enter ST_STORE_C --
    // no req_idx>0 warm-up needed, write can start on the very first cycle.
    assign hwa_mem_write = (state == ST_STORE_C);
    assign output_data   = (state == ST_STORE_C) ? {16'd0, array_output_rd_data} : 32'd0;
    
    assign load_done     = load_done_r;
    assign stall_request = hwa_rise || (state != ST_IDLE);
    assign hwa_active_out = (state != ST_IDLE);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= ST_IDLE;
            req_idx          <= 0;
            cap_idx          <= 0;
            base_reg         <= 32'd0;
            hwa_prev         <= 1'b0;
            load_done_r      <= 1'b0;
            weight_wr_en_r   <= 1'b0;
            input_wr_en_r    <= 1'b0;
            array_start_r    <= 1'b0;
        end else begin
            hwa_prev        <= hwa;
            load_done_r     <= 1'b0;
            weight_wr_en_r  <= 1'b0;
            input_wr_en_r   <= 1'b0;
            array_start_r   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (hwa_rise) begin
                        cap_idx <= 0;
                        case (funct3)
                            // req_idx <= 1: element 0 was already requested
                            // this cycle via `load_issue`, so on entry to
                            // ST_LOAD_A/B the FSM is already one element ahead.
                            CMD_LOAD_A:      begin base_reg <= configure_data; req_idx <= 1; state <= ST_LOAD_A;  end
                            CMD_LOAD_B_COMP: begin base_reg <= configure_data; req_idx <= 1; state <= ST_LOAD_B;  end
                            // req_idx <= 1 for the same reason as the loads:
                            // req_idx has to stay one step AHEAD of cap_idx so
                            // the registered output-BRAM read (1-cycle latency)
                            // is always ready by the time cap_idx needs it.
                            // Address 0 itself was already pre-settled while
                            // idle (req_idx sat at 0 since the prior phase), so
                            // this only needs to kick off the request for
                            // address 1.
                            CMD_OUTPUT_C:    begin base_reg <= configure_data; req_idx <= 1; state <= ST_STORE_C; end
                            default: ; 
                        endcase
                    end
                end

                ST_LOAD_A: begin
                    if (req_idx < EL) req_idx <= req_idx + 1;

                    // Data for `cap_idx` was requested last cycle (either the
                    // ST_IDLE prefetch, or this same state the cycle before),
                    // so it's valid every cycle here -- no more warm-up wait.
                    input_wr_addr_r <= cap_idx[IDX_W-1:0];
                    input_wr_data_r <= data[15:0];
                    input_wr_en_r   <= 1'b1;

                    if (cap_idx == EL-1) begin
                        state       <= ST_IDLE;       
                        load_done_r <= 1'b1;          
                        req_idx     <= 0;
                        cap_idx     <= 0;
                    end else begin
                        cap_idx <= cap_idx + 1;
                    end
                end

                ST_LOAD_B: begin
                    if (req_idx < EL) req_idx <= req_idx + 1;

                    weight_wr_addr_r <= cap_idx[IDX_W-1:0];
                    weight_wr_data_r <= data[15:0];
                    weight_wr_en_r   <= 1'b1;

                    if (cap_idx == EL-1) begin
                        state   <= ST_COMPUTE_GO; // 1-cycle wait to safely latch BRAM data
                        req_idx <= 0;
                        cap_idx <= 0;
                    end else begin
                        cap_idx <= cap_idx + 1;
                    end
                end

                ST_COMPUTE_GO: begin
                    array_start_r <= 1'b1;
                    state         <= ST_COMPUTE_WAIT;
                end

                ST_COMPUTE_WAIT: begin
                    if (array_done) begin
                        state       <= ST_IDLE;       
                        load_done_r <= 1'b1;
                        req_idx     <= 0;
                        cap_idx     <= 0;
                    end
                end

                ST_STORE_C: begin
                    if (req_idx < EL) req_idx <= req_idx + 1;

                    if (cap_idx == EL-1) begin
                        state       <= ST_IDLE;       
                        load_done_r <= 1'b1;
                        req_idx     <= 0;
                        cap_idx     <= 0;
                    end else begin
                        cap_idx <= cap_idx + 1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule