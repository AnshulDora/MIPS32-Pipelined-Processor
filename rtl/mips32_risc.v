`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.07.2026 09:31:18
// Design Name: 
// Module Name: mips32_risc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Fully synthesizable MIPS32 pipeline with explicit hardware reset.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.03 - Removed initial block, implemented synthesizable hardware reset (rst)
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

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
reg [31:0] ex_mem_ir, ex_mem_aluout, ex_mem_b;
reg ex_mem_cond;
reg taken_branch;
reg [31:0] mem_wb_ir, mem_wb_lmd, mem_wb_aluout;
reg [31:0] wb_end_ir;

reg [31:0] instruct_mem [0:1023];
reg [31:0] data_mem [0:1023];     
reg [31:0] reg_bank [0:31];

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
      // Freeze PC and continuously inject NOPs into the pipeline
      if_id_ir  <= 32'd0; 
   end
   else if ((ex_mem_ir[31:26] == BEQ) && (ex_mem_cond)) begin
      if_id_ir     <= 32'd0;
      if_id_npc    <= ex_mem_aluout;
      taken_branch <= 1'b1;
      pc           <= ex_mem_aluout;
   end
   else begin
      if_id_ir     <= instruct_mem[pc];
      if_id_npc    <= pc + 1;
      pc           <= pc + 1;
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
      id_ex_npc <= if_id_npc;
   end
   else if (if_id_ir[31:26] == HALT) begin
      halted    <= 1'b1;   // Permanently latches the halt state
      id_ex_ir  <= if_id_ir; // Passes HALT along to flush downstream stages safely
      id_ex_a   <= 32'd0;
      id_ex_b   <= 32'd0;
      id_ex_imm <= 32'd0;
      id_ex_npc <= if_id_npc;
   end
   else begin
      id_ex_ir  <= if_id_ir;
      id_ex_a   <= reg_bank[if_id_ir[25:21]];
      id_ex_b   <= reg_bank[if_id_ir[20:16]];
      id_ex_imm <= {{16{if_id_ir[15]}}, {if_id_ir[15:0]}};
      id_ex_npc <= if_id_npc;
   end
end

// ==========================================
// 3. EXECUTE (EX) STAGE - clk1
// ==========================================
always @(posedge clk1) begin 
   if (rst) begin
      ex_mem_ir     <= 32'd0;
      ex_mem_aluout <= 32'd0;
      ex_mem_b      <= 32'd0;
      ex_mem_cond   <= 1'b0;
   end
   else begin
      taken_branch <= 1'b0; // Safely pull down flag
      ex_mem_ir    <= id_ex_ir;
      
      if (id_ex_ir[31:26] == R_TYPE) begin // R-Type
         ex_mem_b    <= id_ex_b;
         ex_mem_cond <= 1'b0;            
         
         case (id_ex_ir[5:0])
            ADD:     ex_mem_aluout <= id_ex_a + id_ex_b;     
            SUB:     ex_mem_aluout <= id_ex_a - id_ex_b;     
            AND:     ex_mem_aluout <= id_ex_a & id_ex_b;     
            OR:      ex_mem_aluout <= id_ex_a | id_ex_b;     
            SLT:     ex_mem_aluout <= (id_ex_a < id_ex_b);   
            default: ex_mem_aluout <= 32'd0;
         endcase        
      end
      else begin // I-Type
         case (id_ex_ir[31:26])
            ADDI, LW, SW: begin 
               ex_mem_aluout <= id_ex_a + id_ex_imm; 
               ex_mem_b      <= id_ex_b;
               ex_mem_cond   <= 1'b0;                
            end
            BEQ: begin 
               ex_mem_aluout <= id_ex_imm + id_ex_npc;
               ex_mem_b      <= id_ex_b;
               ex_mem_cond   <= (id_ex_a == id_ex_b); 
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
   end
   else begin
      mem_wb_ir      <= ex_mem_ir;
      mem_wb_aluout <= ex_mem_aluout;
      
      case(ex_mem_ir[31:26])
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
      // Note: Reg_bank and data_mem typically do not reset via logic blocks 
      // to avoid massive hardware overhead; they get overwritten during execution.
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
             // SW, BEQ, HALT ignore writeback
          end
      endcase
   end
end

endmodule
