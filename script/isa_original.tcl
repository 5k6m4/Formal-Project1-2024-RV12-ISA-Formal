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

# turn off debug mode
assume {core.du_stall == 1'b0}
assume {core.du_stall_if == 1'b0}
assume {core.du_re_rf == 1'b0}
assume {core.dbg_we_i == 1'b0}
assume {core.int_rf.du_we_rf_i == 0}
assume {core.cpu_state.du_we_csr_i == 0}

# trun off exception
stopat core.if_unit.parcel_exceptions
assume {core.if_unit.parcel_exceptions == 1'b0}
assume {core.wb_exceptions == 1'b0}
assume {core.id_unit.my_exceptions == 1'b0}
assume {dmem_ctrl_inst.pma_exception == 1'b0}

# icache always hit
stopat core.if_unit.imem_parcel_valid_i
assume {core.if_unit.imem_parcel_valid_i == 1'b1}

# always fetch legal instruction
stopat core.if_unit.imem_parcel_i
assume {core.if_unit.imem_parcel_i[6:0] == 7'b0110111 ||
        core.if_unit.imem_parcel_i[6:0] == 7'b0010111 ||
        core.if_unit.imem_parcel_i[6:0] == 7'b1101111 ||
        core.if_unit.imem_parcel_i[6:0] == 7'b1100111 ||
        (core.if_unit.imem_parcel_i[6:0] == 7'b1100011
            && core.if_unit.imem_parcel_i[14:12] != 3'b010
            && core.if_unit.imem_parcel_i[14:12] != 3'b011) ||
        core.if_unit.imem_parcel_i[6:0] == 7'b0010011 ||
        (core.if_unit.imem_parcel_i[6:0] == 7'b0110011
            && (core.if_unit.imem_parcel_i[31:25] == 7'b0000000
                || core.if_unit.imem_parcel_i[31:25] == 7'b0100000)) ||
        (core.if_unit.imem_parcel_i[6:0] == 7'b0001111
            && (core.if_unit.imem_parcel_i[14:12] == 3'b000
                || core.if_unit.imem_parcel_i[14:12] == 3'b001))}
      # Load, Store
      #  ||(core.if_unit.imem_parcel_i[6:0] == 7'b0000011
      #      && core.if_unit.imem_parcel_i[14:12] != 3'b011
      #      && core.if_unit.imem_parcel_i[14:12] != 3'b110
      #      && core.if_unit.imem_parcel_i[14:12] != 3'b111) ||
      #  (core.if_unit.imem_parcel_i[6:0] == 7'b0100011
      #      && (core.if_unit.imem_parcel_i[14:12] == 3'b000
      #          || core.if_unit.imem_parcel_i[14:12] == 3'b001
      #          || core.if_unit.imem_parcel_i[14:12] == 3'b010))}
      # Zicsr
      #  ||(core.if_unit.imem_parcel_i[6:0] == 7'b1110011
      #      && core.if_unit.imem_parcel_i[14:12] != 3'b100)}

# set clock and reset signal
clock HCLK
reset ~HRESETn

# set maximum runtime
set_prove_time_limit 259200s

prove -all