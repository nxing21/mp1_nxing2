
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

		pushl %ebx # callee-saved registers
		pushl %edi
		pushl %esi
		
		# call the three functions that are used in tasklet
		pushl %eax # caller-saved registers
		pushl %ecx
		pushl %edx
		call update_missiles
		call draw_cities
		call redraw_crosshairs
		popl %edx
		popl %ecx
		popl %eax

done_tasklet:
		popl %esi
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
		# check if valid
		movl 8(%esp), %eax
		cmpl $0, %eax
		jl invalid
		cmpl $4, %eax
		jg invalid
		jmp *jump_table(,%eax,4)

invalid:
		movl $-1, %eax
		ret

jump_table:
		.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------
draw_cities:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		# finished processing missiles, redraw cities
		movl $1, %ebx # counter to which base we are currently on

		# check if city is destroyed or not
		movl base_alive, %edx

base_loop:		
		movl $0, %edi # set/reset width counter
		cmpb $0, %dl # check if dead or alive city
		je dead_base

alive_base:
		movl $base_pic, %esi
		jmp draw_base

dead_base:
		movl $dead_base_pic, %esi
		# now the base we want to draw is in %esi

draw_base:
		# now we need to find the location
		# first city is (18, 24) to (22, 24)
		# second city is (38, 24) to (42, 24)
		# third city is (58, 24) to (62, 24)
		# %eax = 24 * 80 * 2 + 2 * x_location
		# initialize %eax to its starting location for that city using above formula
		movl %ebx, %eax
		imull $20, %eax # get to the center x value (either 20, 40, or 60)
		subl $2, %eax # now eax is at the row location
		addl $1920, %eax # + 24 * 80
		imull $2, %eax # multiply by 2
		# %eax is at the starting location

city_loop:
		movl (%esi), %ecx # move base picture to %cl
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx

		# update counters
		addl $1, %edi
		cmpl $5, %edi # check if we are done with the current city (width of 5)
		je done_city
		addl $2, %eax
		addl $1, %esi
		jmp city_loop

done_city:
		addl $1, %ebx
		rorl $8, %edx
		cmpl $4, %ebx # check if we are done with all cities
		jne base_loop

		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

redraw_crosshairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		# draw the crosshair
		movl crosshairs_y, %edx
		movl crosshairs_x, %esi 

		imull $160, %edx # 2 * 80 * y
		imull $2, %esi # + 2 * x

		addl %edx, %esi
		movl %esi, %eax # now the byte location of crosshair is stored in %eax

		# draw '+' at crosshair location
		movb $0x2B, %cl
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx

		# callee-saved registers
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# inputs - previous node, current node
update_missiles:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx # callee-saved registers
		pushl %esi
		pushl %edi

		movl mp1_missile_list, %ebx # get the first element of linked list of missiles
		movl $mp1_missile_list, %edi # use %edi to keep track of previous node
		xorl %esi, %esi # flag for notify_user
missile_iteration:
		cmpl $0, %ebx # check if null
		je finished_list

		# store old location
		movl Y(%ebx), %edx
		movl X(%ebx), %eax
		shrl $16, %edx
		shrl $16, %eax

		# erase missile at old location
		imull $160, %edx
		imull $2, %eax

		addl %edx, %eax # now the old byte location is stored in %eax

		# draw a space character to remove the missile
		movl $0x20, %ecx
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx
		
		# check if exploding
		movl EXPLODED(%ebx), %edx
		cmpl $0, %edx
		je not_exploding
		jmp exploding

not_exploding:
		# update position
		movl VX(%ebx), %edx
		movl VY(%ebx), %ecx
		addl %edx, X(%ebx)
		addl %ecx, Y(%ebx)

processing:
		# check if out of bounds
		movl X(%ebx), %edx
		movl Y(%ebx), %ecx
		shrl $16, %edx # right shift by 16 to access high 16 bits
		shrl $16, %ecx
		cmpl $0, %edx
		jl out_of_bounds
		cmpl $0, %ecx
		jl out_of_bounds
		cmpl $79, %edx
		jg out_of_bounds
		cmpl $24, %ecx
		jg out_of_bounds
		jmp in_bounds

out_of_bounds:
		# remove the missile from the list if out of bounds
		movl %ebx, %edx # store current node
		movl NEXT(%ebx), %ebx # go to next missile
		pushl %eax
		pushl %ecx
		pushl %edx

		pushl %edx # current node
		pushl %edi # previous node
		call mp1_missile_remove
		addl $8, %esp

		popl %edx
		popl %ecx
		popl %eax
		jmp missile_iteration # done processing current missile, loop back

in_bounds:
		# check if missile has reached destination
		movl Y(%ebx), %edx
		movl X(%ebx), %ecx
		shrl $16, %edx
		shrl $16, %ecx # get the location of x and y
		cmpl %edx, DEST_Y(%ebx)
		jne simply_moving
		cmpl %ecx, DEST_X(%ebx)
		jne simply_moving

exploding:
		# need to caller-save %ecx and %edx
		pushl %ecx
		pushl %edx

		pushl %ebx
		call missile_explode # call missile_explode for explosion
		popl %ebx

		popl %edx
		popl %ecx

		# need to call mp1_notify_user if the output is not 0, unless we already called
		cmpl $0, %eax
		je continue
		
		cmpl $0, %esi
		jne continue
		# call mp1_notify_user
		pushl %eax
		pushl %ecx
		pushl %edx
		call mp1_notify_user
		popl %edx
		popl %ecx
		popl %eax
		addl $1, %esi

continue:
		# decrement exploded field for the missile
		decl EXPLODED(%ebx)
		cmpl $0, EXPLODED(%ebx)
		je finished_exploding
		
		# still exploding, draw to screen
		movl Y(%ebx), %edx
		movl X(%ebx), %ecx
		shrl $16, %edx
		shrl $16, %ecx # get the location of x and y

		# find byte location, 80 * y * 2 + x * 2
		imull $160, %edx # 80 * 2 * y
		imull $2, %ecx # + 2 * x

		addl %edx, %ecx
		movl %ecx, %eax # now the new byte location is stored in %eax

		# draw missile at new location
		movb $EXPLOSION, %cl
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx
		jmp finished_processing

finished_exploding: # finished exploding, erase missile, and remove missile from list
		movl %ebx, %edx # store current node
		movl NEXT(%ebx), %ebx # go to next node
		pushl %eax # caller-saved registers
		pushl %ecx
		pushl %edx

		pushl %edx # current node
		pushl %edi # previous node
		call mp1_missile_remove
		addl $8, %esp

		popl %edx
		popl %ecx
		popl %eax
		jmp missile_iteration # done processing current missile, move to next one

simply_moving:
		# draw it in the new location (new location is x: %edx, y: %ecx)
		imull $160, %edx # 80 * 2 * y
		imull $2, %ecx # + 2 * x

		addl %edx, %ecx
		movl %ecx, %eax # now the new byte location is stored in %eax

		# draw missile at new location
		movb C(%ebx), %cl
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx

finished_processing:		
		movl %ebx, %edi # update previous missile
		movl NEXT(%ebx), %ebx # go to next missile
		jmp missile_iteration

finished_list:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# input - previous missile node, current missile node
# remove missile from linked list, and free from memory
mp1_missile_remove:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 12(%ebp), %ebx # store current node in %ebx
		movl 8(%ebp), %esi # store previous node in %esi
		movl NEXT(%ebx), %edx # store next node in %edx
		
		# check if current node is head
		# and if so, update mp1_missile_list
		cmpl %ebx, mp1_missile_list
		jne connect_nodes
		# we need to update the head node
		movl %edx, mp1_missile_list
		jmp free_node

connect_nodes:
		# set the previous node->next to the next node
		movl %edx, NEXT(%esi)	
free_node:
		# free current node
		# caller save %ecx, %edx, and %eax
		pushl %ecx
		pushl %edx
		pushl %eax

		pushl %ebx # current node
		call mp1_free
		addl $4, %esp

		popl %eax
		popl %edx
		popl %ecx

end_of_missile_remove:
		popl %edi
		popl %esi
		popl %ebx

		leave
		ret

# need to callee-save %ebx, %esi, and %edi for these
mp1_ioctl_startgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		# initialize variables used by driver,
		# and set crosshair to (40, 12)
		movl $12, crosshairs_y
		movl $40, crosshairs_x

		movl $0, mp1_score
		movl $0x00FFFFFF, base_alive # low 3 bytes are alive cities, highest bit is padding
		movl $0, mp1_missile_list

		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_addmissile:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl 8(%ebp), %ebx # load the missile into %ebx
		pushl %ecx
		pushl %edx
		# call mp1_malloc
		pushl $36
		call mp1_malloc
		addl $4, %esp
		popl %edx
		popl %ecx
		cmpl $0, %eax # failed, malloc returns null pointer
		je malloc_failed
		movl %eax, %edi # save this in %edi for later

		# will use the allocated space to copy from user to kernel
		pushl %ecx
		pushl %edx
		pushl $36 # need to allocate 36 bytes
		pushl %ebx # from %ebx (missile)
		pushl %eax # to %eax (newly allocated space)
		call mp1_copy_from_user
		addl $12, %esp
		popl %edx
		popl %ecx
		cmpl $0, %eax
		jne addmissile_failed

		# succeeded, so update the head pointer
		movl mp1_missile_list, %esi
		movl %esi, NEXT(%edi) # old head is the next value of our new node
		movl %edi, mp1_missile_list # set new head
		movl $0, %eax
		jmp return_addmissile

addmissile_failed: # free the memory that we allocated earlier
		pushl %eax # caller-saved registers
		pushl %ecx
		pushl %edx

		pushl %edi # free memory we just allocated
		call mp1_free
		popl %edi

		popl %edx
		popl %ecx
		popl %eax
malloc_failed: # malloc failed, so we do not need to free anything
		movl $-1, %eax

return_addmissile:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_movexhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		# erase old crosshair
		movl crosshairs_y, %edx
		movl crosshairs_x, %esi 

		imull $160, %edx # 80 * 2 * y
		imull $2, %esi # + 2 * x

		addl %edx, %esi
		movl %esi, %eax # now the byte location of crosshair is stored in %eax

		# draw space at crosshair location to erase it
		movb $0x20, %cl
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx

		movl 8(%ebp), %ebx # get the input (low 16 bits are x component, high 16 bits are y component)
		# reset original coordinates back
		movl crosshairs_y, %edx
		movl crosshairs_x, %esi
		addw %bx, %si # add to x coordinate
		shrl $16, %ebx
		addw %bx, %dx # add to y coordinate

		# first check x boundary
		cmpw $0, %si
		jge x_ge_zero
		movl $0, %esi # x is below zero, so set it to 0
		jmp check_y
x_ge_zero:
		cmpw $79, %si
		jle check_y
		movl $79, %esi # x is above 79, so set it to 79

check_y:
		cmpw $0, %dx
		jge y_ge_zero
		movl $0, %edx # y is below zero, so set it to 0
		jmp draw_new_crosshair
y_ge_zero:
		cmpw $24, %dx
		jle draw_new_crosshair
		movl $24, %edx # y is above 24, so set it to 24
		
draw_new_crosshair:
		# update values
		movl %edx, crosshairs_y
		movl %esi, crosshairs_x

		# then draw crosshair at the new location
		imull $160, %edx # 2 * 80 * y
		imull $2, %esi # + 2 * x

		addl %edx, %esi
		movl %esi, %eax # now the byte location of crosshair is stored in %eax

		# draw '+' at location
		movb $0x2B, %cl
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx

finished_movexhairs:
		movl $0, %eax # return 0 for success
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		xorl %ebx, %ebx
		movw mp1_score, %bx # move score into first 16 bits
		rorl $16, %ebx # rotate so we can edit 16th, 17th, and 18th bit

check_city_1:
		# checking city 1, add 1 to 1st bit if alive (will be rotated to 16th bit)
		movl base_alive, %edx
		cmpb $0, %dl
		je check_city_2
		addl $1, %ebx

check_city_2:
		# checking city 2, add 1 to 1st bit if alive (will be rotated to 17th bit)
		rorl $1, %ebx # rotate to edit 17th bit
		rorl $8, %edx
		cmpb $0, %dl
		je check_city_3
		addl $1, %ebx

check_city_3:
		# checking city 3, add 1 to 1st bit if alive (will be rotated to 18th bit)
		rorl $1, %ebx # rotate to edit 18th bit
		rorl $8, %edx
		cmpb $0, %dl
		je done_checking_cities
		addl $1, %ebx

done_checking_cities:
		rorl $14, %ebx # reset %ebx to correct rotation
		# send back to user from kernel
		pushl %ecx
		pushl %edx
		
		pushl $4 # allocate 4 bytes
		call mp1_malloc
		addl $4, %esp

		popl %edx
		popl %ecx
		movl %eax, %edi # save malloc space for later when we free
		movl %ebx, (%eax) # move %ebx into the newly allocated memory

		pushl %ecx
		pushl %edx
		pushl $4 # 4 bytes to be moved
		pushl %eax # from kernel
		pushl 8(%ebp) # to user
		call mp1_copy_to_user
		addl $12, %esp
		cmpl $0, %eax
		jne failed_copying

		xorl %eax, %eax # succeeded copying, return 0
		jmp return_status

failed_copying:
		movl $-1, %eax # failed copying, return -1

return_status:
		popl %edx # caller-saved registers from copy_to_user
		popl %ecx

		pushl %eax # caller-saved registers for mp1_free
		pushl %ecx
		pushl %edx

		pushl %edi # free memory we just allocated
		call mp1_free
		addl $4, %esp

		popl %edx
		popl %ecx
		popl %eax
	
		# callee-saved registers
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_endgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl mp1_missile_list, %ebx # current node
		movl $mp1_missile_list, %edi # previous node
endgame_loop:
		# iterate through linked list and free all nodes
		
		cmpl $0, %ebx # check if we cleared everything
		je fully_cleared

		movl %ebx, %edx # store current node
		movl NEXT(%ebx), %ebx

		# free the current node
		pushl %ecx
		pushl %edx
		pushl %eax

		pushl %edx # current node
		pushl %edi # previous node
		call mp1_missile_remove
		addl $8, %esp

		popl %eax
		popl %edx
		popl %ecx
		jmp endgame_loop

fully_cleared:
		xorl %eax, %eax # return 0
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret
