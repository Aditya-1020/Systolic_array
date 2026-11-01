# Systolic Accelerator Architecture Redesign

## Design goal

Keep the existing N x N systolic compute mesh (`array.sv` and `pe.sv`) and its valid/ready backpressure behavior. Replace the local ping-pong memory arrangement with a memory-agnostic DMA front end controlled by a PeakRDL-generated CSR block. The accelerator must not instantiate or know about a particular SRAM macro.

## Target hierarchy

- `systolic_top.sv`: integration boundary. Instantiates generated CSR RTL, synchronized reset, DMA front end, `systolic_array`, and `postproc`. Exposes APB4 for software and AXI4 master channels for memory traffic.
- `csr_regs` (generated): source of truth for software-visible configuration and status fields.
- `dma_frontend.sv`: groups the read path currently in `feeder.sv` and the write path currently in `result_writer.sv`. Keep read and write control independent inside this module; do not force them to share one FSM. It performs external-memory transactions and produces/consumes the existing stream-style interfaces.
- `systolic_array.sv`: keep its stream-oriented interface, scheduling, skewing, valid tracking, backpressure and clock-gated advancement.
- `array.sv`: keep the N x N mesh.
- `pe.sv`: keep each processing element.
- `postproc.sv`: keep as the pipelined rounding/shift/ReLU/saturation stage.
- Shared data RAM and CPU/accelerator arbitration live outside this accelerator IP, in the SoC interconnect/memory subsystem.

The reset synchronizer may remain a separate reusable module or be written inline in the top to reduce file count. Use exactly one synchronized reset source for this accelerator hierarchy.

## Data flow

1. The RISC-V CPU writes data and weights into shared data RAM.
2. Software programs the accelerator's base addresses, activation-vector count and post-processing configuration through APB4 CSR registers.
3. Software writes a one-shot `LOAD_WEIGHTS` command. The DMA read path fetches N weight vectors and streams them to `systolic_array`.
4. After weights are loaded, software writes a one-shot `START` command. The read path fetches activation vectors from the activation base, in order, and streams them to the array.
5. `systolic_array` produces accumulator vectors. `postproc` applies the configured shift, ReLU and saturation while preserving valid/ready backpressure.
6. The DMA write path accepts each processed result vector and writes it to the configured destination base in shared data RAM.
7. The operation is marked done only after the final output's AXI write response has completed successfully, not merely when its data was accepted by the local stream.

## Proposed minimal CSR map

Assume a 32-bit software CSR bus and byte-addressed memory pointers. Adjust address width if the target system uses wider physical addresses.

| Offset | Register | Proposed fields and behavior |
|---|---|---|
| `0x00` | `CMD` | `LOAD_WEIGHTS` bit 0 and `START` bit 1; write-one-pulse commands, not persistent level signals |
| `0x04` | `STATUS` | `BUSY` bit 0, `WEIGHTS_LOADED` bit 1, `COMPUTING` bit 2, `STALLED` bit 3, sticky `DONE` bit 4, sticky `ERROR` bit 5 |
| `0x08` | `WEIGHT_BASE` | Software-owned base address for N weight vectors |
| `0x0C` | `ACT_BASE` | Software-owned base address for activation vectors |
| `0x10` | `DST_BASE` | Software-owned destination address for output vectors |
| `0x14` | `COUNT` | Number of activation vectors / output vectors for the operation; require nonzero unless explicitly defined otherwise |
| `0x18` | `POSTPROC_CFG` | `SHIFT[4:0]`, `RELU_EN` bit 8 |

Define sticky-bit clearing explicitly: for example, software writes one to clear `DONE` or `ERROR`. The command write should be accepted only when the engine is idle; a command while busy should set an error or be rejected in a documented way.

If bias remains required, do not try to pack the current N*OUT_W-bit bias bus into a single ordinary CSR. Either add one register per lane, use a small bias memory, or hold bias at zero for the first integration milestone.

## Important address rule

The CSR base-address registers are configuration, not live DMA counters. Hardware must not increment or overwrite `WEIGHT_BASE`, `ACT_BASE`, or `DST_BASE`.

When a command is accepted, capture the configuration into internal active/shadow registers. Generate independent working addresses from those snapshots. The active address counters can advance when memory transfers are accepted while the software-visible CSR values remain unchanged.

For the current default parameters, N=8 and DW=8 gives a 64-bit vector, so one vector is 8 bytes on a 64-bit memory interface. Thus activation and output addresses advance by 8 bytes per vector. Make the address semantics explicitly byte-based; do not carry the current ping-pong bank bit into the external address format.

The current `feeder.sv` reads the N weight vectors in descending word-address order, starting at `i_w_base + N - 1`. Preserve that ordering in the first refactor, or deliberately change the weight-memory layout and verify the numerical result. Do not accidentally switch to ascending order during the bus conversion.

## Backpressure and completion rules

- A stream transfer occurs only on `valid && ready`.
- Do not drop read-return data when the array deasserts ready; retain the small skid/FIFO buffering behavior from `feeder.sv` or replace it with an equivalent tested queue.
- The array and post-processing pipeline freeze according to their existing backpressure rules. Keep the clock-gating behavior unchanged during the first architectural refactor.
- The DMA write path must hold output data and its destination address stable until the corresponding bus handshakes complete.
- Handle AXI read and write response errors and expose a CSR error status.
- `BUSY` should span command acceptance through completion of the final output write response. `STALLED` can be a derived status indicating an active transfer is blocked by a downstream/upstream handshake or bus wait.
- `DONE` must not be asserted only because the array emitted its final vector; that vector may still be blocked in post-processing or awaiting an external memory response.

## Mapping from current files

- `systolic_top.sv`: remove the local host-buffer interface (`i_host_w_*`, `i_host_r_*`, `i_act_push`, `i_res_pop`) from the accelerator-facing design. Replace it with APB4 CSR and AXI4 master ports.
- `pp_buf_1r1w.sv`: remove from the accelerator. It can remain as a testbench or SoC memory wrapper, outside this IP.
- `feeder.sv`: reuse its read sequencing, weight order, activation count handling and return-data buffering within `dma_frontend.sv`.
- `result_writer.sv`: replace bank toggling and local word counter with a DMA write path using `DST_BASE` and an output beat counter.
- `systolic_array.sv`, `array.sv`, `pe.sv`, `postproc.sv`: retain as separate compute/datapath boundaries during the first refactor.
- `cells_clkgate.v`: retain the clock-gate abstraction only if its implementation matches the target PDK. The current wrapper instantiates a SkyWater SKY130 standard cell and is not portable to a GPDK90 library as written.
- Reset synchronizer: retain the existing two-flop synchronized deassertion behavior and distribute its output consistently.

## Recommended implementation order

1. Freeze `array.sv`, `pe.sv` and the stream-level contract of `systolic_array.sv` with a passing simulation baseline.
2. Replace local buffer behavior with a simple memory request/response testbench model and explicit byte addresses. Validate weight ordering and activation sequencing before introducing AXI complexity.
3. Add the generated CSR block and one-shot command semantics; snapshot the descriptor at command acceptance.
4. Implement the DMA read and write control in `dma_frontend.sv`, including response buffering, `valid && ready` rules and error handling.
5. Add the AXI4 master wrapper/interconnect connection to shared RAM and RISC-V arbitration.
6. Verify end-to-end output values, stalls, reset, command rejection while busy, AXI wait states, and errors.
7. Only after functional verification, run Genus and Innovus. Check that the clock-gating cell maps to the target technology before interpreting physical results.
