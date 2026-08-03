// ---------------------------------------------------------
// Bare-Metal RISC-V WS Systolic Array Emulator with Tiling
// ---------------------------------------------------------

#define BASE_LIMIT 8

#include "uart_debug.h"

// Adjust these based on your board's available SRAM / DRAM
// HiFive1 Rev B has 16KB total DTIM. At BASE_LIMIT=8, M_DIM=N_DIM=K_DIM=24:
// full matrices 9.0KB + tile buffers 0.75KB + WS() internal state 1.0KB +
// job queue (MAX_JOBS=64) 3.0KB = ~13.75KB used, ~2.25KB free for stack.
// This is close to the real ceiling for this chip -- see the SRAM budget
// walkthrough in chat before pushing these any higher.
#define M_DIM 24
#define N_DIM 24
#define K_DIM 24

// Maximum number of 8x8 tiles needed for the workload
#define MAX_JOBS ((M_DIM / BASE_LIMIT + 1) * (N_DIM / BASE_LIMIT + 1) * (K_DIM / BASE_LIMIT + 1))

struct Tile {
    int row_start;
    int row_end;
    int col_start;
    int col_end;
    int width;
    int height;
};

struct HwaJob {
    Tile a_tile;
    Tile b_tile;
};

// --- BARE-METAL MATH HELPERS ---
float abs_f(float x) {
    return (x < 0.0f) ? -x : x;
}

float max_f(float a, float b) {
    return (a > b) ? a : b;
}

int min_i(int a, int b) {
    return (a < b) ? a : b;
}

// --- HARDWARE SCHEDULER ---
int matmul_hwa_feeder(int M, int N, int K, int base_limit, HwaJob* job_queue) {
    int job_count = 0;
    
    if (M <= 0 || N <= 0 || K <= 0) return 0;
    
    for (int n = 0; n < N; n += base_limit) {
        for (int k = 0; k < K; k += base_limit) {
            
            int n_end = min_i(n + base_limit, N);
            int k_end = min_i(k + base_limit, K);
            int height_B = n_end - n;
            int width_B = k_end - k;
            
            Tile b_tile = { n, n_end, k, k_end, width_B, height_B };
            for (int m = 0; m < M; m += base_limit) {
                
                int m_end = min_i(m + base_limit, M);
                int height_A = m_end - m;
                int width_A = n_end - n; 
                
                Tile a_tile = { m, m_end, n, n_end, width_A, height_A };
                
                if (job_count < MAX_JOBS) {
                    job_queue[job_count].a_tile = a_tile;
                    job_queue[job_count].b_tile = b_tile;
                    job_count++;
                }
            }
        }
    }
    return job_count;
}

// --- WEIGHT STATIONARY (WS) ARRAY SIMULATION ---
void WS(const float* A, const float* B, float* C) {
    // Hardware pipeline registers between the PEs.
    // static: these are 4 x 4KB buffers. Left as stack locals, that's 16KB
    // of simultaneous stack depth inside one function call -- worse than the
    // DiP() case. Pin to .bss instead.
    static float in_regs[BASE_LIMIT * BASE_LIMIT] = {0.0f};
    static float psum_regs[BASE_LIMIT * BASE_LIMIT] = {0.0f};

    // IMPORTANT: static's "= {0.0f}" initializer only runs once ever (first
    // call), not on every call like it did when these were stack locals.
    // But this pipeline state MUST start empty at the beginning of every
    // tile job, or job N+1 starts with leftover register values from job N
    // -- a silent wrong-answer bug. So reset explicitly, every call.
    for (int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) {
        in_regs[i] = 0.0f;
        psum_regs[i] = 0.0f;
    }

    // Initialize output matrix tile to 0
    for(int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) {
        C[i] = 0.0f;
    }

    int max_cycles = 3 * BASE_LIMIT;

    for (int cycle = 0; cycle < max_cycles; cycle++) {
        static float next_in_regs[BASE_LIMIT * BASE_LIMIT];
        static float next_psum_regs[BASE_LIMIT * BASE_LIMIT];

        // Both arrays get fully rewritten by the code below EXCEPT
        // next_psum_regs row 0 (nothing ever assigns "i+1==0", there's no
        // PE row -1). I originally assumed that meant this reset loop was
        // load-bearing -- I tested it by removing it, and the result was
        // identical. Reason: static arrays with no initializer are
        // zero-initialized once, and since row 0 is never written anywhere
        // else in the algorithm, it just stays at that initial zero forever.
        // So on THIS (hosted) build, this loop is redundant.
        //
        // Keep it anyway for the bare-metal build: that zero-init guarantee
        // is a C++ language guarantee backed by your *startup code* clearing
        // .bss before main() runs. Nothing does that for you automatically
        // on real hardware -- and the minimal startup stub we'll write in
        // the next step won't either, unless we add it. This loop makes
        // correctness independent of whether .bss got zeroed at boot.
        for (int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) {
            next_in_regs[i] = 0.0f;
            next_psum_regs[i] = 0.0f;
        }

        // 1. PEs perform MACs and route data to neighbors
        for (int i = 0; i < BASE_LIMIT; i++) {
            for (int j = 0; j < BASE_LIMIT; j++) {
                // Flattened access: [i][j] becomes [i * BASE_LIMIT + j]
                float mac = psum_regs[i * BASE_LIMIT + j] + (in_regs[i * BASE_LIMIT + j] * B[i * BASE_LIMIT + j]);
                
                if (j + 1 < BASE_LIMIT) {
                    next_in_regs[i * BASE_LIMIT + (j + 1)] = in_regs[i * BASE_LIMIT + j];
                }
                
                if (i + 1 < BASE_LIMIT) {
                    next_psum_regs[(i + 1) * BASE_LIMIT + j] = mac;
                } else { 
                    int output_row = cycle - BASE_LIMIT - j;
                    if (output_row >= 0 && output_row < BASE_LIMIT) {
                        C[output_row * BASE_LIMIT + j] = mac;
                    }
                }
            }
        }
        
        // 2. Emulate Input FIFOs
        for (int i = 0; i < BASE_LIMIT; i++) {
            int input_row = cycle - i; 
            if (input_row >= 0 && input_row < BASE_LIMIT) {
                next_in_regs[i * BASE_LIMIT + 0] = A[input_row * BASE_LIMIT + i]; 
            } else {
                next_in_regs[i * BASE_LIMIT + 0] = 0.0f; 
            }
        }

        // 3. Clock tick: latch state
        for(int x = 0; x < BASE_LIMIT * BASE_LIMIT; x++){
            in_regs[x] = next_in_regs[x];
            psum_regs[x] = next_psum_regs[x];
        }
    }
}

// --- MEMORY ACCESS HELPERS ---
void extract_tile(const float* mat_full, int full_cols, int row_start, int col_start, int max_row, int max_col, float* tile) {
    for (int i = 0; i < BASE_LIMIT; i++) {
        for (int j = 0; j < BASE_LIMIT; j++) {
            if (row_start + i < max_row && col_start + j < max_col) {
                tile[i * BASE_LIMIT + j] = mat_full[(row_start + i) * full_cols + (col_start + j)];
            } else {
                tile[i * BASE_LIMIT + j] = 0.0f;
            }
        }
    }
}

void accumulate_tile(float* C_full, int full_cols, const float* C_tile, int row_start, int col_start, int max_row, int max_col) {
    for (int i = 0; i < BASE_LIMIT; i++) {
        for (int j = 0; j < BASE_LIMIT; j++) {
            if (row_start + i < max_row && col_start + j < max_col) {
                C_full[(row_start + i) * full_cols + (col_start + j)] += C_tile[i * BASE_LIMIT + j];
            }
        }
    }
}

void full_cpu_matmul(const float* A, const float* B, float* C, int M, int N, int K) {
    for (int i = 0; i < M * K; i++) C[i] = 0.0f; 
    
    for (int i = 0; i < M; ++i) {
        for (int j = 0; j < K; ++j) {
            for (int k = 0; k < N; ++k) {
                C[i * K + j] += A[i * N + k] * B[k * K + j];
            }
        }
    }
}

// --- STATIC ALLOCATIONS ---
// Placed in global scope (.bss segment) to prevent Stack Overflow
static float A_full[M_DIM * N_DIM];
static float B_full[N_DIM * K_DIM];
static float C_HW_full[M_DIM * K_DIM];
static float C_CPU_full[M_DIM * K_DIM];
static HwaJob scheduled_jobs[MAX_JOBS];

// Hardware registers for tile extraction
static float A_tile[BASE_LIMIT * BASE_LIMIT];
static float B_tile[BASE_LIMIT * BASE_LIMIT];
static float C_tile[BASE_LIMIT * BASE_LIMIT];

// Volatile flag to allow debugger (GDB) to read the final state
volatile int VERIFICATION_STATUS = -1; // -1: Running, 1: Passed, 0: Failed

int main() {
    // 1. Populate A_full
    float val = 124.55f;
    for (int i = 0; i < M_DIM; i++) {
        for (int j = 0; j < N_DIM; j++) {
            A_full[i * N_DIM + j] = val + (i * 3.1415f) - (j * 1.618f);
            val += 7.33f;
        }
    }

    // Populate B_full
    for (int i = 0; i < N_DIM; i++) {
        for (int j = 0; j < K_DIM; j++) {
            B_full[i * K_DIM + j] = ((val - i) * 0.5f / (j + 1.0f)) - 42.123f; 
            val += 7.33f;
        }
    }

    // 2. Generate Hardware Jobs
    int total_jobs = matmul_hwa_feeder(M_DIM, N_DIM, K_DIM, BASE_LIMIT, scheduled_jobs);

    // Initialize HW Output Matrix to 0
    for(int i = 0; i < M_DIM * K_DIM; i++) { C_HW_full[i] = 0.0f; }

    // 3. Emulate Hardware Dataflow
    for (int idx = 0; idx < total_jobs; idx++) {
        HwaJob job = scheduled_jobs[idx];
        
        extract_tile(A_full, N_DIM, job.a_tile.row_start, job.a_tile.col_start, M_DIM, N_DIM, A_tile);
        extract_tile(B_full, K_DIM, job.b_tile.row_start, job.b_tile.col_start, N_DIM, K_DIM, B_tile);
        
        WS(A_tile, B_tile, C_tile);
        
        accumulate_tile(C_HW_full, K_DIM, C_tile, job.a_tile.row_start, job.b_tile.col_start, M_DIM, K_DIM);
    }

    // 4. Baseline CPU compute
    full_cpu_matmul(A_full, B_full, C_CPU_full, M_DIM, N_DIM, K_DIM);

    // 5. Verification
    int passed = 1; 
    float relative_epsilon = 1e-4f; 
    int fail_index = -1;
    float fail_hw = 0.0f, fail_cpu = 0.0f;
    
    for (int i = 0; i < M_DIM * K_DIM; i++) {
        float hw = C_HW_full[i];
        float cpu = C_CPU_full[i];
        float diff = abs_f(hw - cpu);
        
        if (diff > 1e-5f) {
            float max_val = max_f(abs_f(hw), abs_f(cpu));
            if (diff / max_val > relative_epsilon) {
                passed = 0; 
                fail_index = i;
                fail_hw = hw;
                fail_cpu = cpu;
                break;
            }
        }
    }

    // Latch status for debugger (harmless to leave in -- costs nothing,
    // and still works if you DO ever get a debugger attached some other way)
    VERIFICATION_STATUS = passed;

    // No OpenOCD on this board -- report over UART since GDB isn't an option
    report_verification(passed, fail_index, fail_hw, fail_cpu);

    // Halt execution (Bare-metal trap)
    while(1) { }

    return 0;
}