module isa (
  input clk,
  input rst_n
  );

endmodule

bind riscv_top_ahb3lite isa isa_prop(
  .clk(HCLK),
  .rst_n(HRESETn)
  );