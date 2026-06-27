# Simple FPGA verification project
Simple verification of 24CSM01 I2C EEPROM IC

##  Project setup
Make sure Vivado 2025.2 is installed and available in PATH.

## Build & simulation targets

| Target | Description |
|--------|-------------|
| `make` / `make all` | Compile RTL, compile TB, elaborate, and run simulation |
| `make comp_rtl` | Compile RTL sources (via `rtl.f`) into the `myrtl` library |
| `make comp_tb` | Compile testbench sources (via `verif.f`) into the `tb` library |
| `make elab` | Elaborate the design (links libraries into the `sim` snapshot) |
| `make run` | Run simulation |
| `make waves` | Open the saved waveform file (`waves.wdb`) in the Xsim GUI |
| `make report` | Generate code and functional coverage reports (requires `COV=1`) |
| `make format` | Auto-format all RTL and TB sources using `verible-verilog-format` |
| `make clean` | Remove all generated files (logs, journals, waveforms, coverage DB) |

## Options

Options are passed as `make OPTION=value`. All options can be combined.

| Option | Default | Description |
|--------|---------|-------------|
| `WAVE` | `0` | Set to `1` to enable waveform dumping; output saved to `waves.wdb` |
| `COV` | `0` | Set to `1` to enable code and functional coverage collection |
| `TOPO` | `0` | Set to `1` to print the UVM topology at the start of simulation |
| `VERBOSITY` | `UVM_LOW` | UVM verbosity level (e.g. `UVM_NONE`, `UVM_LOW`, `UVM_MEDIUM`, `UVM_HIGH`, `UVM_FULL`) |
| `TESTNAME` | `mem_ctrl_test` | Name of the UVM test to run |

### Examples

```bash
# Full run with waveforms
make WAVE=1

# Run with coverage collection
make COV=1

# Run with coverage and open report
make COV=1 && make report COV=1

# Run a specific test at high verbosity
make TESTNAME=my_test VERBOSITY=UVM_HIGH

# Run with all debug options enabled
make WAVE=1 COV=1 TOPO=1 VERBOSITY=UVM_MEDIUM
```
