// ---------------------------------------------------------
// Bare-Metal RISC-V WS Systolic Array Emulator with Tiling
// Computes C = A x B by tiling into BASE_LIMIT x BASE_LIMIT blocks,
// running each block pair through a weight-stationary array model,
// accumulating the partial results, and checking against a CPU matmul.
// ---------------------------------------------------------

#define BASE_LIMIT 8

#include "uart_debug.h"

// A[M][N] x B[N][K] = C[M][K], sized to fit the 16KB SRAM
#define M_DIM 24
#define N_DIM 24
#define K_DIM 24

// Tiles per dimension (+1 for ragged edges), multiplied
#define MAX_JOBS ((M_DIM / BASE_LIMIT + 1) * (N_DIM / BASE_LIMIT + 1) * (K_DIM / BASE_LIMIT + 1))

struct Tile {
    int row_start;
    int row_end;
    int col_start;
    int col_end;
    int width;
    int height;
};

// One array run: an A tile times a B tile
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
// Builds the tile job list; returns the job count
int matmul_hwa_feeder(int M, int N, int K, int base_limit, HwaJob* job_queue) {
    int job_count = 0;
    
    if (M <= 0 || N <= 0 || K <= 0) return 0;
    
    for (int n = 0; n < N; n += base_limit) {
        for (int k = 0; k < K; k += base_limit) {
            
            int n_end = min_i(n + base_limit, N);
            int k_end = min_i(k + base_limit, K);
            int height_B = n_end - n;
            int width_B = k_end - k;
            
            // B tile stays fixed while every A tile (m loop) streams past it
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
// B[i][j] stays in PE(i,j). A flows left to right, partial sums flow top to bottom.
void WS(const float* A, const float* B, float* C) {
    // Hardware pipeline registers between the PEs.
    // static: kept in .bss instead of the small stack
    static float in_regs[BASE_LIMIT * BASE_LIMIT] = {0.0f};
    static float psum_regs[BASE_LIMIT * BASE_LIMIT] = {0.0f};

    // static initializers run only once, so clear the pipeline for every tile
    for (int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) {
        in_regs[i] = 0.0f;
        psum_regs[i] = 0.0f;
    }

    // Initialize output matrix tile to 0
    for(int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) {
        C[i] = 0.0f;
    }

    // Fill (N) + compute (N) + drain (N)
    int max_cycles = 3 * BASE_LIMIT;

    for (int cycle = 0; cycle < max_cycles; cycle++) {
        // Register values after this clock edge
        static float next_in_regs[BASE_LIMIT * BASE_LIMIT];
        static float next_psum_regs[BASE_LIMIT * BASE_LIMIT];
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
                    // Bottom row: C row r leaves column j at cycle r + N + j
                    int output_row = cycle - BASE_LIMIT - j;
                    if (output_row >= 0 && output_row < BASE_LIMIT) {
                        C[output_row * BASE_LIMIT + j] = mac;
                    }
                }
            }
        }
        
        // 2. Emulate Input FIFOs (row i delayed by i cycles)
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
// Copies a tile out of a full matrix, zero-padding past the edges
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

// Adds a tile result into the full output matrix
void accumulate_tile(float* C_full, int full_cols, const float* C_tile, int row_start, int col_start, int max_row, int max_col) {
    for (int i = 0; i < BASE_LIMIT; i++) {
        for (int j = 0; j < BASE_LIMIT; j++) {
            if (row_start + i < max_row && col_start + j < max_col) {
                C_full[(row_start + i) * full_cols + (col_start + j)] += C_tile[i * BASE_LIMIT + j];
            }
        }
    }
}

// Reference matmul on the CPU
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

// Working tile buffers
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

    // 5. Verification (Relative Tolerance)
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

    // Latch status for debugger
    VERIFICATION_STATUS = passed;

    // No OpenOCD on this board -- report over UART instead
    report_verification(passed, fail_index, fail_hw, fail_cpu);

    // Halt execution (Bare-metal trap)
    while(1) { }

    return 0;
}