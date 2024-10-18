# reset Jasper environment
clear -all
check_cov -init -type all

# analyze source code
analyze -sv [glob ./source/RV12/rtl/verilog/pkg/*sv]
analyze -sv [glob ./source/RV12/rtl/verilog/core/cache/*.sv]
analyze -sv [glob ./source/RV12/rtl/verilog/core/ex/*.sv]
analyze -sv [glob ./source/RV12/rtl/verilog/core/memory/*.sv]
analyze -sv [glob ./source/RV12/rtl/verilog/core/mmu/*.sv]
analyze -sv [glob ./source/RV12/rtl/verilog/core/*.sv]
analyze -sv [glob ./source/RV12/submodules/ahb3lite_pkg/rtl/verilog/*.sv]
analyze -sv [glob ./source/RV12/submodules/memory/rtl/verilog/*.sv]
analyze -sv [glob ./source/RV12/rtl/verilog/ahb3lite/*.sv]

# analyze assertion property
analyze -sv [glob ./property/isa.sv]

# elaborate top module
elaborate -top  riscv_top_ahb3lite

prove -all