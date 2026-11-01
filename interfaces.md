# PICORV32
```sv
odule picorv32 #(
	parameter [ 0:0] ENABLE_COUNTERS = 1,
	parameter [ 0:0] ENABLE_COUNTERS64 = 1,
	parameter [ 0:0] ENABLE_REGS_16_31 = 1,
	parameter [ 0:0] ENABLE_REGS_DUALPORT = 1,
	parameter [ 0:0] LATCHED_MEM_RDATA = 0,
	parameter [ 0:0] TWO_STAGE_SHIFT = 1,
	parameter [ 0:0] BARREL_SHIFTER = 0,
	parameter [ 0:0] TWO_CYCLE_COMPARE = 0,
	parameter [ 0:0] TWO_CYCLE_ALU = 0,
	parameter [ 0:0] COMPRESSED_ISA = 0,
	parameter [ 0:0] CATCH_MISALIGN = 1,
	parameter [ 0:0] CATCH_ILLINSN = 1,
	parameter [ 0:0] ENABLE_PCPI = 0,
	parameter [ 0:0] ENABLE_MUL = 0,
	parameter [ 0:0] ENABLE_FAST_MUL = 0,
	parameter [ 0:0] ENABLE_DIV = 0,
	parameter [ 0:0] ENABLE_IRQ = 0,
	parameter [ 0:0] ENABLE_IRQ_QREGS = 1,
	parameter [ 0:0] ENABLE_IRQ_TIMER = 1,
	parameter [ 0:0] ENABLE_TRACE = 0,
	parameter [ 0:0] REGS_INIT_ZERO = 0,
	parameter [31:0] MASKED_IRQ = 32'h 0000_0000,
	parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET = 32'h 0000_0000,
	parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010,
	parameter [31:0] STACKADDR = 32'h ffff_ffff
) (
	input clk, resetn,
	output reg trap,

	output reg        mem_valid,
	output reg        mem_instr,
	input             mem_ready,

	output reg [31:0] mem_addr,
	output reg [31:0] mem_wdata,
	output reg [ 3:0] mem_wstrb,
	input      [31:0] mem_rdata,

	// Look-Ahead Interface
	output            mem_la_read,
	output            mem_la_write,
	output     [31:0] mem_la_addr,
	output reg [31:0] mem_la_wdata,
	output reg [ 3:0] mem_la_wstrb,

	// Pico Co-Processor Interface (PCPI)
	output reg        pcpi_valid,
	output reg [31:0] pcpi_insn,
	output     [31:0] pcpi_rs1,
	output     [31:0] pcpi_rs2,
	input             pcpi_wr,
	input      [31:0] pcpi_rd,
	input             pcpi_wait,
	input             pcpi_ready,

	// IRQ Interface
	input      [31:0] irq,
	output reg [31:0] eoi,

`ifdef RISCV_FORMAL
	output reg        rvfi_valid,
	output reg [63:0] rvfi_order,
	output reg [31:0] rvfi_insn,
	output reg        rvfi_trap,
	output reg        rvfi_halt,
	output reg        rvfi_intr,
	output reg [ 1:0] rvfi_mode,
	output reg [ 1:0] rvfi_ixl,
	output reg [ 4:0] rvfi_rs1_addr,
	output reg [ 4:0] rvfi_rs2_addr,
	output reg [31:0] rvfi_rs1_rdata,
	output reg [31:0] rvfi_rs2_rdata,
	output reg [ 4:0] rvfi_rd_addr,
	output reg [31:0] rvfi_rd_wdata,
	output reg [31:0] rvfi_pc_rdata,
	output reg [31:0] rvfi_pc_wdata,
	output reg [31:0] rvfi_mem_addr,
	output reg [ 3:0] rvfi_mem_rmask,
	output reg [ 3:0] rvfi_mem_wmask,
	output reg [31:0] rvfi_mem_rdata,
	output reg [31:0] rvfi_mem_wdata,

	output reg [63:0] rvfi_csr_mcycle_rmask,
	output reg [63:0] rvfi_csr_mcycle_wmask,
	output reg [63:0] rvfi_csr_mcycle_rdata,
	output reg [63:0] rvfi_csr_mcycle_wdata,

	output reg [63:0] rvfi_csr_minstret_rmask,
	output reg [63:0] rvfi_csr_minstret_wmask,
	output reg [63:0] rvfi_csr_minstret_rdata,
	output reg [63:0] rvfi_csr_minstret_wdata,
`endif

	// Trace Interface
	output reg        trace_valid,
	output reg [35:0] trace_data
);
```
# Ibex32IM
```sv
module ibex_top import ibex_pkg::*; import ibex_cheriot_pkg::*; #(
  parameter ibex_pkg::base_isa_e    BaseIsa                      = ibex_pkg::BaseIsaRV32I,
  parameter bit                     PMPEnable                    = 1'b0,
  parameter int unsigned            PMPGranularity               = 0,
  parameter int unsigned            PMPNumRegions                = 4,
  parameter int unsigned            MHPMCounterNum               = 0,
  parameter int unsigned            MHPMCounterWidth             = 40,
  parameter ibex_pkg::pmp_cfg_t     PMPRstCfg[PMP_MAX_REGIONS]   = ibex_pkg::PmpCfgRst,
  parameter logic [PMP_ADDR_MSB:0]  PMPRstAddr[PMP_MAX_REGIONS]  = ibex_pkg::PmpAddrRst,
  parameter ibex_pkg::pmp_mseccfg_t PMPRstMsecCfg                = ibex_pkg::PmpMseccfgRst,
  parameter int unsigned            CheriotRevBitmapAddrWidth    = 32'd11,
  parameter int unsigned            CheriotRevBitmapBaseAddr     = 32'h0,
  parameter bit                     RV32E                        = 1'b0,
  parameter rv32m_e                 RV32M                        = RV32MFast,
  parameter rv32b_e                 RV32B                        = RV32BNone,
  parameter rv32zc_e                RV32ZC                       = RV32ZcaZcbZcmp,
  parameter regfile_e               RegFile                      = RegFileFF,
  parameter bit                     BranchTargetALU              = 1'b0,
  parameter bit                     WritebackStage               = 1'b0,
  parameter bit                     ICache                       = 1'b0,
  parameter bit                     ICacheECC                    = 1'b0,
  parameter bit                     BranchPredictor              = 1'b0,
  parameter bit                     DbgTriggerEn                 = 1'b0,
  parameter int unsigned            DbgHwBreakNum                = 1,
  parameter bit                     SecureIbex                   = 1'b0,
  parameter int unsigned            LockstepOffset               = 1,
  parameter bit                     MemECC                       = SecureIbex,
  parameter int unsigned            MemDataWidth                 = MemECC ? 32 + 7 : 32,
  parameter bit                     ICacheScramble               = 1'b0,
  parameter int unsigned            ICacheScrNumPrinceRoundsHalf = 2,
  parameter bit                     ICacheTweakInfection         = SecureIbex,
  parameter lfsr_seed_t             RndCnstLfsrSeed              = RndCnstLfsrSeedDefault,
  parameter lfsr_perm_t             RndCnstLfsrPerm              = RndCnstLfsrPermDefault,
  parameter int unsigned            DmBaseAddr                   = 32'h1A110000,
  parameter int unsigned            DmAddrMask                   = 32'h00000FFF,
  parameter int unsigned            DmHaltAddr                   = 32'h1A110800,
  parameter int unsigned            DmExceptionAddr              = 32'h1A110808,
  // Default seed and nonce for scrambling
  parameter logic [SCRAMBLE_KEY_W-1:0]   RndCnstIbexKey          = RndCnstIbexKeyDefault,
  parameter logic [SCRAMBLE_NONCE_W-1:0] RndCnstIbexNonce        = RndCnstIbexNonceDefault,
  // mvendorid: encoding of manufacturer/provider
  // 0 indicates this field is not implemented. Ibex implementers may wish to set their
  // own JEDEC ID here.
  parameter logic [31:0]            CsrMvendorId                 = 32'b0,
  // mimpid: encoding of processor implementation version
  // 0 indicates this field is not implemented. Ibex implementers may wish to indicate an
  // RTL/netlist version here using their own unique encoding (e.g. 32 bits of the git hash of the
  // implemented commit).
  parameter logic [31:0]            CsrMimpId                    = 32'b0
) (
  // Clock and Reset
  input  logic                                                         clk_i,
  input  logic                                                         rst_ni,

  // enable all clock gates for testing
  input  logic                                                         test_en_i,
  input  prim_ram_1p_pkg::ram_1p_cfg_req_t [ibex_pkg::IC_NUM_WAYS-1:0] ram_cfg_icache_tag_i,
  output prim_ram_1p_pkg::ram_1p_cfg_rsp_t [ibex_pkg::IC_NUM_WAYS-1:0] ram_cfg_icache_tag_o,
  input  prim_ram_1p_pkg::ram_1p_cfg_req_t [ibex_pkg::IC_NUM_WAYS-1:0] ram_cfg_icache_data_i,
  output prim_ram_1p_pkg::ram_1p_cfg_rsp_t [ibex_pkg::IC_NUM_WAYS-1:0] ram_cfg_icache_data_o,

  input  ibex_mubi_t                                                   cheriot_enable_i,

  input  logic [31:0]                                                  hart_id_i,
  input  logic [31:0]                                                  boot_addr_i,

  input  logic [31:0]                                                  trvk_heap_base_addr_i,

  // Instruction memory interface
  output logic                                                         instr_req_o,
  input  logic                                                         instr_gnt_i,
  input  logic                                                         instr_rvalid_i,
  output logic [31:0]                                                  instr_addr_o,
  input  logic [31:0]                                                  instr_rdata_i,
  input  logic [6:0]                                                   instr_rdata_intg_i,
  input  logic                                                         instr_err_i,

  // Data memory interface
  output logic                                                         data_req_o,
  input  logic                                                         data_gnt_i,
  input  logic                                                         data_rvalid_i,
  output logic                                                         data_we_o,
  output logic [3:0]                                                   data_be_o,
  output logic [31:0]                                                  data_addr_o,
  output logic [31:0]                                                  data_wdata_o,
  output logic [6:0]                                                   data_wdata_intg_o,
  output logic                                                         data_tag_o,
  input  logic [31:0]                                                  data_rdata_i,
  input  logic [6:0]                                                   data_rdata_intg_i,
  input  logic                                                         data_tag_i,
  input  logic                                                         data_err_i,

  // TRVK revocation bitmap read interface
  output logic                                                         trvk_revbm_req_o,
  input  logic                                                         trvk_revbm_gnt_i,
  input  logic                                                         trvk_revbm_rvalid_i,
  output logic [31:0]                                                  trvk_revbm_addr_o,
  input  logic [31:0]                                                  trvk_revbm_rdata_i,
  input  logic [6:0]                                                   trvk_revbm_rdata_intg_i,
  input  logic                                                         trvk_revbm_err_i,

  // Interrupt inputs
  input  logic                                                         irq_software_i,
  input  logic                                                         irq_timer_i,
  input  logic                                                         irq_external_i,
  input  logic [14:0]                                                  irq_fast_i,
  // non-maskeable interrupt
  input  logic                                                         irq_nm_i,

  // Scrambling Interface
  input  logic                                                         scramble_key_valid_i,
  input  logic [SCRAMBLE_KEY_W-1:0]                                    scramble_key_i,
  input  logic [SCRAMBLE_NONCE_W-1:0]                                  scramble_nonce_i,
  output logic                                                         scramble_req_o,

  // Debug Interface
  input  logic                                                         debug_req_i,
  output crash_dump_t                                                  crash_dump_o,
  output logic                                                         double_fault_seen_o,

  // RISC-V Formal Interface
  // Does not comply with the coding standards of _i/_o suffixes, but follows
  // the convention of RISC-V Formal Interface Specification.
`ifdef RVFI
  output logic                                                        rvfi_valid,
  output logic [63:0]                                                 rvfi_order,
  output logic [31:0]                                                 rvfi_insn,
  output logic                                                        rvfi_trap,
  output logic                                                        rvfi_halt,
  output logic                                                        rvfi_intr,
  output logic [ 1:0]                                                 rvfi_mode,
  output logic [ 1:0]                                                 rvfi_ixl,
  output logic [ 4:0]                                                 rvfi_rs1_addr,
  output logic [ 4:0]                                                 rvfi_rs2_addr,
  output logic [ 4:0]                                                 rvfi_rs3_addr,
  output logic [31:0]                                                 rvfi_rs1_rdata,
  output logic [31:0]                                                 rvfi_rs2_rdata,
  output logic [31:0]                                                 rvfi_rs3_rdata,
  output cap_t                                                        rvfi_rs1_rcap,
  output cap_t                                                        rvfi_rs2_rcap,
  output cap_t                                                        rvfi_rd_wcap,
  output logic [ 4:0]                                                 rvfi_rd_addr,
  output logic [31:0]                                                 rvfi_rd_wdata,
  output logic [31:0]                                                 rvfi_pc_rdata,
  output logic [31:0]                                                 rvfi_pc_wdata,
  output logic [31:0]                                                 rvfi_mem_addr,
  output logic [ 3:0]                                                 rvfi_mem_rmask,
  output logic [ 3:0]                                                 rvfi_mem_wmask,
  output logic [31:0]                                                 rvfi_mem_rdata,
  output logic [31:0]                                                 rvfi_mem_wdata,
  output logic                                                        rvfi_mem_is_cap,
  output cap_t                                                        rvfi_mem_rcap,
  output cap_t                                                        rvfi_mem_wcap,
  output logic [31:0]                                                 rvfi_ext_pre_mip,
  output logic [31:0]                                                 rvfi_ext_post_mip,
  output logic                                                        rvfi_ext_nmi,
  output logic                                                        rvfi_ext_nmi_int,
  output logic                                                        rvfi_ext_debug_req,
  output logic                                                        rvfi_ext_debug_mode,
  output logic                                                        rvfi_ext_rf_wr_suppress,
  output logic [63:0]                                                 rvfi_ext_mcycle,
  output logic [31:0]                                                 rvfi_ext_mhpmcounters [10],
  output logic [31:0]                                                 rvfi_ext_mhpmcountersh [10],
  output logic                                                        rvfi_ext_ic_scr_key_valid,
  output logic                                                        rvfi_ext_irq_valid,
  output logic                                                        rvfi_ext_expanded_insn_valid,
  output logic [15:0]                                                 rvfi_ext_expanded_insn,
  output logic                                                        rvfi_ext_expanded_insn_last,
`endif

  // CPU Control Signals
  input  ibex_mubi_t                                                  fetch_enable_i,
  input  ibex_mubi_t                                                  mcounteren_writable_i,
  output logic                                                        alert_minor_o,
  output logic                                                        alert_major_internal_o,
  output logic                                                        alert_major_bus_o,
  output logic                                                        core_sleep_o,

  // DFT bypass controls
  input logic                                                         scan_rst_ni,

  // Lockstep signals
  output ibex_mubi_t                                                  lockstep_cmp_en_o,

  // Shadow core data interface outputs
  output logic                                                        data_req_shadow_o,
  output logic                                                        data_we_shadow_o,
  output logic [3:0]                                                  data_be_shadow_o,
  output logic [31:0]                                                 data_addr_shadow_o,
  output logic [31:0]                                                 data_wdata_shadow_o,
  output logic [6:0]                                                  data_wdata_intg_shadow_o,

  // Shadow core instruction interface outputs
  output logic                                                        instr_req_shadow_o,
  output logic [31:0]                                                 instr_addr_shadow_o
);
```