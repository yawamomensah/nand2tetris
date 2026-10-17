# Nand2Tetris — Building a Computing Platform from First Principles

A complete implementation of the Nand2Tetris curriculum in C and HDL, built to answer a specific question: **how does a computing platform actually come into being?**

Every layer of this project was implemented by hand — from boolean logic gates through to a working compiler for a high-level object-oriented language. No shortcuts, no standard library substitutes for the interesting parts.

---

## What Was Built

| Layer | Implementation | Language |
|---|---|---|
| Boolean Logic Gates | NAND, AND, OR, NOT, XOR, MUX, DMUX and all variants | HDL |
| Combinational Chips | Half adder, full adder, ALU, multiplexers | HDL |
| Sequential Chips | D flip-flop, registers, RAM8 through RAM16K, PC | HDL |
| CPU | Complete Hack CPU with A/D registers, ALU, PC | HDL |
| Memory | ROM, RAM, Screen, Keyboard mapped memory | HDL |
| Assembler | Two-pass assembler with symbol resolution | C |
| VM Translator | Stack-based bytecode to assembly translator | C |
| Jack Tokenizer | Lexical analyser — source text to typed token stream | C |
| Jack Parser | Recursive descent parser with XML parse tree output | C |
| Jack Compiler | Full code generation — Jack source to VM bytecode | C |

All modules tested and passing against the provided test suites.

---

## The Intellectual Arc

What became clear building each layer is that **constraints are not obstacles to elegant solutions — they are the source of them**. The Hack architecture's minimal instruction set forces you to express complex operations through careful sequencing of simple primitives. The VM's flat global stack turns out to be sufficient substrate for arbitrarily nested function calls. Each layer's limitations shaped the design of the layer above it in ways that feel inevitable in retrospect.

This isn't something you understand by reading about it. It becomes visible when you implement it.

---

## Assembler — C Implementation

A two-pass assembler that translates Hack assembly into binary machine code.

**First pass** — scans the source file building a symbol table of label declarations and their ROM addresses using a custom djb2 hash table with chaining.

**Second pass** — translates each instruction, resolving symbols through the table built in the first pass. A-instructions become 16-bit values, C-instructions are encoded by decomposing their dest/comp/jump fields against a lookup table.

**Infrastructure built from scratch:**
- djb2 hash table with chaining for O(1) symbol lookup
- Two-pass parser with clean separation between symbol resolution and instruction translation
- Fail fast error handling — invalid instructions exit immediately with meaningful messages

---

## VM Translator — C Implementation

A complete two-tier VM translator covering the full Hack VM specification across chapters 7 and 8. Translates stack-based VM bytecode into Hack assembly, implementing the virtual machine's execution model entirely in generated assembly code.

### Pipeline Architecture

```
raw line → strip → tokenize → lookup → dispatch → codewriter → .asm output
```

Each stage has a single responsibility and a clean contract with the next. The pipeline requires zero structural modification between chapter 7 and chapter 8 — new commands are added to the lookup table and new codewriter functions handle them. The architecture absorbed the extension without resistance.

### Custom Infrastructure

**String library** — hand-written string utilities including `strip` (in-place whitespace and comment removal via `memmove`) and a custom tokenizer using an anchor/scout two-pointer strategy with `reached_end` boundary handling for correct final token capture.

**Hash table** — djb2 hash table (size 31, chaining) over a static `CommandEntry` ground truth table covering all 17 chapter 7 VM commands plus the 6 chapter 8 additions. The hash table holds typed `CommandNode` pointers into the static table — one source of truth, the hash table purely an acceleration structure.

**`string_to_int`** — custom integer parser with overflow detection against Hack's 16-bit bounds using `HACK_INT_MAX` and `HACK_INT_MIN` macros, trailing character validation, and preserved input pointer for accurate error reporting.

### Chapter 7 — Stack Arithmetic and Memory Access

Implements all arithmetic, logical, and memory access commands across all eight virtual memory segments:

- **Binary operations** — `add`, `sub`, `and`, `or` via parameterised `write_binary`, substituting only the ALU instruction string
- **Unary operations** — `neg`, `not` via `write_unary`
- **Comparison operations** — `eq`, `gt`, `lt` with unique label generation via caller-owned counter passed as `int*`, producing `FunctionName$ret.i` symbols that avoid collisions in the flat assembly namespace
- **Memory segments** — `constant`, `static`, `local`, `argument`, `this`, `that`, `temp`, `pointer` — each with distinct address computation patterns. `static` uses `Filename.i` symbols resolved by the assembler. Base pointer segments use pointer dereferencing. Fixed base segments use direct address arithmetic.

### Chapter 8 — Function Calling Convention

Implements a complete runtime environment for function calls — the mechanism that makes arbitrarily nested function execution possible on a flat stack machine.

**`write_function`** — emits the function entry label followed by a local variable initialisation loop, pushing 0 onto the stack `n_locals` times.

**`write_call`** — complete frame setup sequence:
1. Push return address symbol (`CurrentFunction$ret.i`) — loads ROM address of the label into D via `D=A`
2. Push saved LCL, ARG, THIS, THAT — loads pointer values via `D=M`
3. Reposition ARG to `SP - nArgs - 5` — reaches back past the five saved values to the first argument
4. Reposition LCL to current SP — callee's local segment starts here
5. Jump to callee entry label
6. Emit return address label — the instruction immediately following, where execution resumes after return

**`write_return`** — frame dismantling sequence:
1. Save frame base (`LCL`) to R13 before anything moves
2. Save return address (`*(LCL-5)`) to R14 — must happen before SP is repositioned
3. Reposition return value to `*ARG` — caller expects it here
4. Restore SP to `ARG + 1`
5. Restore THAT, THIS, ARG, LCL from frame offsets in reverse order — LCL last since all offsets are computed relative to it
6. Jump via R14 to saved return address

**Symbol generation** follows the VM spec naming convention:
- Function entry points: `FunctionName` (e.g. `Foo.bar`)
- Branching labels: `FunctionName$label` (e.g. `Foo.bar$LOOP`)
- Return address symbols: `FunctionName$ret.i` (e.g. `Foo.bar$ret.0`)
- Static variables: `Filename.i` (e.g. `Foo.3`)

**Directory translation mode** — when passed a directory, the translator processes all `.vm` files into a single output assembly file, emitting bootstrap code (SP initialisation + `call Sys.init 0`) at the top. Each file's `base_name` is tracked independently for correct static segment label generation. A persistent counter across all files ensures globally unique return address labels.

### Error Handling Philosophy

Fail fast throughout. Unrecognised commands, malformed input, invalid segment indices, integer overflow, truncated lines — all caught at the earliest possible point with meaningful `stderr` messages including the offending token and line context. The translator either produces correct assembly or terminates with a clear explanation. It never silently continues past structural errors.

### Code Review

Both chapters reviewed by CodeRabbit on submission:
- **Complexity rating: 4 (Complex)** — consistent across both chapters
- Estimated review effort: ~50 minutes per chapter
- Issues found: targeted mechanical findings, no architectural concerns raised

---

## Jack Compiler — Chapters 10 and 11 (C Implementation)

A complete compiler for the Jack language, implemented in C across two chapters. Chapter 10 built the front end — lexical analysis and parsing. Chapter 11 added the back end — symbol resolution and VM code generation. The compiler drives two output streams simultaneously: an XML parse tree for structural verification and VM bytecode for execution.

### Pipeline

```
.jack source → tokenizer → token stream → parser → parse tree + VM code
```

The tokenizer and parser are strictly separated. The tokenizer's only job is to produce a flat, typed token stream from source text. The parser's only job is to impose grammatical structure on that stream and drive code generation. Neither stage reaches into the other's domain.

### Tokenizer

The tokenizer consumes a Jack source file and produces a flat array of typed tokens, each represented as a slice into the original source buffer — a pointer and length with no allocation or copy overhead. Printing uses `%.*s` throughout; the source buffer is never null-terminated mid-stream.

**Character classification** is handled by a dispatch table indexed on the first character of each token, collapsing the branching that would otherwise dominate the recognition loop into a single indirect call per token.

**Keyword discrimination** happens at the identifier boundary: candidates that pass the identifier character test are submitted to a `bsearch` against a sorted keywords array. Identifiers that match become keyword tokens; everything else remains an identifier. This keeps the recognition path uniform and avoids special-casing keywords during character-level scanning.

**Token storage** uses a flat array of structs with dynamic doubling reallocation — no pool allocator, no array of heap pointers. The layout is cache-friendly and the growth strategy is the standard amortised O(1) append.

**The two-pointer anchor/scout idiom** drives the main scan loop, with the anchor always positioned at the first character of the next token and the scout advancing to find its boundary. Preconditions are maintained explicitly at each transition so the loop body reasons only about what it sees, not about what might have been left behind.

### Parser

A hand-written recursive descent parser structured directly from the Jack grammar. Each non-terminal in the grammar maps to a function; each function consumes exactly the tokens its production covers and returns, leaving the stream positioned at the first token of whatever follows.

**Error handling** follows the same fail-fast discipline as the rest of the pipeline. A token that does not match the expected terminal exits immediately with the offending token, its position, and what was expected. The parser never attempts recovery or continuation past a structural mismatch.

### Symbol Table

Two-scope flat array model: `ClassTable` (field/static) and `SubTable` (argument/local), each a fixed array of entry structs with slice-based name and type fields — pointer and length into the source buffer, consistent with the tokenizer's representation throughout. Separate per-kind counters assign VM segment indices at insertion time.

Both lookup functions iterate from the most recently inserted entry backwards — variables declared closest to the point of use are found first on average, reducing comparisons in the common case. Lookup is subroutine-scope-first, falling through to class scope on a miss. A NULL return at a subroutine call site indicates a class name rather than a variable reference.

Linear search over the flat array is deliberate — Jack's scope sizes make hashing unnecessary overhead. A subroutine symbol table large enough to require hashing would indicate a poorly structured subroutine.

### Code Generation

**Subroutine kind handling** — the subroutine kind (constructor/method/function) is captured into `ParserState` before parsing the keyword. The `function` declaration is deferred until all `varDec` parsing completes so that `local_count` is final. The preamble then diverges by kind:

- Constructor: `push field_count`, `call Memory.alloc 1`, `pop pointer 0`
- Method: `push argument 0`, `pop pointer 0`
- Function: no preamble

For methods, a hidden `this` entry is inserted into the subroutine table before parameter parsing so explicit parameters receive correct indices from 1.

**Expression code generation** — `compileExpression` holds the binary operator in a temporary after consuming it, compiles the right-hand term, then emits the operator. Postfix ordering falls out of the recursive call structure without any explicit reordering.

**`compileTerm`** handles all term forms: integer and string constants, keyword constants (`null`/`false` → `push constant 0`; `true` → `push constant 0` / `not`; `this` → `push pointer 0`), plain variable lookup, array access, subroutine calls in all three forms, unary operators, and parenthesised expressions. Every branch either emits correct VM code or terminates with a diagnostic — no silent fallthrough.

**Array assignment** uses a temp register to preserve the RHS value across the `pointer 1` assignment: push base address, compile index, `add`, compile RHS, `pop temp 0`, `pop pointer 1`, `push temp 0`, `pop that 0`.

**Label generation** — `compileIf` and `compileWhile` each reserve two indices from a persistent `label_count` in `ParserState` at function entry, before any recursive `compileStatements` call. Both labels are allocated upfront so nested constructs consume indices beyond them, eliminating collisions under arbitrary nesting depth.

**Void return** — `compileReturn` pushes `constant 0` before emitting `return` when the next token is `;`. `compileDo` pops the discarded return value into `temp 0` after every subroutine call to keep the stack balanced.

**`emit_push` / `emit_pop`** centralise the kind-to-segment mapping: `T_STATIC` → `static`, `T_FIELD` → `this`, `T_ARG` → `argument`, `T_VAR` → `local`.

### Tests Passing

Single-file: Average, Seven, ConvertToBin, ComplexArrays. Multi-file: Pong — verified in the VM emulator with directory load.

### Code Review

Chapters 10 and 11 reviewed by CodeRabbit on submission:
- **Complexity rating: 4 (Complex)** — consistent across both chapters
- Estimated review effort: ~50 minutes per chapter
- Issues found: targeted mechanical findings, no architectural concerns raised

---

## Repository Structure

```
nand2tetris/
├── part_I/
│   ├── chapter_01/     — Boolean Logic
│   ├── chapter_02/     — Boolean Arithmetic
│   ├── chapter_03/     — Sequential Logic
│   ├── chapter_04/     — Machine Language
│   ├── chapter_05/     — Computer Architecture
│   └── chapter_06/     — Assembler (C)
└── part_II/
    ├── chapter_07/     — VM Translator Part I (C)
    ├── chapter_08/     — VM Translator Part II (C)
    ├── chapter_10/     — Jack Tokenizer and Parser (C)
    └── chapter_11/     — Jack Compiler Back-End (C)
```

Each chapter directory contains its own README with implementation notes, design decisions, and test results.

---

## References

- Nisan & Schocken — *The Elements of Computing Systems* (Nand2Tetris)
- Bryant & O'Hallaron — *Computer Systems: A Programmer's Perspective* (CS:APP)
- Kernighan & Ritchie — *The C Programming Language* (K&R 2nd edition)
- Petzold — *Code: The Hidden Language of Computer Hardware and Software*
- Bentley — *Programming Pearls*
- Skiena — *The Algorithm Design Manual*
