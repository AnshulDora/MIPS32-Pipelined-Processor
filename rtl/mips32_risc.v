`timescale 1ns / 1ps

module mips32_risc(
    input clk1, clk2,
    input rst,        // Explicit hardware reset pin (Active-High)
    output reg halted // Exposed to top level for simulation control
);

// ==========================================
// PARAMETERS: Opcodes & Function Codes
// ==========================================
parameter R_TYPE = 6'b000000;
parameter ADDI   = 6'b001000;
parameter LW     = 6'b100011;
parameter SW     = 6'b101011;
parameter BEQ    = 6'b000100;
parameter HALT   = 6'b111111;

parameter ADD    = 6'b100000;
parameter SUB    = 6'b100010;
parameter AND    = 6'b100100;
parameter OR     = 6'b100101;
parameter SLT    = 6'b101010;

// ==========================================
// INTERNAL REGISTERS & MEMORY
// ==========================================
reg [31:0] pc;
reg [31:0] if_id_ir, if_id_npc;
reg [31:0] id_ex_ir, id_ex_a, id_ex_b, id_ex_imm, id_ex_npc;
reg [31:0] ex_mem_ir, ex_mem_aluout, ex_mem_b, alu_in_a, alu_in_b;
reg [4:0]  ex_mem_dest;
reg        ex_mem_cond;
reg        taken_branch;
reg [31:0] mem_wb_ir, mem_wb_lmd, mem_wb_aluout;
reg [4:0]  mem_wb_dest;
reg [31:0] wb_end_ir;

reg [31:0] instruct_mem [0:1023];
reg [31:0] data_mem     [0:1023];     
reg [31:0] reg_bank     [0:31];

// ==========================================
// 1. INSTRUCTION FETCH (IF) STAGE - clk1
// ==========================================
always @(posedge clk1) begin  
   if (rst) begin
      pc           <= 32'd0;
      if_id_ir     <= 32'd0;
      if_id_npc    <= 32'd0;
      taken_branch <= 1'b0;
   end
   else if (halted) begin
      if_id_ir     <= 32'd0; // Freeze PC and continuously inject NOPs
   end
   else if ((ex_mem_ir[31:26] == BEQ) && (ex_mem_cond)) begin
      if_id_ir     <= 32'd0;
      if_id_npc    <= ex_mem_aluout;
      taken_branch <= 1'b1;
      pc           <= ex_mem_aluout;
   end
   else begin
      if_id_ir     <= instruct_mem[pc];
      if_id_npc    <= pc + 32'd1;
      pc           <= pc + 32'd1;
   end 
end

// ==========================================
// 2. INSTRUCTION DECODE (ID) STAGE - clk2
// ==========================================
always @(posedge clk2) begin  
   if (rst) begin
      halted    <= 1'b0;
      id_ex_ir  <= 32'd0;
      id_ex_a   <= 32'd0;
      id_ex_b   <= 32'd0;
      id_ex_imm <= 32'd0;
      id_ex_npc <= 32'd0;
   end
   else if (taken_branch) begin
      id_ex_ir  <= 32'd0;
      id_ex_a   <= 32'd0;
      id_ex_b   <= 32'd0;
      id_ex_imm <= 32'd0;
      id_ex_npc <= 32'd0;
   end
   else if (if_id_ir[31:26] == HALT) begin
      halted    <= 1'b1;     // Latches halt state
      id_ex_ir  <= if_id_ir; // Passes HALT to flush downstream stages
      id_ex_a   <= 32'd0;
      id_ex_b   <= 32'd0;
      id_ex_imm <= 32'd0;
      id_ex_npc <= 32'd0;
   end
   else begin
      id_ex_ir  <= if_id_ir;
      id_ex_a   <= reg_bank[if_id_ir[25:21]];
      id_ex_b   <= reg_bank[if_id_ir[20:16]];
      id_ex_imm <= {{16{if_id_ir[15]}}, if_id_ir[15:0]}; // Fixed syntax
      id_ex_npc <= if_id_npc;
   end
end

// ==========================================
// 3. EXECUTE (EX) STAGE - clk1
// ==========================================
always @(*) begin
    // --- Operand A Forwarding ---
    if ((id_ex_ir[25:21] == ex_mem_dest) && (ex_mem_dest != 5'd0)) begin
        alu_in_a = ex_mem_aluout; // Priority 1: Forward from EX/MEM
    end 
    else if ((id_ex_ir[25:21] == mem_wb_dest) && (mem_wb_dest != 5'd0)) begin
        case (mem_wb_ir[31:26])
            LW:      alu_in_a = mem_wb_lmd;    // Memory load result
            R_TYPE,
            ADDI:    alu_in_a = mem_wb_aluout; // ALU result
            default: alu_in_a = id_ex_a;
        endcase
    end
    else begin
        alu_in_a = id_ex_a; // Default: Register file read
    end

    // --- Operand B Forwarding ---
    if ((id_ex_ir[20:16] == ex_mem_dest) && (ex_mem_dest != 5'd0)) begin
        alu_in_b = ex_mem_aluout; // Priority 1: Forward from EX/MEM
    end 
    else if ((id_ex_ir[20:16] == mem_wb_dest) && (mem_wb_dest != 5'd0)) begin
        case (mem_wb_ir[31:26])
            LW:      alu_in_b = mem_wb_lmd;
            R_TYPE,
            ADDI:    alu_in_b = mem_wb_aluout;
            default: alu_in_b = id_ex_b;
        endcase
    end 
    else begin
        alu_in_b = id_ex_b; // Default: Register file read
    end
end

always @(posedge clk1) begin 
   if (rst) begin
      ex_mem_ir     <= 32'd0;
      ex_mem_aluout <= 32'd0;
      ex_mem_b      <= 32'd0;
      ex_mem_cond   <= 1'b0;
      ex_mem_dest   <= 5'd0;
   end
   else begin
      taken_branch <= 1'b0; // Pull down flag
      ex_mem_ir    <= id_ex_ir;

      case (id_ex_ir[31:26])
         R_TYPE:  ex_mem_dest <= id_ex_ir[15:11]; // rd
         ADDI,LW: ex_mem_dest <= id_ex_ir[20:16]; // rt
         default: ex_mem_dest <= 5'd0;            // SW, BEQ, HALT write no register
      endcase

      if (id_ex_ir[31:26] == R_TYPE) begin
         ex_mem_b    <= alu_in_b;
         ex_mem_cond <= 1'b0;            
         
         case (id_ex_ir[5:0])
            ADD:     ex_mem_aluout <= alu_in_a + alu_in_b;     
            SUB:     ex_mem_aluout <= alu_in_a - alu_in_b;     
            AND:     ex_mem_aluout <= alu_in_a & alu_in_b;     
            OR:      ex_mem_aluout <= alu_in_a | alu_in_b;     
            SLT:     ex_mem_aluout <= (alu_in_a < alu_in_b);   
            default: ex_mem_aluout <= 32'd0;
         endcase        
      end
      else begin
         case (id_ex_ir[31:26])
            ADDI, LW, SW: begin 
               ex_mem_aluout <= alu_in_a + id_ex_imm; 
               ex_mem_b      <= alu_in_b;
               ex_mem_cond   <= 1'b0;                
            end
            BEQ: begin 
               ex_mem_aluout <= id_ex_imm + id_ex_npc;
               ex_mem_b      <= alu_in_b;
               ex_mem_cond   <= (alu_in_a == alu_in_b); 
            end
            default: begin
               ex_mem_aluout <= 32'd0;
               ex_mem_cond   <= 1'b0;
            end
         endcase
      end
   end
end

// ==========================================
// 4. MEMORY ACCESS (MEM) STAGE - clk2
// ==========================================
always @(posedge clk2) begin
   if (rst) begin
      mem_wb_ir     <= 32'd0;
      mem_wb_aluout <= 32'd0;
      mem_wb_lmd    <= 32'd0;
      mem_wb_dest   <= 5'd0;
   end
   else begin
      mem_wb_ir     <= ex_mem_ir;
      mem_wb_aluout <= ex_mem_aluout;
      mem_wb_dest   <= ex_mem_dest;

      case (ex_mem_ir[31:26])
          LW: mem_wb_lmd <= data_mem[ex_mem_aluout];
          SW: begin 
                data_mem[ex_mem_aluout] <= ex_mem_b; 
                mem_wb_lmd <= 32'd0; 
              end 
          default: mem_wb_lmd <= 32'd0;
      endcase
   end
end

// ==========================================
// 5. WRITE BACK (WB) STAGE - clk1
// ==========================================
always @(posedge clk1) begin
   if (rst) begin
      wb_end_ir <= 32'd0;
   end
   else begin
      wb_end_ir <= mem_wb_ir;
      
      case (mem_wb_ir[31:26])
          R_TYPE: begin 
             if (mem_wb_ir[15:11] != 5'd0) begin
                reg_bank[mem_wb_ir[15:11]] <= mem_wb_aluout;
             end
          end
          
          ADDI: begin 
             if (mem_wb_ir[20:16] != 5'd0) begin
                reg_bank[mem_wb_ir[20:16]] <= mem_wb_aluout;
             end
          end
          
          LW: begin 
             if (mem_wb_ir[20:16] != 5'd0) begin
                reg_bank[mem_wb_ir[20:16]] <= mem_wb_lmd;
             end
          end
          
          default: begin
             // SW, BEQ, HALT write nothing
          end
      endcase
   end
end

endmodule
