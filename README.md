# Frame Aligner Verification

This repository contains a SystemVerilog verification environment for a simple frame aligner module. The aligner scans an incoming serial stream for predefined headers and asserts synchronization once valid frames are detected.

## Features
- Detects two valid header patterns (`AAAF` and `55BA`).
- Collects 10 bytes of payload after a valid header.
- Reports frame alignment after three consecutive valid frames.
- Resets synchronization if 48 bytes are received without a valid header.

## Repository Layout
- `dut.sv` – RTL implementation of the frame aligner.
- `testbench.sv` – Top-level testbench connecting all verification components.
- `environment.sv`, `driver.sv`, `monitor_in.sv`, `monitor_out.sv`, `scoreboard.sv` – UVM‑like components implementing the test environment.
- `generator.sv` – Generates stimulus for a variety of valid and invalid frame sequences.
- `assertions.sv` – Simple assertions used during simulation.
- `build.list` – Compilation order of all source files.
- `frame_aligner_model.sv` – SystemVerilog reference model mirroring the DUT behaviour.

## Running the Simulation
1. Compile all files listed in `build.list` with your preferred SystemVerilog simulator (e.g. VCS, Questa).
2. Run `testbench` to execute the random and directed test cases from the generator.
3. At the end of the run the scoreboard prints the number of detected errors.

## License
This project is provided for educational purposes and carries no specific license.
