# Full TOP RTL file list
sys_pkg.sv
csr_generated/sys_csr_pkg.sv

# Accelerator
pe.sv
array.sv
systolic_array.sv
pp_reg_reg.sv
relu.sv
postproc.sv
sys_datapath.sv

# APB interface
apb_bridge.sv
csr_generated/sys_csr.sv

# CDC and reset
reset_sync.sv
async_fifo.sv
cdc_sync_bit.sv
cdc_pulse_sync.sv
mem_cdc.sv

# Memory interface and write path
mem_arb.sv
sram_wrap.sv
res_wr.sv

# core control and chip integeration
seq_ctrl.sv
sys_top.sv
