# AXI4-Lite RAM Wrapper (Verilog)

An **AXI4-Lite slave wrapper around a synchronous RAM**, written in Verilog. It implements all five AXI4-Lite channels (AW, W, B, AR, R) as separate modules, supports **byte-lane writes using `WSTRB`**, and is verified with a **self-checking testbench that acts as the AXI master** (in place of a processor).

Simulated and verified in **Xilinx Vivado**.

---

## Features

- Full AXI4-Lite slave interface: 5 independent channels with VALID/READY handshakes
- Parameterizable data width and address width (`DATA_WIDTH`, `ADDR_WIDTH`)
- Byte-enable writes through `WSTRB`
- Write address and write data are accepted independently; the RAM write fires only when **both** have arrived
- Write response (`BRESP = OKAY`) sent after each write
- Synchronous RAM read, with a 1-cycle delay register so read data is valid when `RVALID` is asserted
- Self-checking testbench with task-based AXI master (`axi_write`, `axi_read`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 32 | Data bus width in bits (`WSTRB` is `DATA_WIDTH/8` bits) |
| `ADDR_WIDTH` | 10 | Address width. RAM depth = 2^`ADDR_WIDTH` = 1024 words |

---

## Architecture

<img width="2250" height="1350" alt="axi_lite_architecture" src="https://github.com/user-attachments/assets/e1282be2-a23c-4ca7-aaf4-61e16bee86ea" />


### Module hierarchy

```
axi_ram_top                    (top level)
├── axi_write_addr_channel     AW: latches write address
├── axi_write_data_channel     W : latches write data and strobes
├── axi_write_resp_channel     B : write response (OKAY)
├── axi_read_addr_channel      AR: latches read address
├── axi_read_data_channel      R : returns read data (OKAY)
└── ram_memory                 1024 x 32 RAM, byte-strobe write, sync read
```

| Module | Role |
|--------|------|
| `axi_write_addr_channel` | Accepts `AWADDR`, pulses `AWREADY`, raises `aw_done` |
| `axi_write_data_channel` | Accepts `WDATA`/`WSTRB`, pulses `WREADY`, raises `w_done` |
| `axi_write_resp_channel` | Holds `BVALID` until `BREADY`; `BRESP` is always OKAY (`2'b00`) |
| `axi_read_addr_channel` | Accepts `ARADDR`, pulses `ARREADY`, raises `ar_done` |
| `axi_read_data_channel` | Registers RAM data, holds `RVALID` until `RREADY` |
| `ram_memory` | Memory array with byte-lane write enables and synchronous read |

---

## How a Transaction Works

**Write**
1. The master drives `AWADDR/AWVALID` and `WDATA/WSTRB/WVALID` at the same time.
2. The AW and W channels each latch their payload, pulse their READY signal, and set `aw_done` / `w_done`.
3. When both flags are set (and no response is pending), `ram_write_en` is pulsed and the RAM stores the data in the byte lanes enabled by `WSTRB`.
4. The B channel asserts `BVALID` (`BRESP = OKAY`) until the master asserts `BREADY`.

**Read**
1. The master drives `ARADDR/ARVALID`; the AR channel latches the address and pulses `ARREADY`.
2. The RAM has a synchronous read, so `ar_done` is delayed by one clock (`read_data_avail`) to give the RAM time to output data.
3. The R channel registers the RAM data and asserts `RVALID` (`RRESP = OKAY`) until the master asserts `RREADY`.

---

## Port Description

| Channel | Signal | Dir | Width |
|---------|--------|-----|-------|
| Global | `clk`, `rst_n` (active low) | in | 1 |
| AW | `s_axi_awaddr` | in | `ADDR_WIDTH` |
| AW | `s_axi_awvalid` / `s_axi_awready` | in / out | 1 |
| W | `s_axi_wdata` | in | `DATA_WIDTH` |
| W | `s_axi_wstrb` | in | `DATA_WIDTH/8` |
| W | `s_axi_wvalid` / `s_axi_wready` | in / out | 1 |
| B | `s_axi_bresp` | out | 2 |
| B | `s_axi_bvalid` / `s_axi_bready` | out / in | 1 |
| AR | `s_axi_araddr` | in | `ADDR_WIDTH` |
| AR | `s_axi_arvalid` / `s_axi_arready` | in / out | 1 |
| R | `s_axi_rdata` | out | `DATA_WIDTH` |
| R | `s_axi_rresp` | out | 2 |
| R | `s_axi_rvalid` / `s_axi_rready` | out / in | 1 |

---

## Repository Structure

```
axi-lite-ram-wrapper-verilog/
├── rtl/
│   └── axi_ram_top.v            # top + channel modules + RAM
├── tb/
│   └── tb_axi_ram_top.v         # self-checking testbench (AXI master)
├── docs/
│   ├── axi_lite_architecture.png
│   ├── simulation_output.png
│   ├── waveform.png
│   └── schematic.png
└── README.md
```

---

## Verification

The testbench replaces the processor: it drives the AXI-Lite master signals using two tasks. `axi_write` asserts the address and data channels together, waits for both handshakes in parallel with `fork ... join`, then waits for the write response and checks `BRESP`. `axi_read` issues the address, waits for `RVALID`, and compares `RDATA` with the expected value.

| # | Test case | Checks |
|---|-----------|--------|
| 1 | Write `0xDEADBEEF` to address 4, read it back | Basic write and read |
| 2 | Write `0xCAFEBABE` to address 8, read it back | Second location |
| 3 | Read address 4 again | Earlier data is not overwritten |
| 4 | Read untouched address 100 | Returns `0` (RAM initialized to zero) |

Clock: 100 MHz (10 ns period). The testbench ends with a `SIMULATION PASSED / FAILED` summary based on an error counter.

### Console output



```
===================================================
STARTING SELF-CHECKING TESTBENCH
===================================================
[WRITE] Addr: 0x004, Data: 0xdeadbeef
[READ]  Addr: 0x004, Data: 0xdeadbeef ... OK
[WRITE] Addr: 0x008, Data: 0xcafebabe
[READ]  Addr: 0x008, Data: 0xcafebabe ... OK
[READ]  Addr: 0x004, Data: 0xdeadbeef ... OK
[READ]  Addr: 0x064, Data: 0x00000000 ... OK

===================================================
SIMULATION PASSED: All checks successful.
===================================================
```

### Simulation waveform
<img width="1917" height="853" alt="Screenshot 2026-10-25 235904" src="https://github.com/user-attachments/assets/a1fe9d0d-14c0-4e1b-bef7-0ef5ef85caa9" />


### RTL schematic (Vivado)
<img width="1568" height="677" alt="Screenshot 2026-10-26 002249" src="https://github.com/user-attachments/assets/d86a6e5c-5c99-48d2-82ae-a659090d640a" />


---

## How to Run (Vivado)

1. Create a new RTL project in Vivado
2. Add `rtl/axi_ram_top.v` as a **design source** (top module: `axi_ram_top`)
3. Add `tb/tb_axi_ram_top.v` as a **simulation source** and set `tb_axi_ram_top` as the simulation top
4. Click **Run Simulation → Run Behavioral Simulation**
5. Run for about 1 µs and read the Tcl console for the `OK` / `PASSED` messages

---

## Tools Used

- Verilog HDL
- Xilinx Vivado (behavioral simulation, elaborated schematic)

---

## Limitations and Future Work

- The address is used directly as a **word index** into the RAM (10 bits select one of 1024 words). A byte-addressed version would use `addr[ADDR_WIDTH-1:2]` as the word index.
- `BRESP` and `RRESP` are always OKAY; there is no `SLVERR` / `DECERR` for out-of-range or invalid accesses.
- One transaction at a time per direction (no outstanding-transaction queue). The optional `AWPROT` / `ARPROT` signals are not implemented.
- The testbench is directed. It uses full-word strobes (`4'b1111`) and keeps `BREADY` / `RREADY` asserted, so partial-strobe writes and slow-master back-pressure are not tested yet.
- Planned improvements: partial `WSTRB` tests, random delays on `BREADY` / `RREADY`, simultaneous read and write, protocol assertions, and an FPGA synthesis run with block-RAM utilization and timing results.

---

## Author

**Sumit**
RTL Design | Verilog | AXI | FPGA


## References

- Arm, *AMBA AXI and ACE Protocol Specification* (AXI4-Lite section)
