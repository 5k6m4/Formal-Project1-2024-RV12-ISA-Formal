module ALU (
  input clk,
  input rst,
  input [3:0] A,       // 4-bit input A
  input [3:0] B,       // 4-bit input B
  input control,       // Control bit (0 for subtract, 1 for add)
  output reg [3:0] Y   // 4-bit registered output
);

  always @(posedge clk) begin
    if(rst) begin
      Y <= 4'b0;
    end
    else begin
      if (control) // If control is 1, perform addition
        Y <= A + B;
      else         // If control is 0, perform subtraction
        Y <= A - B;
      end
  end
endmodule