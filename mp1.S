
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		pushl %ebp
		movl %esp, %ebp

		pushl %ebx
		pushl %edi # previous node
		pushl %edx
		pushl %esi
		movl $mp1_missile_list, %ebx # get the ptr to first element of linked list of missiles
		movl %ebx, %edi
		movl (%ebx), %ebx # dereference the pointer to get first missile
missile_iteration:
		cmpl $0, %ebx # check if null
		je finished

		# call update_missiles, function to process missiles
		pushl %ebx
		pushl %edi
		call update_missiles
		addl $8, %esp

		movl %ebx, %edi # update previous missile
		movl NEXT(%ebx), %ebx # go to next missile
		jmp missile_iteration

finished:
		# finished processing, redraw cities
		movl $3, %ebx # counter to which base we are currently on
		movl $0, %ecx # width counter

		# check if city is destroyed or not
		movl $base_alive, %edx
		movl (%edx), %edx

base_loop:		
		sarl $8, %edx # shift right to remove padding byte
		cmpb $0, %dl
		je alive_base
		jmp dead_base

alive_base:
		movl $base_pic, %esi
		jmp draw_base

dead_base:
		movl $dead_base_pic, %esi

# now the base we want to draw is in %esi
draw_base:
		movl (%esi), %esi
		# now we need to find the location
		# third city is (58, 24) to (62, 24)
		# second city is (38, 24) to (42, 24)
		# first city is (18, 24) to (22, 24)
		movl $80, %eax
		imull $60, %ebx, %eax
		imull $2, %eax
		addl $48, %eax
		subl $2, %eax
		# %eax is at the starting location

		movl %esi, %ecx # move base picture to %cl
		pushl %eax
		call mp1_poke
		addl $4, %esp

		addl $1, %ecx
		subl $1, %ebx
		cmpl %ecx, $4
		je done_city

done_city:
		cmpl $0, %ebx
		je done_drawing
		subl $16, %eax
		jmp base_loop

done_drawing:



		popl %esi
		popl %edx
		popl %edi
		popl %ebx
		leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		ret


# ----------------- Functions private to this file -------------------

# inputs - previous node, current node
update_missiles:
		pushl %ebp
		movl %esp, %ebp
		pushl %ecx
		pushl %esi
		pushl %edx
		pushl %ebx
		pushl %edi

		movl 8(%ebp), %edi # store previous node in %edi
		movl 12(%ebp), %ebx # store current node in %ebx
		
		# check if exploding
		movl EXPLODED(%ebx), %edx
		cmpl $0, %edx
		jne exploding

not_exploding:
		# store old location
		movl X(%ebx), %ecx
		movl Y(%ebx), %eax

		# erase missile at old location
		imull $80, %ecx, %ecx
		imull $2, %ecx, %ecx

		imull $15, %eax, %eax
		imull $2, %eax, %eax

		addl %ecx, %eax # now the old byte location is stored in %eax

		# draw a space character to remove the missile
		movb $0x20, %cl
		pushl %eax
		pushb
		call mp1_poke
		addl $4, %esp

		# update position
		movl VX(%ebx), %edx
		movl VY(%ebx), %esi
		addl %edx, X(%ebx)
		addl %esi, Y(%ebx)

processing:
		# check if out of bounds
		movl X(%ebx), %edx
		movl Y(%ebx), %esi
		sarl $16, %edx
		sarl $16, %esi
		cmpl $0, %edx
		jl out_of_bounds
		cmpl $0, %esi
		jl out_of_bounds
		cmpl $79, %edx
		jg out_of_bounds
		cmpl $24, %esi
		jg out_of_bounds
		jmp in_bounds

out_of_bounds:
		pushl %ebx
		pushl %edi
		call mp1_missile_remove
		addl $8, %esp
		jmp finished_processing

in_bounds:
		# check if missile has reached destination
		movl X(%ebx), %edx
		movl Y(%ebx), %esi
		sarl $16, %edx
		sarl $16, %esi # get the location of x and y
		cmpl %edx, DEST_X(%ebx)
		jne simply_moving
		cmpl %esi, DEST_Y(%esi)
		jne simply_moving

exploding:
		# need to caller-save %ecx and %edx
		pushl %ecx
		pushl %edx

		pushl %edi
		call missile_explode
		addl $12, %esp

		cmpl %eax, $0
		je continue
		# call mp1_notify_user
		pushl %ecx
		pushl %edx
		pushl %eax
		call mp1_notify_user
		addl $12, %esp

continue:
		# decrement exploded field for the missile
		subl $1, EXPLODED(%ebx)
		cmpl $0, EXPLODED(%ebx)
		je finished_exploding
		
		# still exploding, draw to screen
		movl X(%ebx), %edx
		movl Y(%ebx), %esi

		imull $80, %edx, %edx
		imull $2, %edx, %edx

		imull $15, %esi, %esi
		imull $2, %esi, %esi

		addl %edx, %esi
		movl %esi, %eax # now the new byte location is stored in %eax

		# draw missile at new location
		movb EXPLOSION(%ebx), %cl
		pushl %eax
		call mp1_poke
		addl $4, %esp
		jmp finished_processing

finished_exploding: # finished exploding, remove missile from list
		pushl %ebx
		pushl %edi
		call mp1_missile_remove
		addl $8, %esp
		jmp finished_processing

simply_moving:
		# draw it in the new location (new location is x: %edx, y: %esi)
		imull $80, %edx, %edx
		imull $2, %edx, %edx

		imull $15, %esi, %esi
		imull $2, %esi, %esi

		addl %edx, %esi
		movl %esi, %eax # now the new byte location is stored in %eax

		# draw missile at new location
		movb C(%ebx), %cl
		pushl %eax
		call mp1_poke
		addl $4, %esp
		jmp finished_processing

finished_processing:
		popl %edi
		popl %ebx
		popl %edx
		popl %esi
		popl %ecx
		leave
		ret

# input - previous missile node, current missile node
# remove missile from linked list, and free from memory
mp1_missile_remove:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edx
		movl 12(%ebp), %ebx # store current node in %edx
		movl 8(%ebp), %esi # store previous node in %esi
		movl NEXT(%ebx), %edx # store next node in %ebx

		# set the previous node->next to the next of current node
		movl %edx, NEXT(%esi)

		# free current node
		pushl %ecx
		pushl %edx
		pushl %eax

		pushl %ebx
		call mp1_free
		addl $16, %esp

		popl %edx
		popl %esi
		popl %ebx

		leave
		ret


mp1_ioctl_startgame:
		ret

mp1_ioctl_addmissile:
		ret

mp1_ioctl_movexhairs:
		ret

mp1_ioctl_getstatus:
		ret

mp1_ioctl_endgame:
		ret
