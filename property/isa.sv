module isa (
  input clk,
  input rst_n
  );


  //---------------------
  //  Pipeline Follower
  //---------------------
  
  // Variables
  logic [31:0] if_pc, pd_pc, id_pc, ex_pc, mem_pc, wb_pc;
  logic [31:0] if_inst, pd_inst, id_inst, ex_inst, mem_inst, wb_inst;
  logic if_bubble, pd_bubble, id_bubble, ex_bubble, mem_bubble;
  logic id_stall;
  logic bu_flush;

  // IF stage
  assign if_pc = core.if_unit.if_pc_o;
  assign if_inst = core.if_unit.if_insn_o;
  assign if_bubble = core.if_unit.if_nxt_insn_o.bubble;
  
  // PD stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      pd_pc <= PC_INIT;
      pd_inst <= NOP;
    end else if(!id_stall) begin
      pd_pc <= if_pc;
      pd_inst <= if_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)         pd_bubble <= 1'b1;
    else if(bu_flush)  pd_bubble <= 1'b1;
    else if(!id_stall) pd_bubble <= if_bubble;
  end

  // ID stage
  assign id_stall = core.id_unit.id_stall_o;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      id_pc <= PC_INIT;
      id_inst <= NOP;
    end else if(!id_stall) begin
      id_pc <= pd_pc;
      id_inst <= pd_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)         id_bubble <= 1'b1;
    else if(bu_flush)  id_bubble <= 1'b1;
    else if(id_stall)  id_bubble <= 1'b1;
    else               id_bubble <= pd_bubble;
  end

  // EX stage
  assign bu_flush = core.ex_units.bu_flush_o;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      ex_pc <= PC_INIT;
      ex_inst <= NOP;
    end else begin 
      ex_pc <= id_pc;
      ex_inst <= id_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) ex_bubble <= 1'b1;
    else ex_bubble <= id_bubble;
  end

  // MEM stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      mem_pc <= PC_INIT;
      mem_inst <= NOP;
    end else begin 
      mem_pc <= ex_pc;
      mem_inst <= ex_inst;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) mem_bubble <= 1'b1;
    else mem_bubble <= ex_bubble;
  end

  // WB stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      wb_pc <= PC_INIT;
      wb_inst <= NOP;
    end else begin 
      wb_pc <= mem_pc;
      wb_inst <= mem_inst;
    end
  end

  //----------------------------------------------
  //  Properties for verifying pipeline follower  
  //----------------------------------------------

endmodule

bind riscv_top_ahb3lite isa isa_prop(
  .clk(HCLK),
  .rst_n(HRESETn)
  ); 
