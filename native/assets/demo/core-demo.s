	section	text
	xdef	_start

_start:
	lea	banner(pc),a0
	bsr	puts
	moveq	#0,d6
	moveq	#1,d7
	moveq	#2,d5

animate:
	moveq	#2,d4
wait_frames:
	move.w	#37,-(sp)
	trap	#14
	addq.l	#2,sp
	dbra	d4,wait_frames

	lea	erase_star(pc),a0
	move.b	d6,d0
	add.b	#42,d0
	move.b	d0,3(a0)
	bsr	puts

	add.w	d7,d6
	cmp.w	#50,d6
	blt.s	check_left
	moveq	#50,d6
	moveq	#-1,d7
check_left:
	tst.w	d6
	bge.s	draw_star
	moveq	#0,d6
	moveq	#1,d7

draw_star:
	addq.w	#1,d5
	cmp.w	#8,d5
	blt.s	colour_ready
	moveq	#2,d5
colour_ready:
	lea	show_star(pc),a0
	move.b	d5,2(a0)
	move.b	d6,d0
	add.b	#42,d0
	move.b	d0,7(a0)
	bsr	puts

	move.w	#11,-(sp)
	trap	#1
	addq.l	#2,sp
	tst.l	d0
	beq.s	animate

	move.w	#7,-(sp)
	trap	#1
	addq.l	#2,sp
	lea	goodbye(pc),a0
	bsr	puts
	move.w	#0,-(sp)
	trap	#1

puts:
	pea	(a0)
	move.w	#9,-(sp)
	trap	#1
	addq.l	#6,sp
	rts

banner:
	dc.b	$1b,"E",$1b,"f",$1b,"b",7
	dc.b	13,10,"+------------------------------------------------------------+"
	dc.b	13,10,"|                  RETRO-ATARIST CORE DEMO                  |"
	dc.b	13,10,"+------------------------------------------------------------+"
	dc.b	13,10,13,10,$1b,"b",3,"  EmuTOS boot ROM             OK"
	dc.b	13,10,$1b,"b",4,"  Hatari 68000 CPU core        RUNNING"
	dc.b	13,10,$1b,"b",5,"  Native framebuffer video     RUNNING"
	dc.b	13,10,$1b,"b",6,"  Keyboard input               WAITING"
	dc.b	13,10,13,10,$1b,"b",7,"  The moving marker below confirms CPU and frame timing."
	dc.b	13,10,13,10,"          ",0
erase_star:
	dc.b	$1b,"Y",43,42," ",0
show_star:
	dc.b	$1b,"b",2,$1b,"Y",43,42,"*",0
goodbye:
	dc.b	$1b,"b",7,$1b,"Y",46,32,"Input received. Returning to the EmuTOS desktop...",13,10,$1b,"e",0
