# 5-Stage Pipelined MIPS32 Processor Core (with Data Forwarding)

A cycle-accurate, 5-stage pipelined MIPS32-inspired RISC processor core implemented in synthesizable Verilog. This repository features a complete behavioral datapath equipped with dynamic hardware data forwarding, branch-flush handling, and a macro-based verification testbench.

---

## 📂 Project Structure

* **`/rtl`**: Contains the core hardware implementation file (`mips32_risc.v`). This acts as the structural hardware template containing the pipeline registers, hazard bypass paths, and execution datapath blocks.
* **`/tb`**: Contains the verification suite (`tb_mips32_risc.v`). This file acts as the simulation engine that loads programs, drives the two-phase clocking scheme (`clk1` & `clk2`), and monitors pipeline registers.

---

## 🛠️ Project Design & Architecture

### Main Processor Core (`/rtl`)
The hardware maps execution stages cleanly across a two-phase split clocking layout (`clk1` and `clk2`) using specialized inter-stage pipeline registers (`if_id_ir`, `id_ex_ir`, `ex_mem_ir`, `mem_wb_ir`).
1. **Instruction Fetch (IF):** Reads instructions out of an ideal instruction memory array using the current Program Counter (`pc`) register and flushes pipeline registers on taken branches.
2. **Instruction Decode (ID):** Extracts operand source locations, retrieves data from the internal 32-element register bank (`reg_bank`), and sign-extends immediate fields.
3. **Execute (EX):** Resolves mathematical operations through the ALU core, evaluates conditional branch flags (`BEQ`), and dynamically forwards operands across stages to resolve data hazards.
4. **Memory Access (MEM):** Dispatches load (`LW`) and store (`SW`) transactions directly targeting data memory blocks (`data_mem`).
5. **Write Back (WB):** Writes processed arithmetic outputs or freshly loaded memory data into destination registers inside the register bank.

### Default Testbench Profile (`/tb`)
To demonstrate and stress-test the processor's hazard resolution and branch-tracking capabilities, the provided testbench comes pre-loaded with a program that computes the **Greatest Common Divisor (GCD)** of two numbers using the Euclidean Subtraction Algorithm. By default, it initializes register `$r1 = 24` and `$r2 = 9`, executing a looping subtraction sequence until they match, outputting the final result ($3$) into register `$r5`.

---

## ⚡ Hazard Handling & Forwarding Logic

Unlike baseline pipeline designs that require software stalls or manual NOP insertion, this core incorporates integrated **hardware-level data forwarding**:

* **EX-to-EX Forwarding (Priority 1):** If an instruction in EX depends on a result calculated by an immediately preceding instruction currently in `EX/MEM`, data is forwarded directly from `ex_mem_aluout`.
* **MEM-to-EX Forwarding (Priority 2):** If an instruction depends on a result two cycles prior currently in `MEM/WB`, data is forwarded directly from `mem_wb_aluout` (or `mem_wb_lmd` for `LW`).
* **Branch Flushing:** On a taken `BEQ` instruction, the core automatically flushes speculatively fetched instructions in the `IF` and `ID` stages to ensure correct execution.

---

## 🔄 Customization: How to Write Your Own Programs

The provided testbench uses behavioral macro tasks to assemble code. Because these tasks write machine instructions directly into the processor's instruction memory array during initialization, **you do not need an external compiler or assembler to write and run new code on this core.**

You can completely repurpose this processor to calculate anything you want by updating the program sequence inside the testbench.

### 1. Available Instruction Tasks Syntax
When writing your own algorithm inside the testbench simulation block, you can use these pre-built helper commands to write your code step-by-step:

*   **`addi(rt, rs, immediate);`** $\rightarrow$ Adds a sign-extended 16-bit constant value to register `rs` and saves it inside destination index `rt`.
*   **`add(rd, rs, rt);`** $\rightarrow$ Adds values in registers `rs` and `rt`, storing the output inside destination register `rd`.
*   **`sub(rd, rs, rt);`** $\rightarrow$ Subtracts the value inside register `rt` from register `rs` and stores the output inside destination register `rd`.
*   **`and_op(rd, rs, rt);`** $\rightarrow$ Performs a bitwise AND operation between `rs` and `rt` and saves it in `rd`.
*   **`or_op(rd, rs, rt);`** $\rightarrow$ Performs a bitwise OR operation between `rs` and `rt` and saves it in `rd`.
*   **`slt(rd, rs, rt);`** $\rightarrow$ Sets register `rd = 1` if the value inside register `rs` is less than register `rt`. Otherwise, sets `rd = 0`.
*   **`lw(rt, offset, base);`** $\rightarrow$ Loads a word from memory address `base + offset` into register `rt`.
*   **`sw(rt, offset, base);`** $\rightarrow$ Stores the word from register `rt` into memory address `base + offset`.
*   **`beq(rs, rt, offset);`** $\rightarrow$ Evaluates operand equality. If `rs` and `rt` match, it shifts your program pointer according to the relative sign-extended index `offset`.
*   **`halt;`** $\rightarrow$ Stops processor execution and freezes the program counter.

### 2. Steps to Change the Program for Your Own Task

To completely wipe out the default GCD loop and execute your own custom task, follow these guidelines inside `tb_mips32_risc.v`:

1. Locate the **`// --- Main Simulation Block ---`** marker.
2. Leave the initial helper loops intact (the ones that clear out `uut.instruct_mem` and `uut.reg_bank` to prevent old data corruption).
3. Delete the default GCD instruction lines (the `addi`, `beq`, `slt`, and `sub` sequence).
4. Begin ordering your own custom application instructions sequentially using the task commands listed above.
5. **AUTOMATIC HAZARD RESOLUTION - No NOPs Required:** Thanks to the dynamic hardware forwarding unit, dependent arithmetic and logical instructions can now be written **back-to-back without inserting `nop;` commands**. The hardware automatically intercepts and routes pipeline register data to prevent Read-After-Write (RAW) data hazards.
