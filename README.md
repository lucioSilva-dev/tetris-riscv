# Tetris in RISC-V Assembly

A playable Tetris written directly in RISC-V assembly, driving a memory-mapped
LED matrix and reading a physical d-pad. No operating system, no standard
library, no heap — 726 lines, 32 registers, and a block of memory that is
simultaneously the game state and the screen.

```
        ████            ██                  the board is the framebuffer:
        ██              ██████              there is no separate model of
      ████                ██                the game to keep in sync
```

## The central idea: the screen is the board

There is no array holding the game state. The LED matrix *is* the state.

Each cell of the matrix is one word in memory, and its value is its colour —
`0x000000` for empty, `0x0000ff` for a filled block. So the two questions the
game constantly asks turn out to be the same question:

| Question | Implementation |
|---|---|
| "What is on screen at this cell?" | `lw x6, 0(addr)` |
| "Is this cell occupied?" | `lw x6, 0(addr)` then `bnez` |

Drawing a block and marking a cell occupied are one store. Erasing and freeing
are one store. This is why the program needs no data structures at all: the
collision test reads pixels.

The address of a cell is plain arithmetic:

```
address = LED_MATRIX_0_BASE + (row × width + column) × 4
```

which makes "one row down" a constant offset of `width × 4` bytes, and "one
column right" a constant `4`. Both are precomputed into a register and added.

## How a piece is represented

The active piece is four registers holding four **absolute addresses** — not
coordinates, not an offset table:

| Register | Role |
|---|---|
| `s4` | anchor cell — stays put across a rotation |
| `s5`, `s6`, `s7` | the other three cells |

Storing addresses rather than `(row, col)` pairs means every operation on the
piece is an addition. Moving it one row down is four `add`s of the same stride;
drawing it is four `sw`s. There is never a coordinate-to-address conversion,
because the coordinates were never materialised.

The remaining game state lives in registers too, untouched for the piece's whole
lifetime:

| Register | Meaning |
|---|---|
| `s1` | board height |
| `s2` | board width (temporarily repurposed as the byte stride) |
| `s3` | rows travelled during this fall |
| `s8` | piece type — `0`=rect, `1`=cube, `2`=z, `3`=t |
| `s9` | rotation flag — `0`=normal, `1`=rotated |

## Collision detection

For each of the four cells, the game computes the cell below it and tests
whether it is occupied. The subtlety is that a piece would otherwise collide
with **itself**: the cell below `s4` may well *be* `s5`.

```asm
p1: add x6, s4, s2       # the cell below s4
    beq x6, s5, p2       # that cell is part of this piece -> not a collision
    beq x6, s6, p2
    beq x6, s7, p2
    lw  x6, 0(x6)
    bnez x6, main        # genuinely occupied -> the piece has landed
```

Three comparisons per cell, twelve in total, and the whole test needs no memory
beyond the four registers already holding the piece. The same pattern with a
`+4` offset does the right-edge test, and with `-4` the left.

## Random pieces without a library

There is no `rand()` to call, so the piece type comes from an **xorshift32**
generator written inline — three shifts and three XORs over a seed kept in
`.data`:

```asm
lw   x6, 0(x5)
slli x7, x6, 13
xor  x6, x6, x7
srli x7, x6, 17
xor  x6, x7, x6
sw   x6, 0(x5)          # store the advanced seed for next time

li   x5, 4
rem  x6, x6, x5         # mod 4 -> piece type
```

Xorshift is the natural fit here: it needs no multiply, no state beyond a single
word, and its whole implementation is six instructions.

## Rotation

Rotation is not implemented as a general transform. Each piece type has a routine
that rewrites `s5`, `s6` and `s7` relative to the fixed anchor `s4` — `rect_up`,
`z_up`, `t_up` — and a matching routine that puts them back: `rect_down`,
`z_down`, `t_down`. The cube has neither, because a square is its own rotation.

Two things fall out of anchoring at `s4`:

- The piece cannot drift while spinning, since one of its cells never moves.
- Undo is exact. Pressing DOWN reverses precisely what UP did, including the
  compensating adjustment to the fall counter `s3` — rotating a horizontal bar
  upright makes it occupy three more rows, so `s3` is advanced by 3 and the undo
  subtracts the same 3.

Every rotation is checked before it is applied: the cells the piece would occupy
must be free, and there must be enough rows below it. If not, the request is
dropped and the piece keeps falling.

The cost of this approach is that each piece has exactly **two** orientations,
not the usual four — UP rotates, DOWN restores. Adding the other two would mean
another pair of routines per piece rather than a change to shared code.

## Clearing lines

Two routines, run in sequence after a piece locks:

- **`verify_and_delete`** scans the board from the bottom up, counting filled
  cells per row. A row whose count reaches `width` is complete: it is blanked in
  place, and `a0` is set to report that something was cleared.
- **`move_lines`** then closes the gap. It finds the empty row, scans upward for
  the first non-empty one, and copies it down cell by cell, blanking the source.

Splitting the work this way keeps each routine to a single loop with one job,
which matters more in assembly than in a language with structured control flow —
the cost of a nested condition is a hand-managed branch label, and the labels are
what make assembly hard to change.

## Running

The code targets the RISC-V simulator used in the course, with two memory-mapped
peripherals:

| Peripheral | Symbols used |
|---|---|
| `LED_MATRIX_0` | `_BASE`, `_WIDTH`, `_HEIGHT` |
| `D_PAD_0` | `_UP`, `_DOWN`, `_LEFT`, `_RIGHT` |

Assemble `tetris.s`, connect both peripherals, and run from the `setup` label.
The board size is read from the matrix at runtime, so the game adapts to whatever
dimensions the peripheral is configured with.

Controls:

| Button | Action |
|---|---|
| LEFT / RIGHT | move the piece one column |
| UP | rotate |
| DOWN | undo the rotation |

## Routines

| Routine | Description |
|---|---|
| `main_loop` | Spawn a random piece at the top of the board |
| `fall` | Main loop — drop one row per iteration, poll the d-pad |
| `draw` | Apply an offset to the piece's 4 cells and redraw |
| `u:` / `d:` | Read UP/DOWN and dispatch to the rotation routines |
| `r:` / `l:` | Read RIGHT/LEFT and move sideways, checking edges and collisions |
| `rect_up`, `z_up`, `t_up` | Rotate each piece type |
| `rect_down`, `z_down`, `t_down` | Undo the corresponding rotation |
| `load_rect`, `load_cube`, `load_z`, `load_t` | Build each piece's starting shape |
| `clear` / `update` | Erase / draw the piece's 4 current cells |
| `verify_and_delete` | Find and clear completed rows |
| `move_lines` | Drop the rows above a cleared one |
| `reset` | Blank the entire board |
| `fill` | Fill half the board — a debugging aid for line clearing |

## Known limitations

- **No game-over condition.** `main_loop` spawns a new piece unconditionally; it
  never checks whether the spawn area is already occupied. The game continues
  past a full board rather than ending.
- **Two orientations per piece**, as described above, instead of a four-state
  cycle.
- **The `z` and `t` rotated shapes were laid out by hand** and may want small
  visual adjustments.
- **Fall speed is whatever the simulator runs at** — there is no timer or delay
  loop, so the game is as fast as the host executes it.
- **`move_lines` closes one gap per call.** It fills the lowest empty row from
  above and then stops at the next empty row it meets, so clearing several
  *non-adjacent* rows at once leaves the upper gaps for later passes.

## Files

| File | Purpose |
|------|---------|
| `tetris.s` | The entire game — data section, main loop, rotations, line clearing |
