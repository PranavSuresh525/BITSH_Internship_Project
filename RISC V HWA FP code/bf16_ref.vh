//////////////////////////////////////////////////////////////////////////////
// bf16_ref.vh : simulation-only helper functions (real <-> bf16) used by
// testbenches to build golden/reference models. NOT synthesizable, NOT part
// of the accelerator RTL.
//////////////////////////////////////////////////////////////////////////////

function real bf16_to_real;
    input [15:0] x;
    real frac;
    integer e;
    begin
        if (x[14:7] == 8'd0) begin
            bf16_to_real = 0.0; // flush-to-zero (matches RTL simplification)
        end else begin
            frac = 1.0;
            frac = frac + (x[0]  ? 1.0/128.0  : 0.0);
            frac = frac + (x[1]  ? 1.0/64.0   : 0.0);
            frac = frac + (x[2]  ? 1.0/32.0   : 0.0);
            frac = frac + (x[3]  ? 1.0/16.0   : 0.0);
            frac = frac + (x[4]  ? 1.0/8.0    : 0.0);
            frac = frac + (x[5]  ? 1.0/4.0    : 0.0);
            frac = frac + (x[6]  ? 1.0/2.0    : 0.0);
            e = x[14:7] - 127;
            bf16_to_real = frac * (2.0 ** e);
            if (x[15]) bf16_to_real = -bf16_to_real;
        end
    end
endfunction

function [15:0] real_to_bf16;
    input real v;
    real av, m;
    integer e;
    reg sgn;
    reg [7:0] mant_full; // wide enough to catch rounding overflow to 128
    reg [6:0] mant;
    reg [7:0] expo;
    begin
        if (v == 0.0) begin
            real_to_bf16 = 16'd0;
        end else begin
            sgn = (v < 0.0);
            av  = (v < 0.0) ? -v : v;
            e   = 0;
            // normalize av into [1,2)
            while (av >= 2.0) begin
                av = av / 2.0;
                e  = e + 1;
            end
            while (av < 1.0) begin
                av = av * 2.0;
                e  = e - 1;
            end
            m = (av - 1.0) * 128.0;
            mant_full = $rtoi(m + 0.5); // round to nearest, full 8-bit width
            if (mant_full == 8'd128) begin // mantissa rounded up to 2.0 -> renormalize
                mant = 7'd0;
                e = e + 1;
            end else begin
                mant = mant_full[6:0];
            end
            expo = e + 127;
            real_to_bf16 = {sgn, expo, mant[6:0]};
        end
    end
endfunction
