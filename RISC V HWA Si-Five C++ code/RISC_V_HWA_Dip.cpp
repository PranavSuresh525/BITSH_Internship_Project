// ---------------------------------------------------------
// Bare-Metal RISC-V DiP Systolic Array Emulator with Tiling
// ---------------------------------------------------------

#define BASE_LIMIT 8

#include "uart_debug.h"

// Matrix Dimensions (Keep these scaled to fit your specific board's SRAM)
#define M_DIM 24
#define N_DIM 24
#define K_DIM 24

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

// Bare-metal absolute value for floats
float abs_f(float x) {
    return (x < 0.0f) ? -x : x;
}

// Bare-metal max value for floats
float max_f(float a, float b) {
    return (a > b) ? a : b;
}

// --- HARDWARE SCHEDULER ---
int matmul_hwa_feeder(int M, int N, int K, int base_limit, HwaJob* job_queue) {
    int job_count = 0;
    
    if (M <= 0 || N <= 0 || K <= 0) return 0;
    
    for (int n = 0; n < N; n += base_limit) {
        for (int k = 0; k < K; k += base_limit) {
            
            int n_end = (n + base_limit < N) ? (n + base_limit) : N;
            int k_end = (k + base_limit < K) ? (k + base_limit) : K;
            int height_B = n_end - n;
            int width_B = k_end - k;
            
            Tile b_tile = { n, n_end, k, k_end, width_B, height_B };
            for (int m = 0; m < M; m += base_limit) {
                
                int m_end = (m + base_limit < M) ? (m + base_limit) : M;
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

// --- HARDWARE ARRAY SIMULATION ---
void permute(const float* matrix, float* permutated_matrix) {
    for (int i = 0; i < BASE_LIMIT; i++) {
        for (int j = 0; j < BASE_LIMIT; j++) {
            // Flattened 2D index mapping
            permutated_matrix[j * BASE_LIMIT + i] = matrix[((j + i) % BASE_LIMIT) * BASE_LIMIT + i];
        }
    }
}

void DiP(const float* A, const float* B, float* C) {
    // These were plain stack locals before. Three 32x32 float buffers is
    // 3 * 4KB = 12KB, live simultaneously with W+current_A+next_A at various
    // points in this function -- plus whatever the caller (main) already has
    // on the stack. On a real embedded core with a few KB of stack that is
    // an overflow waiting to happen. `static` here means "allocate once in
    // .bss, not on the stack" -- same lifetime as a global, but scoped to
    // this function so it can't be touched from anywhere else.
    static float W[BASE_LIMIT * BASE_LIMIT] = {0.0f};
    permute(B, W);
    
    static float current_A[BASE_LIMIT * BASE_LIMIT] = {0.0f}; 
    for (int i = 0; i < BASE_LIMIT; i++) {
        for (int j = 0; j < BASE_LIMIT; j++) {
            current_A[i * BASE_LIMIT + j] = A[i * BASE_LIMIT + ((i + j) % BASE_LIMIT)];
        }
    }

    // Initialize Output Tile to 0
    for(int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) { C[i] = 0.0f; }

    for (int cycle = 0; cycle < BASE_LIMIT; cycle++) {
        for (int i = 0; i < BASE_LIMIT; i++) {
            for (int j = 0; j < BASE_LIMIT; j++) {
                int output_row = (i - cycle + BASE_LIMIT) % BASE_LIMIT;
                C[output_row * BASE_LIMIT + j] += current_A[i * BASE_LIMIT + j] * W[i * BASE_LIMIT + j]; 
            }
        }
        
        static float next_A[BASE_LIMIT * BASE_LIMIT] = {0.0f};
        for (int i = 0; i < BASE_LIMIT; i++) {
            for (int j = 0; j < BASE_LIMIT; j++) {
                int next_row = (i + 1) % BASE_LIMIT;
                int next_col = (j - 1 + BASE_LIMIT) % BASE_LIMIT;
                next_A[next_row * BASE_LIMIT + next_col] = current_A[i * BASE_LIMIT + j];
            }
        }
        
        for (int i = 0; i < BASE_LIMIT * BASE_LIMIT; i++) {
            current_A[i] = next_A[i]; 
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
    for (int i = 0; i < M * K; i++) C[i] = 0.0f; // zero out
    
    for (int i = 0; i < M; ++i) {
        for (int j = 0; j < K; ++j) {
            for (int k = 0; k < N; ++k) {
                C[i * K + j] += A[i * N + k] * B[k * K + j];
            }
        }
    }
}

// --- STATIC ALLOCATIONS ---
// Allocated in .bss segment to avoid blowing up the micro stack
static float A_full[M_DIM * N_DIM];
static float B_full[N_DIM * K_DIM];
static float C_HW_full[M_DIM * K_DIM];
static float C_CPU_full[M_DIM * K_DIM];

static HwaJob scheduled_jobs[MAX_JOBS];

// Tile working buffers -- were stack locals in main() before. Same reasoning
// as the buffers inside DiP(): 3 * 4KB on the stack of main(), simultaneously
// alive with whatever main() calls into (DiP(), extract_tile(), etc). Pin
// them to .bss like every other sizeable buffer in this file.
static float A_tile[BASE_LIMIT * BASE_LIMIT];
static float B_tile[BASE_LIMIT * BASE_LIMIT];
static float C_tile[BASE_LIMIT * BASE_LIMIT];

// Volatile flag to view verification result in GDB
volatile int VERIFICATION_STATUS = -1; // -1: Running, 1: Passed, 0: Failed

int main() {
    // 1. Populate Matrices
    float val = 124.55f;
    for (int i = 0; i < M_DIM; i++) {
        for (int j = 0; j < N_DIM; j++) {
            A_full[i * N_DIM + j] = val + (i * 3.1415f) - (j * 1.618f);
            val += 7.33f;
        }
    }

    for (int i = 0; i < N_DIM; i++) {
        for (int j = 0; j < K_DIM; j++) {
            B_full[i * K_DIM + j] = ((val - i) * 0.5f / (j + 1.0f)) - 42.123f; 
            val += 7.33f;
        }
    }

    // 2. Generate Hardware Jobs
    int total_jobs = matmul_hwa_feeder(M_DIM, N_DIM, K_DIM, BASE_LIMIT, scheduled_jobs);

    // Buffer tiles for processing (declared as static globals above, not here)

    // 3. Emulate Hardware Dataflow
    for (int idx = 0; idx < total_jobs; idx++) {
        HwaJob job = scheduled_jobs[idx];
        
        extract_tile(A_full, N_DIM, job.a_tile.row_start, job.a_tile.col_start, M_DIM, N_DIM, A_tile);
        extract_tile(B_full, K_DIM, job.b_tile.row_start, job.b_tile.col_start, N_DIM, K_DIM, B_tile);
        
        DiP(A_tile, B_tile, C_tile);
        
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
                passed = 0; // Failed
                fail_index = i;
                fail_hw = hw;
                fail_cpu = cpu;
                break;
            }
        }
    }

    // Set hardware status register (visible via GDB, if you have one attached)
    VERIFICATION_STATUS = passed;

    // No OpenOCD on this board -- report over UART since GDB isn't an option
    report_verification(passed, fail_index, fail_hw, fail_cpu);

    // Bare-metal infinite loop (prevents CPU from marching into undefined memory)
    while(1) {
        // Sleep or wait for interrupt instruction could go here (wfi)
    }

    return 0;
}