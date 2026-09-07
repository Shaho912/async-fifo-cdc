# Async FIFO: Clock Domain Crossing (CDC)

A parameterized asynchronous FIFO for crossing data between two independent
clock domains, built from scratch (Gray-coded pointers, 2-flop
synchronizers, dual binary/Gray pointer tracking) and verified with a
self-authored XSIM testbench that specifically targets CDC failure modes,
not just basic read/write correctness.

This is a standalone CDC exercise pulled out of a larger FPGA/RTL
portfolio, built by extending a previously hardware-validated
**synchronous** FIFO into the async domain.

## Files

- `rtl/async_fifo.sv`: top-level async FIFO (parameterized `DEPTH`, `DATA_WIDTH`), including the `sync_ff2` 2-flop synchronizer submodule
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

## Status

Structurally complete and passing all six testbench scenarios (normal
write/read, read-when-empty, fill-to-full, write-when-full,
read-during-full with the two-cycle `full` lag, and concurrent write/read
across the crossing). Async reset deassertion synchronization (assert
async, deassert sync) is a noted, deliberately deferred refinement, not
yet implemented here.
