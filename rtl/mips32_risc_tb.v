`timescale 1ns / 1ps

module tb_mips32_risc_branch();
    reg clk1, clk2;

    mips32_risc uut (.clk1(clk1), .clk2(clk2));

    initial begin
        clk1 = 0; clk2 = 0;
        forever begin
            #5 clk1 = 1; #5 clk1 = 0;
            #5 clk2 = 1; #5 clk2 = 0;
        end
    end

integer i;
reg [5:0] mem_index;

// --- Task Definitions ---
task addi(input [4:0] rt, input [4:0] rs, input [15:0] imm);
    begin
        uut.instruct_mem[mem_index] = {6'b001000, rs, rt, imm};
        mem_index = mem_index + 1;
    end
endtask

task beq(input [4:0] rs, input [4:0] rt, input [15:0] offset);
    begin
        uut.instruct_mem[mem_index] = {6'b000100, rs, rt, offset};
        mem_index = mem_index + 1;
    end
endtask

task sub(input [4:0] rd, input [4:0] rs, input [4:0] rt);
    begin
        uut.instruct_mem[mem_index] = {6'b000000, rs, rt, rd, 5'b00000, 6'b100010};
        mem_index = mem_index + 1;
    end
endtask

task slt(input [4:0] rd, input [4:0] rs, input [4:0] rt);
    begin
        uut.instruct_mem[mem_index] = {6'b000000, rs, rt, rd, 5'b00000, 6'b101010};
        mem_index = mem_index + 1;
    end
endtask

task nop;
    begin
        uut.instruct_mem[mem_index] = 32'd0;
        mem_index = mem_index + 1;
    end
endtask

// --- Main Simulation Block ---
initial begin
    mem_index = 0;

    // 1. Reset Arrays
    for (i = 0; i < 64; i = i + 1) uut.instruct_mem[i] = 32'd0;
    for (i = 0; i < 32; i = i + 1) uut.reg_bank[i] = 32'd0;

    // 2. Load Inputs & Constants
    // PC = 0 to 4
    addi(5'd1, 5'd0, 16'd24);   // $r1 = A = 24
    addi(5'd2, 5'd0, 16'd9);    // $r2 = B = 9
    addi(5'd4, 5'd0, 16'd1);    // $r4 = Constant 1 (used to evaluate slt)
    nop; nop;                   // Allow writeback to settle

    // 3. Loop Core (Starts at PC = 5)
    // IF A == B -> Branch to DONE (PC = 26). Offset relative to PC = 6 is 20.
    beq(5'd1, 5'd2, 16'd20);    // PC = 5
    nop; nop;                   // PC = 6, 7

    // Check condition: A < B
    slt(5'd3, 5'd1, 5'd2);      // PC = 8 -> $r3 = ($r1 < $r2) ? 1 : 0
    nop; nop;                   // PC = 9, 10
    
    // IF $r3 == 1 (A < B) -> Branch to LESS_THAN (PC = 20). Offset relative to PC = 12 is 8.
    beq(5'd3, 5'd4, 16'd8);     // PC = 11
    nop; nop;                   // PC = 12, 13

    // --- GREATER_THAN BLOCK (A > B) ---
    sub(5'd1, 5'd1, 5'd2);      // PC = 14 -> A = A - B
    nop; nop;                   // PC = 15, 16
    beq(5'd0, 5'd0, 16'hFFF3);  // PC = 17 -> Back to START_LOOP (PC = 5). Offset is -13 (16'hFFF3)
    nop; nop;                   // PC = 18, 19

    // --- LESS_THAN BLOCK (A < B) ---
    sub(5'd2, 5'd2, 5'd1);      // PC = 20 -> B = B - A
    nop; nop;                   // PC = 21, 22
    beq(5'd0, 5'd0, 16'hFFED);  // PC = 23 -> Back to START_LOOP (PC = 5). Offset is -19 (16'hFFED)
    nop; nop;                   // PC = 24, 25

    // --- DONE ---
    addi(5'd5, 5'd1, 16'd0);    // PC = 26 -> Copy final GCD result from $r1 to $r5
    nop; nop;                   // PC = 27, 28
end

// --- Monitor and Timing Controls ---
initial begin
    uut.pc = 32'd0;
    #1;
    $monitor("Time=%0t | PC=%0d | A($r1)=%0d | B($r2)=%0d | Temp($r3)=%0d | GCD_Out($r5)=%0d", 
             $time, uut.pc, uut.reg_bank[1], uut.reg_bank[2], uut.reg_bank[3], uut.reg_bank[5]);

    // Allocation of substantial time to allow the subtraction loop iterations to settle
    #1200000; 
    $finish;
end
endmodule
