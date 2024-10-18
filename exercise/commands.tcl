clear -all
analyze -v2k ALU.v
analyze -sv ALU_assert.sv
elaborate -top ALU
clock clk
reset rst
prove -all