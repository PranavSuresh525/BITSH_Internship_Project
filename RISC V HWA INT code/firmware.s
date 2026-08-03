	.file	"risc_code.c"
	.option nopic
	.attribute arch, "rv32i2p1"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	_start
	.type	_start, @function
_start:
 #APP
# 51 "risc_code.c" 1
	li sp, 262128
# 0 "" 2
 #NO_APP
	li	t5,0
	li	t4,12
	li	t6,144
	j	.L2
.L10:
	li	a2,0
.L3:
	add	a6,a6,a2
	addi	a0,a0,4
	addi	a1,a1,48
	beq	a1,a7,.L13
.L5:
	lw	a3,0(a0)
	lw	a4,0(a1)
	beq	a4,zero,.L10
	li	a2,0
.L4:
	andi	a5,a4,1
	neg	a5,a5
	and	a5,a5,a3
	add	a2,a2,a5
	slli	a3,a3,1
	srli	a4,a4,1
	bne	a4,zero,.L4
	j	.L3
.L13:
	add	a5,a7,t3
	sw	a6,0(a5)
	addi	t1,t1,1
	addi	a7,a7,4
	beq	t1,t4,.L6
.L8:
	addi	a1,a7,-576
	mv	a0,t3
	li	a6,0
	j	.L5
.L6:
	addi	t5,t5,12
	beq	t5,t6,.L7
.L2:
	slli	t3,t5,2
	li	a7,1152
	li	t1,0
	j	.L8
.L7:
	li	a4,4096
	li	a5,-559038464
	addi	a5,a5,-273
	sw	a5,-1792(a4)
	li	a5,0
 #APP
# 81 "risc_code.c" 1
	.insn r 0x0b, 0, 0, x0, a5, x0
# 0 "" 2
 #NO_APP
	li	a5,576
 #APP
# 82 "risc_code.c" 1
	.insn r 0x0b, 1, 0, x0, a5, x0
# 0 "" 2
 #NO_APP
	li	a5,1728
 #APP
# 83 "risc_code.c" 1
	.insn r 0x0b, 3, 0, x0, a5, x0
# 0 "" 2
 #NO_APP
	li	a5,-889274368
	addi	a5,a5,-1106
	sw	a5,-1788(a4)
.L9:
 #APP
# 88 "risc_code.c" 1
	nop
# 0 "" 2
 #NO_APP
	j	.L9
	.size	_start, .-_start
	.ident	"GCC: (14.2.0+19) 14.2.0"
	.section	.note.GNU-stack,"",@progbits
