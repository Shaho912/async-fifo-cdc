# Async FIFO: Clock Domain Crossing (CDC) and Reset Domain Crossing (RDC)

A parameterized asynchronous FIFO for crossing data between two independent
clock domains, built from scratch (Gray-coded pointers, 2-flop
synchronizers, dual binary/Gray pointer tracking, asymmetric reset
synchronization) and verified with a self-authored XSIM testbench that
specifically targets CDC and RDC failure modes, not just basic read/write
correctness.

This is a standalone CDC/RDC exercise pulled out of a larger FPGA/RTL
portfolio, built by extending a previously hardware-validated
**synchronous** FIFO into the async domain.

## Files

- `rtl/async_fifo.sv`: top-level async FIFO (parameterized `DEPTH`, `DATA_WIDTH`), including the `sync_ff2` pointer synchronizer and `rst_sync` reset synchronizer submodules
- `sim/async_fifo_tb.sv`: XSIM testbench, two independent non-integer-ratio clocks

## Architecture

- Separate binary write/read pointers (`wptr`/`rptr`), each local to its own
  clock domain, sized `$clog2(DEPTH)+1` bits. The extra MSB tracks wraparound
  parity, resolving the binary-pointer ambiguity between "empty" and "full"
  at the same address.
- Each pointer is Gray-coded (`gray = bin ^ (bin >> 1)`) before crossing
  domains, since Gray code guarantees only one bit changes per increment,
  the property that makes it safe to sample mid-transition without landing
  on a bit-incoherent value.
- Two independent 2-flop synchronizer instances (`sync_ff2`) carry each
  Gray pointer into the other domain. Nothing else crosses between
  domains directly.
- `empty` is computed in the `rclk` domain from the local `rptr_gray` vs.
  the synchronized `wptr_gray_sync`. `full` is computed in the `wclk`
  domain from the local `wptr_gray` vs. the synchronized `rptr_gray_sync`,
  using the standard top-two-bits-inverted comparison (naive single-bit
  MSB inversion does not hold across the full Gray-coded width).
- Dual-port memory array, each side addressing directly with its own
  (wrap-bit-stripped) local pointer. No CDC is needed for the data path
  itself, only for the pointer comparison logic.
- Combinational (FWFT) `dout`, consistent with the sync FIFO this was
  derived from.
- Each domain's raw external reset (`wrst`/`rrst`) is passed through its own
  `rst_sync` instance before reaching any sequential logic in that domain.
  `rst_sync` follows the standard "assert async, deassert sync" pattern:
  the output clamps immediately on assertion (bypassing the clock entirely,
  since an async reset override has no clock-relative timing dependency),
  but release is delayed by two clock edges through an internal 2-flop
  chain, so the domain's own clock never observes an unsynchronized reset
  release edge. The synchronized output (`wrst_sync`/`rrst_sync`) is used
  everywhere in that domain, including both the pointer registers and the
  `sync_ff2` pointer synchronizer instances, not just the pointer logic
  alone.

## Key CDC properties verified in the testbench

- **Asymmetric staleness, not asymmetric risk**: each side's full/empty
  flag can lag the true state by up to two cycles of its own clock, but
  only ever in the conservative direction (never reports "safe to
  proceed" when it isn't). Demonstrated directly in Test 5, where `full`
  is shown holding for two extra `wclk` cycles after a read has already
  locally advanced `rptr`.
- **Same-address collision is structurally unreachable, not just
  untested**: a read can never observe the exact slot a concurrent write
  is still committing, because the synchronizer delay that would need to
  clear for `empty` to drop is the same delay that guarantees the write
  has already moved on to a different address by the time the read is
  unblocked. Demonstrated and reasoned through explicitly in Test 1.
- **Independent, non-integer-ratio clocks** (100 MHz / approximately 66 MHz
  `wclk`/`rclk`) used throughout, specifically to avoid the edges lining up
  predictably the way an integer ratio would, which can mask real CDC bugs.

## Key RDC properties verified in the testbench

- **Reset release is intentionally delayed, not instantaneous**: after the
  testbench drops the raw `wrst`/`rrst` pulse, the domain's internal
  `wrst_sync`/`rrst_sync` correctly stays asserted for two more cycles of
  that domain's own clock before releasing, avoiding a reset-recovery-time
  violation on the release edge. Confirmed by observing the shift in every
  post-reset timestamp in the trace once this was added, versus the
  otherwise-identical trace from before the change.
- **A status flag can look identical during reset and during genuine
  emptiness**: `empty` is computed purely from pointer equality, and both
  pointers are held at `0` for the full duration reset is asserted, not
  just at the instant it ends. So `wait(empty)` in the testbench could
  spuriously succeed while the DUT was still internally in reset,
  silently dropping writes issued in that window. Fixed by waiting on the
  actual internal reset signals directly rather than treating `empty` as
  a reliable proxy for "reset has fully released."

## Debugging notes worth keeping

- `$clog2` vs. a nonexistent `$clog`: a silent-looking elaboration failure
  if mistyped.
- Sensitivity-list operator bugs: `|` and `||` are not `or`/comma in an
  event control list. `always_ff @(posedge clk | rst)` describes an edge
  on a bitwise-OR'd expression, not "trigger on either edge independently."
- Full-flag Gray-code comparison: the naive "MSB differs, remaining bits
  equal" rule (correct for binary pointers) does not hold under Gray
  coding. The standard fix compares against the read pointer with its
  top two bits inverted, not just the top bit.
- Memory addressing must strip the wraparound MSB from the pointer before
  indexing into the (unwrapped) memory array, or indices run out of bounds
  past `DEPTH`.
- Testbench tasks that raise their enable signal only after an initial
  `@(posedge clk)` cost a full extra cycle of "arming delay" before the
  DUT ever samples the request. This matters when deliberately racing a
  signal against a boundary condition (for example, attempting a read in
  the cycle immediately after a write, before `empty` has had time to
  clear).
- A first draft of `rst_sync`'s internal flop reset both stages to the
  same value used during normal (non-reset) operation. Since there was no
  actual bit transition to propagate on release, the second flop's output
  changed on the very first release edge instead of being delayed by a
  full cycle behind the first, silently collapsing the intended 2-stage
  delay down to a no-op. Fixed by resetting the first stage to the
  opposite of its steady-state value, so a real transition exists for the
  second stage to lag behind.
- Simulator caching/incremental-compile issues (stale snapshot reused
  after a source edit) produced identical, unchanged timestamps across
  supposedly different runs more than once during this work. Comparing
  full traces run-to-run, not just final values, caught this before it
  was mistaken for a design bug.

## Status

Structurally complete and passing all six testbench scenarios (normal
write/read, read-when-empty, fill-to-full, write-when-full,
read-during-full with the two-cycle `full` lag, and concurrent write/read
across the crossing), now including reset domain crossing: each domain's
reset is asynchronously asserted and synchronously released via a
dedicated `rst_sync` instance feeding both the pointer registers and the
pointer synchronizers in that domain.
