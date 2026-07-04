# 5-Stage Pipelined MIPS32 Processor Core

A cycle-accurate, 5-stage pipelined MIPS32-inspired RISC processor core implemented in synthesizable Verilog. This repository features a complete behavioral datapath coupled with a programmable, macro-based verification testbench.

---

## 📂 Project Structure

* **`/rtl`**: Contains the core hardware implementation file (`mips32_risc.v`). This acts as the structural hardware template containing the pipeline registers and execution datapath blocks.
* **`/tb`**: Contains the verification suite (`tb_mips32_risc_branch.v`). This file acts as the simulation engine that loads programs and drives clock cycles.

---

## 🛠️ Project Design & Architecture

### Main Processor Core (`/rtl`)
The hardware maps execution stages cleanly across a two-phase split clocking layout (`clk1` and `clk2`) using specialized inter-stage pipeline registers (`if_id_ir`, `id_ex_ir`, `ex_mem_ir`, `mem_wb_ir`).
1. **Instruction Fetch (IF):** Reads instructions out of an ideal instruction memory array using the current Program Counter (`pc`) register.
2. **Instruction Decode (ID):** Extracts operand source locations and retrieves active data configurations from the internal 32-element register bank (`reg_bank`).
3. **Execute (EX):** Resolves mathematical operations through the ALU core and evaluates conditional branch flags (`BEQ`).
4. **Memory Access (MEM):** Dispatches load/store transactions directly targeting data memory blocks.
5. **Write Back (WB):** Forwards processed arithmetic outputs or freshly loaded memory registers down to register bank updates.

### Default Testbench Profile (`/tb`)
To demonstrate and stress-test the processor's branch-tracking capabilities, the provided testbench comes pre-loaded with a program that computes the **Greatest Common Divisor (GCD)** of two numbers using the Euclidean Subtraction Algorithm. By default, it initializes register `$r1 = 24` and `$r2 = 9`, executing a looping subtraction sequence until they match, outputting the final result ($3$) into register `$r5`.

---

## 🔄 Customization: How to Write Your Own Programs

The provided testbench uses behavioral macro tasks to assemble code. Because these tasks write machine instructions directly into the processor's instruction memory array during initialization, **you do not need an external compiler or assembler to write and run new code on this core.**

You can completely repurpose this processor to calculate anything you want by updating the program sequence inside the testbench.

### 1. Available Instruction Tasks Syntax
When writing your own algorithm inside the testbench simulation block, you can use these pre-built helper commands to write your code step-by-step:

*   **`addi(rt, rs, immediate);`** $\rightarrow$ Adds a sign-extended 16-bit constant value to register `rs` and saves it inside destination index `rt`.
*   **`sub(rd, rs, rt);`** $\rightarrow$ Subtracts the value found inside register `rt` from register `rs` and stores the output inside destination register `rd`.
*   **`slt(rd, rs, rt);`** $\rightarrow$ Sets register `rd = 1` if the value inside register `rs` is less than register `rt`. Otherwise, sets `rd = 0`.
*   **`beq(rs, rt, offset);`** $\rightarrow$ Evaluates operand equality. If the data elements within `rs` and `rt` match exactly, it shifts your program pointer forward or backward according to the relative sign-extended index `offset`.
*   **`nop;`** $\rightarrow$ Injects an empty execution cycle (`32'd0`) to let previous calculations settle through your pipeline registers safely.

### 2. Steps to Change the Program for Your Own Task

To completely wipe out the default GCD loop and execute your own custom task, follow these guidelines inside `tb_mips32_risc_branch.v`:

1. Locate the **`// --- Main Simulation Block ---`** marker.
2. Leave the initial helper loops intact (the ones that clear out `uut.instruct_mem` and `uut.reg_bank` to prevent old data corruption).
3. Delete the default GCD instruction lines (the `addi`, `beq`, `slt`, and `sub` sequence).
4. Begin ordering your own custom application instructions sequentially using the task commands listed above.
5. **CRITICAL PIPELINE RULE - Handling Data Hazards:** Because this processor core focuses on pipeline sequencing and does not contain an automatic data-forwarding hardware unit, you must handle data dependencies manually. 
   > **The 2-NOP Rule:** Anytime you write a value to a register using an instruction (like `addi` or `sub`), you **must insert two consecutive `nop;` commands** immediately after it before any following instruction attempts to read from that same register. This provides the processor with enough clock cycles to write the value back to the register bank safely before it's read by the next instruction decode stage.
