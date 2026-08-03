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

static unsigned int umul(unsigned int a, unsigned int b) {
    unsigned int result = 0;
    while (b) {
        if (b & 1u) result = result + a;
        a = a << 1;
        b = b >> 1;
    }
    return result;
}
// Software multiplication for strict RV32I targets
static int soft_mul(int a, int b) {
    int result = 0;
    // Cast to unsigned for logical right shift
    unsigned int ub = (unsigned int)b; 
    while (ub != 0) {
        if (ub & 1u) result = result + a;
        a = a << 1;
        ub = ub >> 1;
    }
    return result;
}
void __attribute__((naked)) _start(void) {
    asm volatile("li sp, %0" :: "i"(STACK_TOP));

    // =========================================================================
    // 1. PHASE 1: SCALAR SW MATMUL (Standard Integer)
    // =========================================================================
    {
        int i, j, k;
        volatile int *A = (volatile int *) ADDR_A;
        volatile int *B = (volatile int *) ADDR_B;
        volatile int *C_SW = (volatile int *) ADDR_C_SW;

        for (i = 0; i < N; i = i + 1) {
            for (j = 0; j < N; j = j + 1) {
                int acc = 0;
                for (k = 0; k < N; k = k + 1) {
                    int a = A[i * N + k];
                    int b = B[k * N + j];
                    // Using standard integer multiplication and addition
                    acc = acc + soft_mul(a, b); 
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