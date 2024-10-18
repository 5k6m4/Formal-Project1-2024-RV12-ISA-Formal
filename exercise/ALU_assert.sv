module ALU_props(
  input clk,
  input rst,
  input [3:0] A,  // 4-bit input A
  input [3:0] B,  // 4-bit input B
  input control,  // Control bit (0 for subtract, 1 for add)
  input [3:0] Y   // 4-bit registered output
);

property ASSERT_ADD;
  @(posedge clk) disable iff(rst)
  control |=> Y == $past(A + B);
endproperty
addition_assert: assert property(ASSERT_ADD);

subtraction_assert: assert property(
  @(posedge clk) disable iff(rst)
  ~control |=> Y == $past(A - B)
);

endmodule

bind ALU ALU_props ALU_props_inst(
  .clk(clk),
  .rst(rst),
  .A(A),
  .B(B),
  .control(control),
  .Y(Y)
);