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
  logic if_bubble, pd_bubble, id_bubble, ex_bubble, mem_bubble, wb_bubble;
  logic id_bubble_q;
  logic id_stall;
  logic bu_flush;
  logic ex_exception;
  logic ex_is_branch, mem_is_branch, wb_is_branch;

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
  assign id_bubble = id_bubble_q | bu_flush;
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
      id_bubble_q <= 1'b1;
    end else if(bu_flush || id_stall || ex_exception) begin
      id_bubble_q <= 1'b1;
    end else begin
      id_bubble_q <= pd_bubble;
    end
  end

  // EX stage
  assign bu_flush = core.ex_units.bu_flush_o;
  assign ex_exception = core.ex_units.ex_exceptions_o.any;
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
    end else if(ex_exception)begin
      ex_bubble <= 1'b1;
    end else begin
      ex_bubble <= id_bubble;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      ex_is_branch <= 1'b0;
    end else if(id_inst[6:2] == 5'b11000)begin
      ex_is_branch <= 1'b1;
    end else begin
      ex_is_branch <= 1'b0;
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
      mem_is_branch <= 1'b0;
    end else begin
      mem_bubble <= ex_bubble;
      mem_is_branch <= ex_is_branch;
    end
  end

  // WB stage
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      wb_pc <= 32'h200; //PC_INIT
      wb_inst <= 32'h13; //NOP
      wb_is_branch <= 1'b0;
      wb_bubble <= 1'b1;
    end else begin 
      wb_pc <= mem_pc;
      wb_inst <= mem_inst;
      wb_is_branch <= mem_is_branch;
      wb_bubble <= mem_bubble;
    end
  end

`ifdef PIPELINE_FOLLOWER_CHECK
  //----------------------------------------------
  //  Properties for verifying pipeline follower  
  //----------------------------------------------
  pd_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    pd_bubble == core.pd_unit.pd_insn_o.bubble
  );
  pd_pc_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~pd_bubble) 
    |->
    pd_pc == core.pd_unit.pd_pc_o
  );
  pd_inst_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~pd_bubble) 
    |->
    pd_inst == core.pd_unit.pd_insn_o.instr
  );
  id_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    id_bubble == core.id_unit.id_insn_o.bubble
  );
  id_pc_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~id_bubble) 
    |->
    id_pc == core.id_unit.id_pc_o
  );
  id_inst_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~id_bubble) 
    |->
    id_inst == core.id_unit.id_insn_o.instr
  );
  ex_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (ex_bubble | ex_is_branch) == core.ex_units.ex_insn_o.bubble
  );
  ex_pc_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~ex_bubble) 
    |->
    ex_pc == core.ex_units.ex_pc_o
  );
  ex_inst_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~ex_bubble) 
    |->
    ex_inst == core.ex_units.ex_insn_o.instr
  );
  mem_bubble_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (mem_bubble | mem_is_branch) == core.mem_unit0.mem_insn_o.bubble
  );
  mem_pc_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble) 
    |->
    mem_pc == core.mem_unit0.mem_pc_o
  );
  mem_inst_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble) 
    |->
    mem_inst == core.mem_unit0.mem_insn_o.instr
  );
  wb_pc_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble)
    |=>
    wb_pc == core.wb_unit.wb_pc_o
  );
  wb_inst_check: assert property(
    @(posedge clk) disable iff(!rst_n)
    (~mem_bubble)
    |=>
    wb_inst == core.wb_unit.wb_insn_o.instr
  );
`endif
  
  //-----------------
  //  Register File
  //-----------------

  // Logics for verifying register file
  logic [31:0][0:31] regfile;
  logic rf_pd_stall, rf_id_stall;
  logic [4:0] rf_rs1_idx, rf_rs2_idx, rf_rd_idx;
  logic [31:0] rf_rs1_value, rf_rs2_value, rf_wb_value;
  logic rf_we;
  logic [4:0] rf_stable_reg_idx;

  // get the value stored in RV12 register file
  always_comb begin
    regfile[0] = 32'd0;
    regfile[1] = core.int_rf.rf[1];
    regfile[2] = core.int_rf.rf[2];
    regfile[3] = core.int_rf.rf[3];
    regfile[4] = core.int_rf.rf[4];
    regfile[5] = core.int_rf.rf[5];
    regfile[6] = core.int_rf.rf[6];
    regfile[7] = core.int_rf.rf[7];
    regfile[8] = core.int_rf.rf[8];
    regfile[9] = core.int_rf.rf[9];
    regfile[10] = core.int_rf.rf[10];
    regfile[11] = core.int_rf.rf[11];
    regfile[12] = core.int_rf.rf[12];
    regfile[13] = core.int_rf.rf[13];
    regfile[14] = core.int_rf.rf[14];
    regfile[15] = core.int_rf.rf[15];
    regfile[16] = core.int_rf.rf[16];
    regfile[17] = core.int_rf.rf[17];
    regfile[18] = core.int_rf.rf[18];
    regfile[19] = core.int_rf.rf[19];
    regfile[20] = core.int_rf.rf[20];
    regfile[21] = core.int_rf.rf[21];
    regfile[22] = core.int_rf.rf[22];
    regfile[23] = core.int_rf.rf[23];
    regfile[24] = core.int_rf.rf[24];
    regfile[25] = core.int_rf.rf[25];
    regfile[26] = core.int_rf.rf[26];
    regfile[27] = core.int_rf.rf[27];
    regfile[28] = core.int_rf.rf[28];
    regfile[29] = core.int_rf.rf[29];
    regfile[30] = core.int_rf.rf[30];
    regfile[31] = core.int_rf.rf[31];
  end

  assign rf_pd_stall = core.int_rf.pd_stall_i;
  assign rf_id_stall = core.int_rf.id_stall_i;

  assign rf_rs1_idx = core.int_rf.rf_src1_i;
  assign rf_rs2_idx = core.int_rf.rf_src2_i;
  assign rf_rd_idx = core.wb_unit.wb_dst_o;
  
  assign rf_rs1_value = core.int_rf.rf_src1_q_o;
  assign rf_rs2_value = core.int_rf.rf_src2_q_o;
  assign rf_wb_value = core.wb_unit.wb_r_o;

  assign rf_we = core.wb_unit.wb_we_o;
  
`ifdef REGFILE_CHECK
  //------------------------------------------
  //  Properties for verifying register file
  //------------------------------------------
  rf_read_rs1: assert property(
    @(posedge clk) disable iff(!rst_n)
    (($past(rf_pd_stall) == 1'b0) && (rf_id_stall == 1'b0))
    |=>
    rf_rs1_value == $past(regfile[$past(rf_rs1_idx)])
  );

  rf_read_rs2: assert property(
    @(posedge clk) disable iff(!rst_n)
    (($past(rf_pd_stall) == 1'b0) && (rf_id_stall == 1'b0))
    |=>
    rf_rs2_value == $past(regfile[$past(rf_rs2_idx)])
  );
  
  rf_write: assert property(
    @(posedge clk) disable iff(!rst_n)
    ((rf_rd_idx != 5'd0) && (rf_we == 1'b1))
    |=>
    regfile[$past(rf_rd_idx)] == $past(rf_wb_value)
  );

  assume property(rf_stable_reg_idx != rf_rd_idx);
  rf_value_stable: assert property(
    @(posedge clk) disable iff(!rst_n)
    (rf_we == 1'b0)
    |=>
    regfile[$past(rf_stable_reg_idx)] == $past(regfile[rf_stable_reg_idx])
  );
`endif

  //-------------------------------------
  //  Logics for verifying instructions
  //-------------------------------------

  logic [4:0] wb_rd_idx;
  logic [31:0] wb_value;
  logic wb_we;

  logic [4:0] gold_wb_rs1_idx, gold_wb_rs2_idx, gold_wb_rd_idx;
  logic [31:0] gold_wb_rs1_value, gold_wb_rs2_value;
  logic gold_wb_we;

  assign wb_rd_idx = core.wb_unit.wb_dst_o;
  assign wb_value = core.wb_unit.wb_r_o;
  assign wb_we = core.wb_unit.wb_we_o;

  assign gold_wb_rs1_idx = wb_inst[19:15];
  assign gold_wb_rs2_idx = wb_inst[24:20];
  assign gold_wb_rd_idx = wb_inst[11:7];

  assign gold_wb_rs1_value = regfile[gold_wb_rs1_idx];
  assign gold_wb_rs2_value = regfile[gold_wb_rs2_idx];

  assign gold_wb_we = gold_wb_rd_idx != 5'b0;

`ifdef ANDI_CHECK
  //----------------
  //  I-type: andi
  //----------------

  logic andi_trigger;
  logic [31:0] andi_imm;
  logic [31:0] andi_golden;

  assign andi_trigger = (wb_inst[6:0] == 7'b0010011) && (wb_inst[14:12] == 3'b111) && !wb_bubble;
  assign andi_imm = {{20{wb_inst[31]}}, wb_inst[31:20]};
  assign andi_golden = gold_wb_rs1_value & andi_imm;

  //---------------------------------------------
  //  Properties for verifying instruction andi
  //---------------------------------------------
  andi_we: assert property(
    @(posedge clk) disable iff(!rst_n)
    andi_trigger
    |->
    wb_we == gold_wb_we
  );

  andi_rd_idx: assert property(
    @(posedge clk) disable iff(!rst_n)
    andi_trigger
    |->
    wb_rd_idx == gold_wb_rd_idx
  );

  andi_wb_value: assert property(
    @(posedge clk) disable iff(!rst_n)
    andi_trigger
    |->
    wb_value == andi_golden
  );
`endif

`ifdef AUIPC_CHECK
  //-----------------
  //  U-type: auipc
  //-----------------

  logic auipc_trigger;
  logic [31:0] auipc_imm;
  logic [31:0] auipc_golden;

  assign auipc_trigger = (wb_inst[6:0] == 7'b0010111) && !wb_bubble;
  assign auipc_imm = {wb_inst[31:12], 12'b0};
  assign auipc_golden = wb_pc + auipc_imm;

  //----------------------------------------------
  //  Properties for verifying instruction auipc
  //----------------------------------------------

  auipc_we: assert property(
    @(posedge clk) disable iff(!rst_n)
    auipc_trigger
    |->
    wb_we == gold_wb_we
  );

  auipc_rd: assert property(
    @(posedge clk) disable iff(!rst_n)
    auipc_trigger
    |->
    wb_rd_idx == gold_wb_rd_idx
  );

  auipc_wb_value: assert property(
    @(posedge clk) disable iff(!rst_n)
    auipc_trigger
    |->
    wb_value == auipc_golden
  );
`endif

`ifdef JAL_CHECK
  //-----------------
  //  J-type: jal
  //-----------------

  logic jal_trigger;
  logic [31:0] jal_imm;
  logic [31:0] jal_golden;
  logic [31:0] jal_target_pc;
  // jal_commited is a state indicates that there's a jal commit but has not found next valid inst yet
  // 0 -> waiting a jal to be commited
  // 1 -> waiting ~bubble
  logic jal_commited;

  assign jal_trigger = (wb_inst[6:0] == 7'b1101111) && !wb_bubble;
  assign jal_imm = {{12{wb_inst[31]}}, wb_inst[19:12], wb_inst[20], wb_inst[30:21], 1'b0};
  assign jal_golden = wb_pc + 4;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      jal_target_pc <= 32'd0;
    end else if (jal_trigger) begin
      jal_target_pc <= (wb_pc + jal_imm) & 32'hfffffffc;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      jal_commited <= 1'b0;
    end else if (jal_trigger) begin
      jal_commited <= 1'b1;
    end else if (jal_commited & (~wb_bubble)) begin
      jal_commited <= 1'b0;
    end
  end

  //--------------------------------------------
  //  Properties for verifying instruction jal  
  //--------------------------------------------

  jal_we: assert property(
    @(posedge clk) disable iff(!rst_n)
    jal_trigger
    |->
    wb_we == gold_wb_we
  );

  jal_rd: assert property(
    @(posedge clk) disable iff(!rst_n)
    jal_trigger
    |->
    wb_rd_idx == gold_wb_rd_idx
  );

  jal_wb_value: assert property(
    @(posedge clk) disable iff(!rst_n)
    jal_trigger
    |->
    wb_value == jal_golden
  );

   jal_nxt_valid_pc: assert property(
    @(posedge clk) disable iff(!rst_n)
    jal_commited & (~wb_bubble)
    |->
    (wb_pc == jal_target_pc)
  ); 
`endif

`ifdef LBU_CHECK
  //---------------
  //  L-type: lbu
  //---------------
  
  logic [31:0] ex_load_addr, mem_load_addr, wb_load_addr; // used to compare with gold_load_addr
  logic [31:0] ex_load_data, wb_load_data; // used to compute gold_wb_value

  assign ex_load_addr = core.ex_units.dmem_adr_o;
  assign ex_load_data = core.ex_units.dmem_q_i;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      mem_load_addr <= 32'b0;
      wb_load_addr <= 32'b0;
      wb_load_data <= 32'b0;
    end else begin
      mem_load_addr <= ex_load_addr;
      wb_load_addr <= mem_load_addr;
      wb_load_data <= ex_load_data;
    end
  end
  
  logic lbu_trigger;
  logic [31:0] lbu_imm;
  logic [31:0] lbu_load_addr_golden;
  logic [31:0] lbu_wb_value_golden;

  assign lbu_trigger = (wb_inst[6:0] == 7'b0000011) && (wb_inst[14:12] == 3'b100) && !wb_bubble;
  assign lbu_imm = {{20{wb_inst[31]}}, wb_inst[31:20]};
  assign lbu_load_addr_golden = gold_wb_rs1_value + lbu_imm;

  always_comb begin
    case(lbu_load_addr_golden[1:0])
      2'b00: lbu_wb_value_golden = {24'b0, wb_load_data[7:0]};
      2'b01: lbu_wb_value_golden = {24'b0, wb_load_data[15:8]};
      2'b10: lbu_wb_value_golden = {24'b0, wb_load_data[23:16]};
      2'b11: lbu_wb_value_golden = {24'b0, wb_load_data[31:24]};
    endcase
  end
  
  //--------------------------------------------
  //  Properties for verifying instruction lbu  
  //--------------------------------------------

  lbu_load_addr: assert property(
    @(posedge clk) disable iff(!rst_n)
    lbu_trigger
    |->
    wb_load_addr == lbu_load_addr_golden
  );

  lbu_we: assert property(
    @(posedge clk) disable iff(!rst_n)
    lbu_trigger
    |->
    wb_we == gold_wb_we
  );

  lbu_rd: assert property(
    @(posedge clk) disable iff(!rst_n)
    lbu_trigger
    |->
    wb_rd_idx == gold_wb_rd_idx
  );

  lbu_wb_value: assert property(
    @(posedge clk) disable iff(!rst_n)
    lbu_trigger
    |->
    wb_value == lbu_wb_value_golden
  );
`endif

endmodule

bind riscv_top_ahb3lite isa isa_prop(
  .clk(HCLK),
  .rst_n(HRESETn)
); 
