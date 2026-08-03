#----------------------------------------------------------------------------------------
# Project Title: Complete Custom RISC-V & Matrix Assembler (with C front-end)
# Description:
#   1. Compiles risc_code.c → firmware.s  using riscv64-linux-gnu-gcc (RV32I target)
#   2. Converts firmware.s → firmware.hex using the custom RV32I + matrix-accelerator
#      assembler below.
#
# Usage:
#   python3 assembler.py
#
# Requirements:
#   - risc_code.c must exist in the working directory
#   - riscv64-linux-gnu-gcc must be installed
#     (sudo apt-get install gcc-riscv64-linux-gnu)
#----------------------------------------------------------------------------------------

import subprocess
import sys
import os
import re

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1 — Compile risc_code.c → firmware.s
# ─────────────────────────────────────────────────────────────────────────────

C_SOURCE = "risc_code.c"
ASM_OUT  = "firmware.s"
HEX_OUT  = "firmware.hex"
GCC      = "riscv64-unknown-elf-gcc"

CFLAGS = [
    "-march=rv32i",
    "-mabi=ilp32",
    "-S",                               # emit assembly only
    "-O1",                              # light optimisation → cleaner asm
    "-fno-pic",                         # no PIC relocations
    "-fno-asynchronous-unwind-tables",  # suppress CFI directives
    "-nostdlib",                        # bare-metal (no libc)
    "-fno-inline-small-functions",
]

if not os.path.isfile(C_SOURCE):
    print(f"Error: '{C_SOURCE}' not found in the current directory.")
    sys.exit(1)

print(f"[Stage 1] Compiling {C_SOURCE} → {ASM_OUT} ...")
result = subprocess.run(
    [GCC] + CFLAGS + [C_SOURCE, "-o", ASM_OUT],
    capture_output=True, text=True
)
if result.returncode != 0:
    print("Compilation failed:\n" + result.stderr)
    sys.exit(1)
print(f"          Done. Assembly written to {ASM_OUT}")

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 2 — Assemble firmware.s → firmware.hex
# ─────────────────────────────────────────────────────────────────────────────

print(f"[Stage 2] Assembling {ASM_OUT} → {HEX_OUT} ...")

# ──────────────────────────────────────────────────────────────────────────────
# Utility helpers
# ──────────────────────────────────────────────────────────────────────────────

def to_binary(val, bits):
    """Convert any int / hex-string / decimal-string to a 2's-complement binary string."""
    if isinstance(val, str):
        val = val.strip()
        val = int(val, 16) if (val.startswith('0x') or val.startswith('-0x')) else int(val, 0)
    if val < 0:
        val = (1 << bits) + val
    return bin(val)[2:].zfill(bits)[-bits:]


def write_word(mem_file, bits32, pc):
    """Write one 32-bit binary string as 8-hex-char line; return incremented PC."""
    mem_file.write(format(int(bits32, 2), '08x') + '\n')
    return pc + 4

# ──────────────────────────────────────────────────────────────────────────────
# Register maps
# ──────────────────────────────────────────────────────────────────────────────

REG = {
    'x0':'00000','x1':'00001','x2':'00010','x3':'00011','x4':'00100','x5':'00101','x6':'00110','x7':'00111',
    'x8':'01000','x9':'01001','x10':'01010','x11':'01011','x12':'01100','x13':'01101','x14':'01110','x15':'01111',
    'x16':'10000','x17':'10001','x18':'10010','x19':'10011','x20':'10100','x21':'10101','x22':'10110','x23':'10111',
    'x24':'11000','x25':'11001','x26':'11010','x27':'11011','x28':'11100','x29':'11101','x30':'11110','x31':'11111',
    'zero':'00000','ra':'00001','sp':'00010','gp':'00011','tp':'00100','t0':'00101','t1':'00110','t2':'00111',
    's0':'01000','fp':'01000','s1':'01001','a0':'01010','a1':'01011','a2':'01100','a3':'01101','a4':'01110',
    'a5':'01111','a6':'10000','a7':'10001','s2':'10010','s3':'10011','s4':'10100','s5':'10101','s6':'10110',
    's7':'10111','s8':'11000','s9':'11001','s10':'11010','s11':'11011','t3':'11100','t4':'11101','t5':'11110','t6':'11111'
}

CSR_ADDR = {'mie':'0x304','mtvec':'0x305','mepc':'0x341'}

# ──────────────────────────────────────────────────────────────────────────────
# Directives that generate NO machine words — silently skip them
# ──────────────────────────────────────────────────────────────────────────────

SKIP_DIRECTIVES = {
    # Section / linkage
    '.text','.globl','.global','.data','.bss','.section','.rodata',
    # Type / size annotations
    '.type','.size',
    # GCC/RISC-V arch attributes
    '.option','.attribute',
    # CFI unwind (suppressed by -fno-asynchronous-unwind-tables, kept as fallback)
    '.cfi_startproc','.cfi_endproc','.cfi_def_cfa','.cfi_def_cfa_offset',
    '.cfi_def_cfa_register','.cfi_offset','.cfi_restore','.cfi_remember_state',
    '.cfi_restore_state','.cfi_return_column',
    # Alignment — not modelling padding bytes
    '.align','.p2align','.balign',
    # Strings / metadata
    '.ident','.file',
    # GCC linkonce / weak
    '.weak','.comm','.lcomm',
}

# ──────────────────────────────────────────────────────────────────────────────
# Instruction size table  (1 = 1 word, 2 = expands to 2 words)
# ──────────────────────────────────────────────────────────────────────────────

ISIZE = {
    'lui':1,'auipc':1,'jal':1,'jalr':1,
    'beq':1,'bne':1,'blt':1,'bge':1,'bltu':1,'bgeu':1,
    # GCC branch pseudos (synthesised from bge/blt with swapped operands)
    'ble':1,'bgt':1,'bleu':1,'bgtu':1,
    'beqz':1,'bnez':1,'blez':1,'bgez':1,'bltz':1,'bgtz':1,
    # Loads
    'lb':1,'lh':1,'lw':1,'lbu':1,'lhu':1,
    # Stores
    'sb':1,'sh':1,'sw':1,
    # I-type ALU
    'addi':1,'slti':1,'sltiu':1,'xori':1,'ori':1,'andi':1,'slli':1,'srli':1,'srai':1,
    # R-type ALU
    'add':1,'sub':1,'sll':1,'slt':1,'sltu':1,'xor':1,'srl':1,'sra':1,'or':1,'and':1,
    # Pseudos – single word
    'mv':1,'not':1,'neg':1,'seqz':1,'snez':1,'sltz':1,'sgtz':1,'sgt':1,
    'j':1,'jr':1,'ret':1,'mret':1,'call':1,'tail':1,'nop':1,
    # Pseudos – two words
    'li':2,'la':2,
    # CSR
    'csrrw':1,'csrrs':1,'csrrc':1,'csrrwi':1,'csrrsi':1,'csrrci':1,
    'csrr':1,'csrw':1,'csrs':1,'csrc':1,
    # Directives that DO emit words
    '.word':1,'.insn':1,
    # Custom accelerator
    'matmul_load_a':1,'matmul_compute':1,'matmul_store_c':1,
}

# ──────────────────────────────────────────────────────────────────────────────
# Pre-processing helpers
# ──────────────────────────────────────────────────────────────────────────────

def strip_comment(line):
    """Remove # and // comments."""
    for m in ('//', '#'):
        idx = line.find(m)
        if idx != -1:
            line = line[:idx]
    return line

def is_gcc_local_label(s):
    """True for .LFB0, .LFE0, .L1, etc. (including the colon)."""
    return s.startswith('.L') and s.endswith(':')

def is_skip_directive(tokens):
    t0 = tokens[0]
    if t0 in SKIP_DIRECTIVES:
        return True
    # Any unknown directive not known to emit a word
    if t0.startswith('.') and t0 not in ISIZE:
        return True
    return False

# %hi(sym) and %lo(sym) relocation expressions — resolve to 0 (placeholder)
# for symbols we can look up in label_dict later.
def strip_reloc(expr, label_dict, current_pc=0, is_lo=False):
    """
    Handle GCC relocation expressions like %hi(.LANCHOR0) and %lo(.LANCHOR0).
    Returns an integer value.
    """
    expr = expr.strip()
    hi_m = re.match(r'%hi\(([^)]+)\)', expr)
    lo_m = re.match(r'%lo\(([^)]+)\)', expr)
    if hi_m:
        sym = hi_m.group(1)
        addr = int(label_dict.get(sym, '0'))
        return (addr + 0x800) >> 12  # standard %hi rounding
    if lo_m:
        sym = lo_m.group(1)
        addr = int(label_dict.get(sym, '0'))
        return addr & 0xFFF if (addr & 0xFFF) < 0x800 else (addr & 0xFFF) - 0x1000
    # Plain integer or label offset
    try:
        return int(expr, 0)
    except ValueError:
        # Label-relative — resolve against label_dict
        if expr in label_dict:
            return int(label_dict[expr]) - current_pc
        return 0

# ──────────────────────────────────────────────────────────────────────────────
# Read and clean firmware.s
# ──────────────────────────────────────────────────────────────────────────────

with open(ASM_OUT, 'r') as f:
    raw_lines = f.readlines()

cleaned = []
for line in raw_lines:
    line = strip_comment(line)
    line = line.replace(',', ' ')
    tokens = line.split()
    if not tokens:
        continue
    cleaned.append(' '.join(tokens))

# Handle  .set NAME, VALUE  →  treat as a label definition at the given address
# (GCC uses .set .LANCHOR0, . + 0 for rodata anchors)
set_defs = {}   # name → raw expression (resolved later)
instr_arr = []
for line in cleaned:
    tokens = line.split()
    if not tokens:
        continue
    t0 = tokens[0]

    if t0 == '.set' and len(tokens) >= 3:
        # e.g.  .set .LANCHOR0 . + 0
        # Store for later resolution; for now record as a label at PC_cnt placeholder
        set_defs[tokens[1]] = tokens[2:]  # raw RHS tokens
        instr_arr.append(line)            # keep so PC_arr slot is allocated
        continue

    if is_gcc_local_label(t0):
        instr_arr.append(line)
        continue

    if is_skip_directive(tokens):
        continue

    instr_arr.append(line)

# ──────────────────────────────────────────────────────────────────────────────
# Pass 1 — assign PC values; collect .equ definitions
# ──────────────────────────────────────────────────────────────────────────────

var_dict = {}
PC_arr   = []
PC_cnt   = 0

for line in instr_arr:
    tokens = line.split()
    t0     = tokens[0]

    if t0 == '.equ':
        var_dict[tokens[1].rstrip(',')] = to_binary(tokens[2], 32)
        PC_arr.append(-1)

    elif t0 == '.set':
        # Reserve a slot but don't advance PC
        PC_arr.append(-1)

    elif ':' in t0 or is_gcc_local_label(t0):
        PC_arr.append(-1)

    else:
        size = ISIZE.get(t0, 1)
        for _ in range(size):
            PC_arr.append(PC_cnt)
            PC_cnt += 4

# ──────────────────────────────────────────────────────────────────────────────
# Pass 2 — build label_dict  (each label → PC of next real instruction)
# ──────────────────────────────────────────────────────────────────────────────

label_dict = {}

# First, seed with labels from the raw file
#
# BUGFIX: `j` must track the true running index into PC_arr, not just the
# source-line count. Pass 1 (above) appends `size` slots to PC_arr for any
# instruction whose ISIZE entry is > 1 (e.g. many `li` expansions are 2
# words), but a plain "j += 1 per line" walk falls permanently behind
# PC_arr's real length as soon as the first such instruction appears --
# every label defined afterward then gets resolved against a stale, too-early
# PC_arr slot. The error accumulates for the rest of the file, so branch/jump
# targets drift further and further from where the label actually is,
# producing what looks like "random" wrong jumps (including accidental
# infinite loops) anywhere past the first multi-word instruction.
j = 0
for line in instr_arr:
    tokens = line.split()
    t0     = tokens[0]

    if t0 == '.equ' or t0 == '.set' or ':' in t0 or is_gcc_local_label(t0):
        if ':' in t0 or is_gcc_local_label(t0):
            name = t0.rstrip(':')
            # Find the PC of the next non-(-1) slot
            for k in range(j + 1, len(PC_arr)):
                if PC_arr[k] != -1:
                    label_dict[name] = str(PC_arr[k])
                    break
            else:
                label_dict[name] = str(PC_cnt)  # past end
        j += 1
    else:
        j += ISIZE.get(t0, 1)

# Resolve .set definitions into the label_dict
# Simple support: ". + 0" → current slot PC, bare label name
for name, rhs_tokens in set_defs.items():
    expr = ' '.join(rhs_tokens)
    if expr.strip() in label_dict:
        label_dict[name] = label_dict[expr.strip()]
    else:
        # ". + N" not easily resolved here; point to whatever slot they define
        # Use 0 as a safe fallback (rodata won't be reached in execution)
        label_dict[name] = '0'

# ──────────────────────────────────────────────────────────────────────────────
# Resolve a branch/jump target or immediate operand
# ──────────────────────────────────────────────────────────────────────────────

def resolve(expr, pc, ld=label_dict):
    expr = str(expr).strip()
    # Relocation wrappers
    if expr.startswith('%'):
        return strip_reloc(expr, ld, pc)
    # Known label
    if expr in ld:
        return int(ld[expr]) - pc
    # Numeric
    try:
        return int(expr, 0)
    except ValueError:
        # Unresolved external symbol (e.g. __mulsi3) — emit NOP and warn
        print(f"  [WARN] Unresolved symbol '{expr}' at PC={pc:#010x} — emitting NOP (addi x0,x0,0)")
        return None   # caller must handle

# ──────────────────────────────────────────────────────────────────────────────
# Pass 3 — machine-code generation
# ──────────────────────────────────────────────────────────────────────────────

NOP = '00000000000000000000000000010011'   # addi x0, x0, 0

with open(HEX_OUT, 'w') as mf:
    PC_cnt = 0
    j_arr  = 0   # index into PC_arr

    i = 0
    while i < len(instr_arr):
        line   = instr_arr[i]
        tokens = line.split()
        t0     = tokens[0]

        # ── skip pseudo-lines ──────────────────────────────────────────────
        if t0 == '.equ' or t0 == '.set' or ':' in t0 or is_gcc_local_label(t0):
            i += 1
            j_arr += 1
            continue

        op = t0
        mw = ''   # machine word (32-bit binary string)

        # ══════════════════════════════════════════════════════════════════
        # CUSTOM ACCELERATOR
        # ══════════════════════════════════════════════════════════════════
        if op == 'matmul_load_a':
            mw = '000000000000' + REG[tokens[1]] + '00000000' + '0001011'

        elif op == 'matmul_compute':
            mw = '000000000000' + REG[tokens[1]] + '00100000' + '0001011'

        elif op == 'matmul_store_c':
            mw = '000000000000' + REG[tokens[1]] + '01100000' + '0001011'

        elif op == '.insn':
            # .insn r <opcode>, <funct3>, <funct7>, rd, rs1, rs2
            opcode = format(int(tokens[2], 0), '07b')
            f3     = format(int(tokens[3]), '03b')
            f7     = format(int(tokens[4], 0), '07b')
            rd, rs1, rs2 = tokens[5], tokens[6], tokens[7]
            mw = f7 + REG[rs2] + REG[rs1] + f3 + REG[rd] + opcode

        elif op == '.word':
            mw = to_binary(tokens[1], 32)

        elif op == 'nop':
            mw = NOP

        # ══════════════════════════════════════════════════════════════════
        # U-TYPE
        # ══════════════════════════════════════════════════════════════════
        elif op in ('lui', 'auipc'):
            rd      = tokens[1]
            imm_val = strip_reloc(tokens[2], label_dict, PC_cnt) if tokens[2].startswith('%') else int(tokens[2], 0)
            mw      = to_binary(imm_val, 20) + REG[rd] + ('0110111' if op == 'lui' else '0010111')

        # ══════════════════════════════════════════════════════════════════
        # J-TYPE  (jal)
        # ══════════════════════════════════════════════════════════════════
        elif op == 'jal':
            rd      = tokens[1]
            r       = resolve(tokens[2], PC_cnt)
            if r is None:
                mw = NOP
            else:
                imm = to_binary(r, 21)
                mw  = imm[0] + imm[10:20] + imm[9] + imm[1:9] + REG[rd] + '1101111'

        # ══════════════════════════════════════════════════════════════════
        # B-TYPE branches (canonical + GCC pseudos)
        # ══════════════════════════════════════════════════════════════════
        elif op in ('beq','bne','blt','bge','bltu','bgeu',
                    'ble','bgt','bleu','bgtu',
                    'beqz','bnez','bltz','blez','bgez','bgtz'):

            # ble rs1, rs2, lbl  →  bge rs2, rs1, lbl  (swap operands)
            # bgt rs1, rs2, lbl  →  blt rs2, rs1, lbl
            GCC_PSEUDO = {'ble':('bge',True), 'bgt':('blt',True),
                          'bleu':('bgeu',True),'bgtu':('bltu',True)}

            effective_op = op
            swap = False
            if op in GCC_PSEUDO:
                effective_op, swap = GCC_PSEUDO[op]

            if op in ('beqz','bnez','bltz','blez','bgez','bgtz'):
                rs1    = tokens[1]
                rs2    = 'x0'
                target = tokens[2]
            else:
                rs1    = tokens[1]
                rs2    = tokens[2]
                target = tokens[3]

            if swap:
                rs1, rs2 = rs2, rs1
            # blez / bgtz pseudo: swap too
            if op == 'blez':
                rs1, rs2 = rs2, rs1
                effective_op = 'bge'
            elif op == 'bgtz':
                rs1, rs2 = rs2, rs1
                effective_op = 'blt'

            F3 = {'beq':'000','bne':'001','blt':'100','bge':'101','bltu':'110','bgeu':'111',
                  'beqz':'000','bnez':'001','bltz':'100','bgez':'101','blez':'101','bgtz':'100'}

            r = resolve(target, PC_cnt)
            if r is None:
                mw = NOP
            else:
                imm = to_binary(r, 13)
                mw  = (imm[0] + imm[2:8] + REG[rs2] + REG[rs1] +
                       F3.get(effective_op, F3.get(op,'000')) + imm[8:12] + imm[1] + '1100011')

        # ══════════════════════════════════════════════════════════════════
        # I-TYPE LOADS
        # ══════════════════════════════════════════════════════════════════
        elif op in ('lb','lh','lw','lbu','lhu'):
            rd = tokens[1]
            if '(' in tokens[2]:
                parts = tokens[2].replace(')', '').split('(')
                imm   = to_binary(parts[0], 12)
                rs1   = parts[1]
            else:
                rs1   = tokens[2]
                imm   = to_binary(tokens[3], 12)
            F3 = {'lb':'000','lh':'001','lw':'010','lbu':'100','lhu':'101'}
            mw = imm + REG[rs1] + F3[op] + REG[rd] + '0000011'

        # ══════════════════════════════════════════════════════════════════
        # JALR
        # ══════════════════════════════════════════════════════════════════
        elif op == 'jalr':
            rd = tokens[1]
            if '(' in tokens[2]:
                parts = tokens[2].replace(')', '').split('(')
                imm   = to_binary(parts[0], 12)
                rs1   = parts[1]
            elif len(tokens) == 3:
                # jalr rs  →  jalr x0, rs, 0  (tail-call form)
                rs1   = tokens[2]
                imm   = to_binary(0, 12)
                rd    = 'x0'
            else:
                rs1   = tokens[2]
                imm   = to_binary(tokens[3], 12)
            mw = imm + REG[rs1] + '000' + REG[rd] + '1100111'

        # ══════════════════════════════════════════════════════════════════
        # S-TYPE STORES
        # ══════════════════════════════════════════════════════════════════
        elif op in ('sb','sh','sw'):
            rs2 = tokens[1]
            if '(' in tokens[2]:
                parts = tokens[2].replace(')', '').split('(')
                imm   = to_binary(parts[0], 12)
                rs1   = parts[1]
            else:
                rs1   = tokens[2]
                imm   = to_binary(tokens[3], 12)
            F3 = {'sb':'000','sh':'001','sw':'010'}
            mw = imm[0:7] + REG[rs2] + REG[rs1] + F3[op] + imm[7:12] + '0100011'

        # ══════════════════════════════════════════════════════════════════
        # I-TYPE ALU
        # ══════════════════════════════════════════════════════════════════
        elif op in ('addi','slti','sltiu','xori','ori','andi','slli','srli','srai'):
            rd  = tokens[1]
            rs1 = tokens[2]
            F3  = {'addi':'000','slli':'001','slti':'010','sltiu':'011',
                   'xori':'100','srli':'101','srai':'101','ori':'110','andi':'111'}
            if op in ('slli','srli','srai'):
                shamt  = to_binary(tokens[3], 5)
                funct7 = '0100000' if op == 'srai' else '0000000'
                mw     = funct7 + shamt + REG[rs1] + F3[op] + REG[rd] + '0010011'
            else:
                raw = tokens[3]
                imm_val = strip_reloc(raw, label_dict, PC_cnt) if raw.startswith('%') else int(raw, 0)
                mw  = to_binary(imm_val, 12) + REG[rs1] + F3[op] + REG[rd] + '0010011'

        # ══════════════════════════════════════════════════════════════════
        # R-TYPE ALU
        # ══════════════════════════════════════════════════════════════════
        elif op in ('add','sub','sll','slt','sltu','xor','srl','sra','or','and'):
            rd  = tokens[1]
            rs1 = tokens[2]
            rs2 = tokens[3]
            F3  = {'add':'000','sub':'000','sll':'001','slt':'010','sltu':'011',
                   'xor':'100','srl':'101','sra':'101','or':'110','and':'111'}
            f7  = '0100000' if op in ('sub','sra') else '0000000'
            mw  = f7 + REG[rs2] + REG[rs1] + F3[op] + REG[rd] + '0110011'

        # ══════════════════════════════════════════════════════════════════
        # PSEUDO: li  (lui + addi, 2 words)
        # ══════════════════════════════════════════════════════════════════
        elif op == 'li':
            rd  = tokens[1]
            val = int(tokens[2], 0)
            low = val & 0xFFF
            hi  = (val >> 12) & 0xFFFFF
            if low >= 0x800:
                hi  = (hi + 1) & 0xFFFFF
                low = low - 0x1000
            mw1 = to_binary(hi, 20) + REG[rd] + '0110111'   # lui
            mw2 = to_binary(low, 12) + REG[rd] + '000' + REG[rd] + '0010011'  # addi
            PC_cnt = write_word(mf, mw1, PC_cnt)
            PC_cnt = write_word(mf, mw2, PC_cnt)
            i += 1; j_arr += 2
            continue

        # ══════════════════════════════════════════════════════════════════
        # PSEUDO: la  (auipc + addi, 2 words)
        # ══════════════════════════════════════════════════════════════════
        elif op == 'la':
            rd  = tokens[1]
            r   = resolve(tokens[2], PC_cnt)
            r   = r if r is not None else 0
            low = r & 0xFFF
            hi  = (r >> 12) & 0xFFFFF
            if low >= 0x800:
                hi  = (hi + 1) & 0xFFFFF
                low = low - 0x1000
            mw1 = to_binary(hi, 20) + REG[rd] + '0010111'   # auipc
            mw2 = to_binary(low, 12) + REG[rd] + '000' + REG[rd] + '0010011'  # addi
            PC_cnt = write_word(mf, mw1, PC_cnt)
            PC_cnt = write_word(mf, mw2, PC_cnt)
            i += 1; j_arr += 2
            continue

        # ══════════════════════════════════════════════════════════════════
        # PSEUDO: mv  →  addi rd, rs, 0
        # ══════════════════════════════════════════════════════════════════
        elif op == 'mv':
            mw = '000000000000' + REG[tokens[2]] + '000' + REG[tokens[1]] + '0010011'

        elif op == 'not':
            mw = to_binary(-1, 12) + REG[tokens[2]] + '100' + REG[tokens[1]] + '0010011'

        elif op == 'neg':
            mw = '0100000' + REG[tokens[2]] + '00000' + '000' + REG[tokens[1]] + '0110011'

        elif op == 'seqz':
            mw = '000000000001' + REG[tokens[2]] + '011' + REG[tokens[1]] + '0010011'

        elif op == 'snez':
            mw = '0000000' + REG[tokens[2]] + '00000' + '011' + REG[tokens[1]] + '0110011'

        elif op == 'sltz':
            mw = '0000000' + '00000' + REG[tokens[2]] + '010' + REG[tokens[1]] + '0110011'

        elif op == 'sgtz':
            mw = '0000000' + REG[tokens[2]] + '00000' + '010' + REG[tokens[1]] + '0110011'
        
        elif op == 'sgt':
            mw = '0000000' + REG[tokens[3]] + REG[tokens[2]] + '010' + REG[tokens[1]] + '0110011'

        # ══════════════════════════════════════════════════════════════════
        # PSEUDO: j / jr / ret / call / tail
        # ══════════════════════════════════════════════════════════════════
        elif op == 'j':
            r = resolve(tokens[1], PC_cnt)
            if r is None:
                mw = NOP
            else:
                imm = to_binary(r, 21)
                mw  = imm[0] + imm[10:20] + imm[9] + imm[1:9] + '00000' + '1101111'

        elif op == 'jr':
            rs1 = tokens[1]
            mw  = '000000000000' + REG[rs1] + '000' + '00000' + '1100111'

        elif op == 'ret':
            mw = '000000000000' + '00001' + '000' + '00000' + '1100111'

        elif op == 'mret':
            mw = '00110000001000000000000001110011'

        elif op == 'call':
            r = resolve(tokens[1], PC_cnt)
            if r is None:
                mw = NOP
            else:
                imm = to_binary(r, 21)
                mw  = imm[0] + imm[10:20] + imm[9] + imm[1:9] + REG['ra'] + '1101111'

        elif op == 'tail':
            r = resolve(tokens[1], PC_cnt)
            if r is None:
                mw = NOP
            else:
                imm = to_binary(r, 21)
                mw  = imm[0] + imm[10:20] + imm[9] + imm[1:9] + '00000' + '1101111'

        # ══════════════════════════════════════════════════════════════════
        # CSR
        # ══════════════════════════════════════════════════════════════════
        elif op in ('csrrw','csrrs','csrrc','csrrwi','csrrsi','csrrci'):
            rd  = tokens[1]
            csr = tokens[2]
            rs1 = tokens[3]
            csr_addr = to_binary(int(CSR_ADDR.get(csr, csr), 16), 12)
            F3 = {'csrrw':'001','csrrs':'010','csrrc':'011',
                  'csrrwi':'101','csrrsi':'110','csrrci':'111'}
            if op.endswith('i'):
                mw = csr_addr + to_binary(rs1, 5) + F3[op] + REG[rd] + '1110011'
            else:
                mw = csr_addr + REG[rs1] + F3[op] + REG[rd] + '1110011'

        elif op == 'csrw':
            csr = tokens[1]; rs1 = tokens[2]
            csr_addr = to_binary(int(CSR_ADDR.get(csr, csr), 16), 12)
            mw = csr_addr + REG[rs1] + '001' + '00000' + '1110011'

        elif op == 'csrr':
            rd = tokens[1]; csr = tokens[2]
            csr_addr = to_binary(int(CSR_ADDR.get(csr, csr), 16), 12)
            mw = csr_addr + '00000' + '010' + REG[rd] + '1110011'

        else:
            print(f"  [WARN] Unknown op '{op}' at PC={PC_cnt:#010x} — skipped")
            i += 1; j_arr += 1
            continue

        if len(mw) != 32:
            print(f"  [BUG] '{op}' produced {len(mw)}-bit word at PC={PC_cnt:#010x} — NOP inserted")
            mw = NOP

        PC_cnt = write_word(mf, mw, PC_cnt)
        i += 1
        j_arr += 1

    # Pad to 256 words
    written = PC_cnt // 4
    for _ in range(written, 256):
        mf.write("00000000\n")

print(f"          Done. {PC_cnt // 4} instruction word(s) assembled → {HEX_OUT}")
print("Assembly pipeline complete.")