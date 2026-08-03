// =========================================================================
// COMBINED SW & HWA matmul firmware -- for simultaneous validation.
//
// Runs the scalar RISC-V bf16 matmul, marks completion, and then runs
// the systolic-array-accelerated matmul and marks completion.
// =========================================================================

#define N 2
#define ELEM_BYTES   4
#define MAT_BYTES    (N * N * ELEM_BYTES)

// Unified Memory Map
#define ADDR_A        (0)
#define ADDR_B        (ADDR_A        + MAT_BYTES)
#define ADDR_C_SW     (ADDR_B        + MAT_BYTES)
#define ADDR_C_HWA    (ADDR_C_SW     + MAT_BYTES)
#define ADDR_DONE_SW  (ADDR_C_HWA    + MAT_BYTES)
#define ADDR_DONE_HWA (ADDR_DONE_SW  + ELEM_BYTES)

#define DONE_TOKEN_SW  0xDEADBEEFu
#define DONE_TOKEN_HWA 0xCAFEBBAEu
#define STACK_TOP      0x0003FFF0

// HWA Macros
#define matmul_load_a(addr)  asm volatile(".insn r 0x0b, 0, 0, x0, %0, x0" :: "r"(addr))
#define matmul_compute(addr) asm volatile(".insn r 0x0b, 1, 0, x0, %0, x0" :: "r"(addr))
#define matmul_store_c(addr) asm volatile(".insn r 0x0b, 3, 0, x0, %0, x0" :: "r"(addr))

// SW BF16 Helpers
#define BF16_SIGN(w)     (((w) >> 15) & 0x1u)
#define BF16_EXP(w)      (((w) >> 7)  & 0xFFu)
#define BF16_MANT(w)     ((w) & 0x7Fu)
#define BF16_PACK(s,e,m) ((((s) & 0x1u) << 15) | (((e) & 0xFFu) << 7) | ((m) & 0x7Fu))
#define ADD_GUARD_BITS 8

static unsigned int umul(unsigned int a, unsigned int b) {
    unsigned int result = 0;
    while (b) {
        if (b & 1u) result = result + a;
        a = a << 1;
        b = b >> 1;
    }
    return result;
}

static unsigned int bf16_mul(unsigned int a, unsigned int b) {
    unsigned int sa = BF16_SIGN(a), sb = BF16_SIGN(b);
    unsigned int ea = BF16_EXP(a),  eb = BF16_EXP(b);
    unsigned int ma = BF16_MANT(a), mb = BF16_MANT(b);

    if ((ea == 0 && ma == 0) || (eb == 0 && mb == 0)) return 0;

    unsigned int sr   = sa ^ sb;
    unsigned int siga = 0x80u | ma;
    unsigned int sigb = 0x80u | mb;

    unsigned int prod = umul(siga, sigb);
    int er = (int)ea + (int)eb - 127;

    unsigned int mant;
    if (prod & 0x8000u) {
        mant = (prod >> 8) & 0x7Fu;
        er += 1;
    } else {
        mant = (prod >> 7) & 0x7Fu;
    }

    if (er < 0)   return BF16_PACK(sr, 0, 0);
    if (er > 255) er = 255;
    return BF16_PACK(sr, (unsigned int)er, mant);
}

static unsigned int bf16_add(unsigned int a, unsigned int b) {
    unsigned int sa = BF16_SIGN(a), sb = BF16_SIGN(b);
    unsigned int ea = BF16_EXP(a),  eb = BF16_EXP(b);
    unsigned int ma = BF16_MANT(a), mb = BF16_MANT(b);

    unsigned int za = (ea == 0 && ma == 0);
    unsigned int zb = (eb == 0 && mb == 0);
    if (za) return b;
    if (zb) return a;

    unsigned int siga = (0x80u | ma) << ADD_GUARD_BITS;
    unsigned int sigb = (0x80u | mb) << ADD_GUARD_BITS;

    int ediff = (int)ea - (int)eb;
    unsigned int exp_r;
    if (ediff >= 0) {
        exp_r = ea;
        sigb  = (ediff > 30) ? 0u : (sigb >> ediff);
    } else {
        exp_r = eb;
        int sh = -ediff;
        siga = (sh > 30) ? 0u : (siga >> sh);
    }

    unsigned int mag;
    unsigned int sign_r;
    if (sa == sb) {
        mag    = siga + sigb;
        sign_r = sa;
    } else if (siga >= sigb) {
        mag    = siga - sigb;
        sign_r = sa;
    } else {
        mag    = sigb - siga;
        sign_r = sb;
    }

    if (mag == 0) return 0;

    int shift = 0;
    unsigned int m = mag;
    while (m >= (1u << (8 + ADD_GUARD_BITS))) { m = m >> 1; shift = shift + 1; }
    while (m <  (1u << (7 + ADD_GUARD_BITS))) { m = m << 1; shift = shift - 1; }

    int exp_final = (int)exp_r + shift;
    unsigned int mant = (m >> ADD_GUARD_BITS) & 0x7Fu;

    if (exp_final < 0)   return BF16_PACK(sign_r, 0, 0);
    if (exp_final > 255) exp_final = 255;
    return BF16_PACK(sign_r, (unsigned int)exp_final, mant);
}

void __attribute__((naked)) _start(void) {
    asm volatile("li sp, %0" :: "i"(STACK_TOP));

    // =========================================================================
    // 1. PHASE 1: SCALAR SW MATMUL
    // =========================================================================
    {
        int i, j, k;
        volatile unsigned int *A = (volatile unsigned int *) ADDR_A;
        volatile unsigned int *B = (volatile unsigned int *) ADDR_B;
        volatile unsigned int *C_SW = (volatile unsigned int *) ADDR_C_SW;

        for (i = 0; i < N; i = i + 1) {
            for (j = 0; j < N; j = j + 1) {
                unsigned int acc = 0;
                for (k = 0; k < N; k = k + 1) {
                    unsigned int a = A[i * N + k] & 0xFFFFu;
                    unsigned int b = B[k * N + j] & 0xFFFFu;
                    acc = bf16_add(acc, bf16_mul(a, b));
                }
                C_SW[i * N + j] = acc;
            }
        }
        // Signal SW completion
        *((volatile unsigned int *) ADDR_DONE_SW) = DONE_TOKEN_SW;
    }

    // =========================================================================
    // 2. PHASE 2: HARDWARE ACCELERATOR MATMUL
    // =========================================================================
    matmul_load_a(ADDR_A);
    matmul_compute(ADDR_B);
    matmul_store_c(ADDR_C_HWA);
    
    // Signal HWA completion
    *((volatile unsigned int *) ADDR_DONE_HWA) = DONE_TOKEN_HWA;

    while (1) { asm volatile("nop"); }
}