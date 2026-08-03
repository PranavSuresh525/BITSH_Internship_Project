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
# 126 "risc_code.c" 1
	li sp, 262128
# 0 "" 2
 #NO_APP
	li	t4,8
	li	t5,0
	li	t6,32768
	li	t0,255
	li	a7,65536
	li	s1,30
	li	s0,2
	li	s2,16
	j	.L2
.L5:
	addi	s4,s4,-127
	srli	a1,a1,7
	andi	a1,a1,127
	j	.L6
.L10:
	sub	s4,s3,s4
	bgt	s4,s1,.L13
	srl	a3,a3,s4
	mv	s4,s3
.L12:
	beq	a1,a5,.L31
	bgeu	a3,a2,.L32
.L16:
	sub	a4,a2,a3
	mv	a1,a5
	j	.L17
.L45:
	li	a2,0
.L31:
	add	a4,a2,a3
.L15:
	beq	a4,zero,.L9
.L17:
	bltu	a4,a7,.L18
	li	a5,0
.L19:
	srli	a4,a4,1
	addi	a5,a5,1
	bgeu	a4,a7,.L19
.L20:
	add	a5,s4,a5
	srli	a4,a4,8
	andi	a4,a4,127
	blt	a5,zero,.L43
.L29:
	ble	a5,t0,.L23
	li	a5,255
.L23:
	slli	a5,a5,7
	slli	a1,a1,15
	or	a1,a1,a4
	or	a4,a5,a1
	j	.L9
.L36:
	mv	s4,s3
	li	a3,0
	j	.L31
.L43:
	slli	a4,a1,15
	j	.L9
.L33:
	mv	a4,a5
.L9:
	addi	a0,a0,4
	addi	a6,a6,8
	beq	a0,t4,.L44
.L24:
	lw	a1,0(a0)
	lw	s3,0(a6)
	srli	s4,a1,7
	andi	s4,s4,255
	andi	a2,a1,127
	or	a5,s4,a2
	beq	a5,zero,.L3
	srli	s5,s3,7
	andi	s5,s5,255
	andi	a3,s3,127
	or	a5,s5,a3
	beq	a5,zero,.L3
	xor	a1,a1,s3
	srli	a1,a1,15
	andi	s3,a1,1
	ori	a2,a2,128
	ori	a3,a3,128
	li	a1,0
.L4:
	andi	a5,a3,1
	neg	a5,a5
	and	a5,a5,a2
	add	a1,a1,a5
	slli	a2,a2,1
	srli	a3,a3,1
	bne	a3,zero,.L4
	add	s4,s4,s5
	slli	a5,a1,16
	bge	a5,zero,.L5
	srli	a1,a1,8
	andi	a1,a1,127
	addi	s4,s4,-126
.L6:
	slli	a5,s3,15
	blt	s4,zero,.L3
	ble	s4,t0,.L8
	mv	s4,t0
.L8:
	slli	s4,s4,7
	slli	a5,s3,15
	or	a5,a5,a1
	or	a5,s4,a5
.L3:
	srli	s4,a4,7
	andi	s4,s4,255
	andi	a3,a4,127
	or	a2,s4,a3
	beq	a2,zero,.L33
	srli	s3,a5,7
	andi	s3,s3,255
	andi	a2,a5,127
	or	a1,s3,a2
	beq	a1,zero,.L9
	srli	a1,a4,15
	srli	a5,a5,15
	slli	a3,a3,8
	or	a3,a3,t6
	slli	a2,a2,8
	or	a2,a2,t6
	sub	a4,s4,s3
	blt	a4,zero,.L10
	srl	a2,a2,a4
	ble	a4,s1,.L12
	li	a2,0
	beq	a1,a5,.L45
.L32:
	sub	a4,a3,a2
	j	.L15
.L44:
	add	a5,t2,t1
	sw	a4,0(a5)
	addi	t3,t3,1
	addi	t1,t1,4
	beq	t3,s0,.L25
.L27:
	mv	a6,t1
	mv	a0,t5
	li	a4,0
	j	.L24
.L25:
	addi	t5,t5,8
	addi	t4,t4,8
	beq	t5,s2,.L26
.L2:
	li	t1,16
	li	t3,0
	add	t2,t5,t1
	j	.L27
.L26:
	li	a5,-559038464
	addi	a5,a5,-273
	sw	a5,64(zero)
	li	a5,0
 #APP
# 155 "risc_code.c" 1
	.insn r 0x0b, 0, 0, x0, a5, x0
# 0 "" 2
 #NO_APP
	li	a5,16
 #APP
# 156 "risc_code.c" 1
	.insn r 0x0b, 1, 0, x0, a5, x0
# 0 "" 2
 #NO_APP
	li	a5,48
 #APP
# 157 "risc_code.c" 1
	.insn r 0x0b, 3, 0, x0, a5, x0
# 0 "" 2
 #NO_APP
	li	a5,-889274368
	addi	a5,a5,-1106
	sw	a5,68(zero)
.L28:
 #APP
# 162 "risc_code.c" 1
	nop
# 0 "" 2
 #NO_APP
	j	.L28
.L46:
	mv	a5,s4
	srli	a4,a4,8
	andi	a4,a4,127
	j	.L29
.L18:
	li	a2,32768
	li	a5,0
	mv	a3,a2
	bgeu	a4,a2,.L46
.L21:
	slli	a4,a4,1
	addi	a5,a5,-1
	bltu	a4,a3,.L21
	j	.L20
.L13:
	beq	a1,a5,.L36
	mv	s4,s3
	li	a3,0
	j	.L16
	.size	_start, .-_start
	.ident	"GCC: (14.2.0+19) 14.2.0"
	.section	.note.GNU-stack,"",@progbits
