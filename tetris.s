.equ pcolor 0x0000ff        # colour used to draw the pieces (blue)

.data
pos: .word 0 , 0 , 0 , 0     # scratch buffer holding the piece's 4 addresses, filled in by the load_* routines
base: .word LED_MATRIX_0_BASE
width: .word LED_MATRIX_0_WIDTH
height: .word LED_MATRIX_0_HEIGHT
right: .word D_PAD_0_RIGHT
up: .word D_PAD_0_UP
down: .word D_PAD_0_DOWN
left: .word D_PAD_0_LEFT
seed: .word 12349908          # seed of the pseudo-random number generator (xorshift)

.text
setup: 
    j main_loop


# main: the piece has landed -> clear full lines, drop the rows above, spawn a new piece
main:
call verify_and_delete        # a0 = 1 if at least one line was cleared
beqz a0  main_loop             # nothing cleared -> straight on to the next piece
call move_lines                 # lines were cleared -> make the ones above fall into the gaps

# main_loop: spawn a new piece of a random type at the top of the board
main_loop: 
li s1 LED_MATRIX_0_HEIGHT     # s1 = board height (constant for the whole game)
li s2 LED_MATRIX_0_WIDTH      # s2 = board width (constant for the whole game)

la x5 seed                     # xorshift32 generator, used to pick the piece type
lw x6 0(x5)
slli x7 x6 13 
xor x6 x6 x7 
srli x7 x6 17
xor x6 x7 x6 
sw x6 0(x5)                    # update the seed for the next spawn

li x5 4
rem x6 x6 x5                   # x6 = random number between 0 and 3
mv s8 x6                       # s8 = current piece type (0=rect, 1=cube, 2=z, 3=t)
li s9 0                        # s9 = rotation flag for the current piece (0=normal, 1=already rotated)
li x5 1
beq s8 x5 cube 
li x5 2
beq s8 x5 z
li x5 3
beq s8 x5 t 

rect: call load_rect            # no beq fired -> type 0 (rect); compute and draw the 4 initial cells
j load_positions
cube: call load_cube
j load_positions
z: call load_z
j load_positions
t: call load_t
j load_positions

# load_positions: copy the 4 addresses left in "pos" into s4..s7 (the active piece's registers)
load_positions:
la s0 pos
add s3 x0 a0                  # s3 = rows travelled during the fall, initialised by load_*
lwu s4 0(s0)
addi s0 s0 4
lwu s5 0(s0)
addi s0 s0 4
lwu s6 0(s0)
addi s0 s0 4
lwu s7 0(s0)

# fall: the falling loop; try to drop one row, and if it cannot, lock the piece in "main"
fall:
addi s3 s3 1
beq s1 s3 main                 # reached the bottom of the board -> lock the piece

slli s2 s2 2                    # s2 goes from "number of columns" to "bytes per row" (stride)

# check that the cell directly below each of the 4 cells is free (ignoring the piece's own cells)
p1:add x6 s4 s2
beq x6 s5 p2 
beq x6 s6 p2
beq x6 s7 p2 
lw x6 0(x6)
bnez x6 main                   # cell occupied -> cannot fall, lock the piece

p2:add x6 s5 s2
beq x6 s6 p3
beq x6 s7 p3
beq x6 s4 p3
lw x6 0(x6)
bnez x6 main

p3:add x6 s6 s2
beq x6 s5 p4 
beq x6 s4 p4
beq x6 s7 p4
lw x6 0(x6)
bnez x6 main

p4:add x6 s7 s2
beq x6 s5 p5
beq x6 s6 p5
beq x6 s4 p5
lw x6 0(x6)
bnez x6 main

p5:mv x5 s2                    # x5 = offset to apply in "draw" (one row down)
srli s2 s2 2                     # restore s2 to its original value (number of columns)

# draw: apply offset x5 to the piece's 4 cells, erase the old position and draw the new one
draw:
call clear                      # erase the 4 cells at the current position

add s6 s6 x5
add s7 s7 x5
add s5 s5 x5
add s4 s4 x5

call update                     # draw the 4 cells at the new position

# u: read the UP button -> request a clockwise rotation (rect_up/z_up/t_up); s9 prevents rotating twice in a row
u:
li x6 D_PAD_0_UP
lwu x6 0(x6)
beqz x6 d                       # UP not pressed -> go on to check DOWN
bnez s9 fall                    # already rotated -> ignore the new rotation request
addi x6 s8 -1 
beqz x6 fall                    # piece = cube -> does not rotate, just keeps falling
addi x6 s8 -2
beqz x6 z_up 
addi x6 s8 -3 
beqz x6  t_up

rect_up:                        # s8==0 (rect); none of the beqz above fired
   slli s2 s2 2                  # s2 -> stride in bytes
   li x7 LED_MATRIX_0_BASE
   mv x6 s4
   sub x6 x6 x7
   srli x6 x6 2 
   div x6 x6 s1                  # x6 = current row of s4: (address - base) / 4 / width
   addi x6 x6 4                  # check that there is room for 4 cells below
   bge x6 s1 fall                # no room (bottom of the board) -> do not rotate

   add x6 s4 s2                  # check that the 3 cells below s4 (the future vertical bar) are free
   lw x7 0(x6)
   bnez x7 fall
   
   add x6 x6 s2 
   lw x7 0(x6)
   bnez x7 fall
   
   add x6 x6 s2 
   lw x7 0(x6)
   bnez x7 fall
   
   add x6 x6 s2 
   lw x7 0(x6)
   bnez x7 fall
   
   addi s3 s3 3                  # the piece "drops" 3 rows as far as the fall counter is concerned
   li s9 1                        # mark as rotated

   call clear                     # erase the old horizontal bar
   add s5 s4  s2                  # rebuild as a vertical bar anchored at s4 (which stays put)
   add s6 s5 s2 
   add s7 s6 s2 
   call update                    # draw the vertical bar

   srli s2 s2 2                    # restore s2 to its original value
   j fall
   
z_up:
   addi x6 s1 -2                  # only rotate if there are at least 2 free rows below
   bge s3 x6 fall
   slli s2 s2 2
   li x7 LED_MATRIX_0_BASE
   
   add x6 s4  s2                  # check that the 2 cells below s4 (same column) are free
   lw x7 0(x6)
   bnez x7 fall
   
   add x6 x6 s2 
   lw x7 0(x6)
   bnez x7 fall
   
   addi s3 s3 1
   li s9 1

   call clear                     # erase the old horizontal shape
   add s4 s4 s2                    # anchor s4 moves down one row
   mv s7 s6                        # the old s6 becomes s7 (it stays in the same cell)
   add s6 s4 s2                    # new s6 = one row below the new s4
   call update                     # draw the vertical shape

   srli s2 s2 2 
   j fall
   
t_up:
   beqz s3 fall                    # already at the top -> no room to rotate
   slli s2 s2 2
   li x7 LED_MATRIX_0_BASE
   sub x6 s6 s2 
   sub x6 x6 s2                    # x6 = 2 rows above s6
   lw x7 0(x6)
   bnez x7 fall                    # cell occupied -> do not rotate
   
   addi s3 s3 -1
   li s9 1

   sw x0 0(s6)                      # erase only cell s6 (the other 3 do not move)
   mv s6 x6                          # s6 moves to the new cell (2 rows above)
   call update

   srli s2 s2 2 
   j fall

# d: read the DOWN button -> request a counter-clockwise rotation, undoing exactly what "u:" did
d:
li x6 D_PAD_0_DOWN
lwu x6 0(x6)
beqz x6 r                        # DOWN not pressed -> go on to check RIGHT
beqz s9 fall                     # the piece is already in its normal orientation -> nothing to undo
addi x6 s8 -1 
beqz x6 fall                     # the cube does not rotate
addi x6 s8 -2
beqz x6 z_down
addi x6 s8 -3 
beqz x6  t_down

rect_down:
   li x7 LED_MATRIX_0_BASE        # work out which half of the board s4 is in, to find the left corner again
   mv x6 s4
   sub x6 x6 x7
   srli x6 x6 2
   rem x7 x6 s2
   srli x5 s2 1
   mv x6 s4 
   blt x7 x5 rect_down_ver
   addi x6 x6 -16                  # adjust if the column falls in the right half
  
 rect_down_ver:
   slli s2 s2 2
   mv x5 x6                         # x5 holds the address that will become the new s4

   lw x7 0(x6)                       # check that the 4 cells of the future horizontal bar are free (ignoring s4)
   beq x6 s4 rdv2
   bnez x7 fall
   
 rdv2: 
   addi x6 x6 4
   lw x7 0(x6)
   bnez x7 fall
   
   addi x6 x6 4 
   lw x7 0(x6)
   bnez x7 fall
   
   addi x6 x6 4 
   lw x7 0(x6)
   bnez x7 fall
  
   addi s3 s3 -3                   # undo the "s3 += 3" done in rect_up
   li s9 0                          # back to the normal orientation

   call clear                       # erase the vertical bar
   mv s4 x5                         # new anchor = the left corner computed above
   addi s5 s4 4
   addi s6 s5 4
   addi s7 s6 4
   call update                      # draw the horizontal bar

   srli s2 s2 2 
   j fall

z_down:
   slli s2 s2 2
   li x7 LED_MATRIX_0_BASE
   
   sub x6 s4  s2                    # check that the cell above s4 and the one right of s7 are free
   lw x7 0(x6)
   bnez x7 fall
   
   addi x6 s7 4
   lw x7 0(x6)
   bnez x7 fall
   
   addi s3 s3 -1                   # undo the "s3 += 1" done in z_up
   li s9 0

   call clear                       # erase the vertical shape
   sub s4 s4  s2                     # anchor moves up one row (original position)
   mv s6 s7                          # the old s7 becomes s6 again
   addi s7 s6 4                       # new s7 = one column to the right of s6
   call update                       # draw the horizontal shape

   srli s2 s2 2 
   j fall
   
t_down:
   addi x6 s1 -2                    # only undo if there is room to move s6 down two rows
   bge s3 x6 fall
   slli s2 s2 2
   li x7 LED_MATRIX_0_BASE
   
   add x6 s6 s2 
   add x6 x6 s2                     # x6 = 2 rows below s6
   lw x7 0(x6)
   bnez x7 fall
   
   addi s3 s3 1
   li s9 0

   sw x0 0(s6)                       # erase only cell s6
   mv s6 x6                           # s6 moves to the cell 2 rows below
   call update

   srli s2 s2 2 
   j fall


# clear / update: erase and draw the piece's 4 current cells (s4..s7); reused throughout
clear:
    sw x0 0(s4)
    sw x0 0(s5)
    sw x0 0(s6)
    sw x0 0(s7)
    ret
update: 
    li x6 pcolor
    sw x6 0(s7)
    sw x6 0(s4)
    sw x6 0(s5)
    sw x6 0(s6)
    ret

# r: read the RIGHT button -> try to move the piece one column right, checking collisions and the right edge
r:
li x6 D_PAD_0_RIGHT
lwu x6 0(x6)
beqz x6 l                        # RIGHT not pressed -> go on to check LEFT

r1:mv x6 s4                       # check that the cell to the right of each of the 4 cells is free (ignoring the piece's own cells)
addi x6 x6 4
beq x6 s5 r2
beq x6 s6 r2
beq x6 s7 r2
lw x6 0(x6)
bnez x6 fall                     # occupied -> ignore the move, just fall

r2:mv x6 s5 
addi x6 x6 4
beq x6 s4 r3
beq x6 s6 r3 
beq x6 s7 r3
lw x6 0(x6)
bnez x6 fall

r3:mv x6 s6 
addi x6 x6 4
beq x6 s5 r4
beq x6 s4 r4
beq x6 s7 r4
lw x6 0(x6)
bnez x6 fall

r4:mv x6 s7
addi x6 x6 4
beq x6 s5 r_border_ver
beq x6 s6 r_border_ver
beq x6 s4 r_border_ver
lw x6 0(x6)
bnez x6 fall

li x7 LED_MATRIX_0_BASE

r_border_ver:                     # check whether s6/s7 are already in the last column (stops the piece wrapping around the row)
mv x6 s6
sub x6 x6 x7
srli x6 x6 2
rem x8 x6 s2
addi x5 s2 -1 
bge x8 x5 fall


mv x6 s7
sub x6 x6 x7
srli x6 x6 2
rem x8 x6 s2
addi x5 s2 -1 
bge x8 x5 fall

li x5 4                          # x5 = offset of +1 column, used by "draw"

j draw

# l: read the LEFT button -> same as "r:" but to the left
l:
li x6 D_PAD_0_LEFT
lwu x6 0(x6)
beqz x6 fall                     # LEFT not pressed -> end of the checks, just fall

li x7 LED_MATRIX_0_BASE

l1:mv x6 s4 
addi x6 x6 -4
beq x6 s5 l2
beq x6 s6 l2
beq x6 s7 l2
lw x6 0(x6)
bnez x6 fall

l2:mv x6 s5
addi x6 x6 -4
beq x6 s4 l3
beq x6 s6 l3
beq x6 s7 l3
lw x6 0(x6)
bnez x6 fall

l3:mv x6 s6
addi x6 x6 -4
beq x6 s5 l4
beq x6 s4 l4
beq x6 s7 l4
lw x6 0(x6)
bnez x6 fall

l4:mv x6 s7
addi x6 x6 4
beq x6 s5 l_border_ver
beq x6 s6 l_border_ver
beq x6 s4 l_border_ver
lw x6 0(x6)
bnez x6 fall

l_border_ver:                     # check whether s4 is already in the first column (column 0)
mv x6 s4
sub x6 x6 x7
srli x6 x6 2
rem x8 x6 s2
beqz x8 fall

li x5 -4                          # x5 = offset of -1 column, used by "draw"
j draw

end: j end

# load_rect/load_cube/load_z/load_t: build each piece's initial shape at the top centre of the board and leave the addresses in "pos"
load_rect:
la x5 pos

li x6 LED_MATRIX_0_BASE
li x28 pcolor

li x7 LED_MATRIX_0_WIDTH          # compute the column at the middle of the board (minus a small offset)
srli x7 x7 1
addi x7 x7 -2
slli x7 x7 2

add x6 x7 x6                      # x6 = address of the first cell (row 0, middle column - 2)
sw x28 0(x6)                       # draw
sw x6 0(x5)                        # store the address in pos[0]
addi x5 x5 4

addi x6 x6 4                       # advance one column
sw x28 0(x6)
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)
sw x6 0(x5)

li a0 0                            # returns 0 = starting fall row (counter s3)
ret

load_cube:
la x5 pos

li x6 LED_MATRIX_0_BASE
li x28 pcolor

li x7 LED_MATRIX_0_WIDTH
srli x7 x7 1
addi x7 x7 -2
slli x7 x7 2

add x6 x7 x6
sw x28 0(x6)                       # cell (0,0) of the square
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)                       # cell (0,1)
sw x6 0(x5)
addi x5 x5 4

slli x7 s2 2                        # x7 = stride of one row (s2 is the width in columns here)
add x6 x7 x6
addi x6 x6 -4
sw x28 0(x6)                       # cell (1,0)
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)                       # cell (1,1)
sw x6 0(x5)

li a0 1
ret

load_z:
la x5 pos

li x6 LED_MATRIX_0_BASE
li x28 pcolor

li x7 LED_MATRIX_0_WIDTH
srli x7 x7 1
addi x7 x7 -2
slli x7 x7 2

add x6 x7 x6
sw x28 0(x6)                       # cell (0,0)
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)                       # cell (0,1)
sw x6 0(x5)
addi x5 x5 4

slli x7 s2 2 
add x6 x7 x6
sw x28 0(x6)                       # cell (1,1)
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)                       # cell (1,2)
sw x6 0(x5)

li a0 1
ret

load_t:
la x5 pos

li x6 LED_MATRIX_0_BASE
li x28 pcolor

li x7 LED_MATRIX_0_WIDTH
srli x7 x7 1
addi x7 x7 -2
slli x7 x7 2

add x6 x7 x6
sw x28 0(x6)                       # cell (0,0)
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sw x28 0(x6)                       # cell (0,1)
sw x6 0(x5)
addi x5 x5 4

slli x7 s2 2 
add x6 x7 x6
sw x28 0(x6)                       # cell (1,1) - the stem of the T
sw x6 0(x5)
addi x5 x5 4

addi x6 x6 4
sub x6 x6 x7
sw x28 0(x6)                       # cell (0,2)
sw x6 0(x5)

li a0 1
ret
    
# fill: paints half the board in the piece colour (used for testing/debugging)
fill:
    mul x5 s1 s2 
    srli x6 x5 1 
    addi x6 x6 -1
    slli x5 x5 2 
    addi x5 x5 -4 
    li x7 LED_MATRIX_0_BASE
    add x5 x7 x5 
    li x7 pcolor 
    fill_loop:
        sw x7 0(x5) 
        addi x5 x5 -4
        addi x6 x6 -1 
        bgtz x6 fill_loop
    ret

# reset: clears (blacks out) every cell of the board
reset:
li x6 LED_MATRIX_0_WIDTH
li x7 LED_MATRIX_0_HEIGHT
mul x6 x6 x7
li x7 LED_MATRIX_0_BASE
loop:
sw x0 0(x7)
addi x7 x7 4
addi x6 x6 -1
bgtz x6 loop
ret
    
# verify_and_delete: scan the board bottom-up, clear complete rows, return a0=1 if any were cleared
verify_and_delete:
    mul x5 s1 s2 
    slli x5 x5 2 
    addi x5 x5 -4 
    li x7 LED_MATRIX_0_BASE
    add x5 x7 x5                   # x5 = address of the last cell (bottom-right corner)
    li x6 0                         # x6 = filled-cell counter for the current row
    li a0 0                         # a0 = "cleared a line" flag
    li x7 0                          # x7 = number of rows visited so far
    
    ver_loop:
        beq x7 s1 ver_ret            # all rows visited -> done
        lw x28 0(x5)
        beqz x28 ver_jump_line       # empty cell -> row is not complete, skip to the next one
        addi x6 x6 1 
        addi x5 x5 -4 
        beq x6 s2 destroy_lines      # counted "width" filled cells -> the row is complete
        j ver_loop
        
    ver_jump_line:
        slli x6 x6 2 
        add x5 x5 x6                 # walk to the start of the current row, then step back to the last cell of the previous row
        slli x6 s2 2 
        sub x5 x5 x6 
        addi x7 x7 1 
        li x6 0
        j ver_loop
           
    destroy_lines:
        addi x5 x5 4                  # back to the start of the completed row
        destroy_loop:
            sw x0 0(x5)                # erase the cell
            addi x5 x5 4 
            addi x6 x6 -1
            bgtz  x6 destroy_loop
         addi x5 x5 -4 
         li a0 1                        # record that at least one line was cleared
         j ver_loop
        
    ver_ret:ret
    
# move_lines: after a line is cleared, make the non-empty rows above the gap fall into it
move_lines:
    mul x5 s1 s2 
    slli x5 x5 2 
    addi x5 x5 -4 
    li x7 LED_MATRIX_0_BASE
    add x5 x7 x5                    # x5 = last cell of the board
    li x6 0                          # x6 = cell counter for the current row
    li x7 0                           # x7 = number of rows visited
    
    move_loop:
        beq x7 s1 move_ret            # everything visited -> done
        lw x28 0(x5)
        bnez x28 move_jump_line        # cell filled -> not a gap, move on to the next row
        addi x6 x6 1 
        addi x5 x5 -4 
        beq x6 s2 fix_line              # the whole row is empty -> found the gap, go and fill it
        j  move_loop
        
    move_jump_line:
        slli x6 x6 2 
        add x5 x5 x6 
        slli x6 s2 2 
        sub x5 x5 x6  
        addi x7 x7 1 
        li x6 0
        j move_loop
    
    fix_line:
        slli x6 x6 2                    # x28 scans the rows above the gap looking for a non-empty one
        add x5 x5 x6 
        slli x6 s2 2 
        sub x28 x5 x6 
        li x6 0 
        li x31 0                        # x31 = "a row has already been moved" flag
        
       move_ver_loop:
            lw x29 0(x28)
            bnez x29 transfer             # found a filled cell -> move this row down
            addi x6 x6 1 
            addi x28 x28 -4
            blt x6 s2 move_ver_loop
            li x6 0
            addi x7 x7 1 
            bgtz x31 move_ret               # a row was already moved -> this pass is done
            bne x7 s1 move_ver_loop
            j move_ret
                  
        transfer:
            slli x6 x6 2                     # copy the row found (x28) into the gap (x5), cell by cell, and clear the original
            add x28 x28 x6 
            
            mv x6 s2
            transfer_loop:
                lw x29 0(x28)
                sw x29 0(x5)
                sw x0 0(x28)
                addi x6 x6 -1 
                addi x28 x28 -4
                addi x5 x5 -4 
                bgtz x6 transfer_loop 
                li x6 0 
                addi x7 x7 1 
                li x31 1                       # record that a row has been moved
                j move_ver_loop
                
            
            
            
        
    move_ret: ret