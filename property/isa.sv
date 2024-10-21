module isa (
  input clk,
  input rst_n
  );
  
  // Disable flush in priviledge mode
  no_st_flush: assume property(##2 core.id_unit.st_flush_i == 0);

  //---------------------
  //  Pipeline Follower
  //---------------------
  
  // Variables
  logic [31:0] if_pc, pd_pc, id_pc, ex_pc, mem_pc, wb_pc;
  logic [31:0] if_inst, pd_inst, id_inst, ex_inst, mem_inst, wb_inst;
  logic if_bubble, pd_bubble, id_bubble, ex_bubble, mem_bubble;
  logic id_stall;
  logic bu_flush;
  logic ex_exception;
  logic is_branch;

  // IF stage
  assign if_pc = core.if_unit.if_pc_o;
  assign if_inst = core.if_unit.if_insn_o;
  assign if_bubble = core.if_unit.if_insn_o.bubble;
  
  // PD stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      pd_pc <= 32'h200; //PC_INIT
      pd_inst <= 32'h13; //NOP
    end else if(!id_stall) begin
      pd_pc <= if_pc & 32'hfffffffc;
      pd_inst <= if_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin 
      pd_bubble <= 1'b1;
    end else if(bu_flush || ex_exception) begin
      pd_bubble <= 1'b1;
    end else if(!id_stall) begin
      pd_bubble <= if_bubble;
    end
  end

  // ID stage
  assign id_stall = core.id_unit.id_stall_o;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      id_pc <= 32'h200; //PC_INIT
      id_inst <= 32'h13; //NOP
    end else if(!id_stall) begin
      id_pc <= pd_pc;
      id_inst <= pd_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      id_bubble <= 1'b1;
    end else if(bu_flush || id_stall || ex_exception) begin
      id_bubble <= 1'b1;
    end else begin
      id_bubble <= pd_bubble;
    end
  end

  // EX stage
  assign bu_flush = core.ex_units.bu_flush_o;
  assign ex_exception = core.ex_units.ex_exceptions_o.any;
  assign is_branch = (id_inst[6:2] == 5'b11000);
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      ex_pc <= 32'h200; //PC_INIT
      ex_inst <= 32'h13; //NOP
    end else begin 
      ex_pc <= id_pc;
      ex_inst <= id_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      ex_bubble <= 1'b1;
    end else if(ex_exception || is_branch)begin
      ex_bubble <= 1'b1;
    end else begin
      ex_bubble <= id_bubble;
    end
  end

  // MEM stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      mem_pc <= 32'h200; //PC_INIT
      mem_inst <= 32'h13; //NOP
    end else begin 
      mem_pc <= ex_pc;
      mem_inst <= ex_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      mem_bubble <= 1'b1;
    end else begin
      mem_bubble <= ex_bubble;
    end
  end

  // WB stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      wb_pc <= 32'h200; //PC_INIT
      wb_inst <= 32'h13; //NOP
    end else begin 
      wb_pc <= mem_pc;
      wb_inst <= mem_inst;
    end
  end

  //----------------------------------------------
  //  Properties for verifying pipeline follower  
  //----------------------------------------------
  pd_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    pd_bubble == core.pd_unit.pd_insn_o.bubble
  );
  pd_pc_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~pd_bubble) 
    |->
    pd_pc == core.pd_unit.pd_pc_o
  );
  pd_inst_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~pd_bubble) 
    |->
    pd_inst == core.pd_unit.pd_insn_o.instr
  );
  id_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    id_bubble == core.id_unit.id_insn_o.bubble
  );
  id_pc_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~id_bubble) 
    |->
    id_pc == core.id_unit.id_pc_o
  );
  id_inst_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~id_bubble) 
    |->
    id_inst == core.id_unit.id_insn_o.instr
  );
  ex_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    ex_bubble == core.ex_units.ex_insn_o.bubble
  );
  ex_pc_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~ex_bubble) 
    |->
    ex_pc == core.ex_units.ex_pc_o
  );
  ex_inst_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~ex_bubble) 
    |->
    ex_inst == core.ex_units.ex_insn_o.instr
  );
  mem_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    mem_bubble == core.mem_unit0.mem_insn_o.bubble
  );
  mem_pc_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble) 
    |->
    mem_pc == core.mem_unit0.mem_pc_o
  );
  mem_inst_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble) 
    |->
    mem_inst == core.mem_unit0.mem_insn_o.instr
  );
  wb_pc_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble)
    |=>
    wb_pc == core.wb_unit.wb_pc_o
  );
  wb_inst_check:assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble)
    |=>
    wb_inst == core.wb_unit.wb_insn_o.instr
  );
  


endmodule

bind riscv_top_ahb3lite isa isa_prop(
  .clk(HCLK),
  .rst_n(HRESETn)
  ); 
