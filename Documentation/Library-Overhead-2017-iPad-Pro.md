# Library overhead on the 2017 iPad Pro

Measured 26 September 2026 on the connected iPad Pro 10.5-inch, iPadOS 17.7.11, using an optimized Release build and Xcode 27.0. This follows the earlier [sample scrolling benchmark](Performance-2017-iPad-Pro.md).

Two small changes reduce main-thread work without changing the public API or moving cell creation off the main thread:

1. On an ordinary viewport change, incoming-cell lookup skips the overlap with a previously reconciled, still-valid visible range. In the dense test, lookups fell from 820 to 20 per row crossing. Recycling still scans the visible dictionary; edits, invalidation, incomplete layout, and dragging retain the full lookup path.
2. After successfully preparing a cell, preparation no longer rebuilds the candidate list a second time. The next tick validates and rebuilds it before use. The display link still stops immediately after the final candidate, and callback invalidation retains the previous recovery path.

## Measurement method

`GridOverheadBenchmarks` creates a real grid in a device window with 100,000 model items, 24-point rows, an 800 × 960-point viewport, and either 2 or 20 columns. This gives 82 or 820 visible cheap `TOGridViewCell` instances. Configuration only dequeues a cell and assigns its index to `tag`; there are no labels, image decoding, artificial delays, or extra app work.

A test-owned display link requests the device's maximum refresh rate and drives six workloads: small movements within one visible range, one-row advances, repeated boundary crossings, direction reversals, alternating distant viewports, and idle. Each case has 60 warm-up callbacks followed by 240 measured callback intervals. Actual cell preparation uses the unmodified scheduling mechanism and deadline checks. Timing probes and counters exist only in test subclasses.

Four complete runs were made in this order: original, optimized, separate original control build, optimized repeat. The control build uses the original two library files from revision `bb14440` in a separate temporary checkout, with the same benchmark. Thermal state was nominal at every recorded scenario endpoint; frequency was not locked. The initial original dense row-crossing result was noticeably slower than the repeated control, so the main table uses the repeat pair rather than the largest observed gain.

Timings below are **synchronous `layoutCells` reconciliation per driver interval**, including its UIKit calls and the cheap data-source callback. They are not total frame time, the full `layoutSubviews` cost, or presentation FPS. `preparation` times the entire preparation display-link callback. `bookkeeping` times `updateCellPreparation` both inside and outside that callback, so it overlaps with `preparation` and must not be added to it. Driver callback intervals describe scheduling cadence, not rendered frames.

## Results from the repeat pair

| Visible cells | Workload | Original mean | Optimized mean | Original p99 | Optimized p99 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 82 | Row crossing | 0.193 ms | 0.182 ms | 0.235 ms | 0.216 ms |
| 82 | Boundary reversal | 0.187 ms | 0.175 ms | 0.268 ms | 0.232 ms |
| 82 | Direction reversal | 0.191 ms | 0.175 ms | 0.239 ms | 0.215 ms |
| 820 | Row crossing | 0.951 ms | 0.834 ms | 1.119 ms | 0.958 ms |
| 820 | Boundary reversal | 0.832 ms | 0.719 ms | 0.963 ms | 0.823 ms |
| 820 | Direction reversal | 0.939 ms | 0.833 ms | 1.111 ms | 0.972 ms |
| 820 | Distant full-viewport jumps | 24.112 ms | 24.472 ms | 25.425 ms | 25.401 ms |

Dense overlapping movement improved by approximately **12–14%** in this repeat pair. The initial pair's dense row-crossing mean was 1.251 → 0.832 ms; the second pair confirms an improvement but cautions against claiming the initial 33% as a stable speedup.

The lookup reduction is deterministic: 196,800 → 4,800 calls over 240 dense row-crossing samples, or **97.6% fewer incoming-cell lookups**. This does not mean total grid work fell by 97.6%.

Dense preparation callback means changed as follows:

| Workload | Original | Optimized |
| --- | ---: | ---: |
| Row crossing | 0.0480 ms | 0.0397 ms |
| Boundary reversal | 0.0537 ms | 0.0438 ms |
| Direction reversal | 0.0587 ms | 0.0436 ms |

That is approximately **17–26% less time in preparation ticks** for the repeat pair. During these workloads, total candidate-update calls fell from 720 to 480: one scheduled update plus one update in each successful preparation tick, instead of two in that tick. The timing amounts are small, but removing a redundant pass avoids collection creation and scanning without introducing a new cache or invalidation scheme.

## What did not need changing

- Unchanged-range reconciliation was already about 0.003 ms per driver interval, with no cell lookups, configurations, or preparation callbacks after warm-up.
- Idle cases recorded zero reconciliation, preparation, configuration, and cell layout work after warm-up. Their preparation display links were stopped.
- All measured scenarios recorded zero **new cell-object allocations** after warm-up. This does not measure all temporary Foundation/UIKit allocations.
- Cell layout counts were unchanged by the optimizations. Even unchanged-range movement had some actual UIKit cell layouts (288 / 2,880 over 240 intervals for 2 / 20 columns); the existing grid shortcut does not imply the entire UIKit hierarchy does zero layout work.
- Ordinary workload driver intervals remained approximately 8.334 ms, consistent with the requested 120 Hz callback cadence. This is not a claim of independently verified 120 FPS presentation.

## Remaining limit

Alternating between two completely different 820-cell viewports every display callback still costs about **24 ms in reconciliation alone**, beyond both 8.33 ms and 16.67 ms frame budgets. The optimized repeat's driver intervals averaged about 27 ms. This is a much denser case than the demo, and it exposes a real synchronous burst even with cheap cells.

There is no overlap to skip in this case. The grid still has to end display, recycle, configure, and attach hundreds of cells immediately. The two changes intentionally preserve that behavior. No large-jump improvement is claimed; the small difference between runs is within the observed timing variation. A policy that delays visible content or a different view-hierarchy strategy would require a separate design decision. It is not justified merely by the demo workload.

## Validation

The two new regression tests first failed against the original implementation: 12 lookups instead of the expected 3 on a small row crossing, and two candidate rebuilds instead of one per successful preparation step. After the changes, all 72 unit tests passed on the physical iPad; the opt-in overhead test was skipped in that ordinary unit run and passed in all four separate benchmark runs.

Existing tests cover preparation pacing, parked deadlines, cache invalidation, callback reload/disable, memory warnings, reuse, geometry overrides, edits, and visible ranges. Device UI checks for add/select/delete and drag reordering passed. The final rotation check stalled before its test body started; the device reported that a passcode was required, and the run was interrupted pending another unlock. Rotation is therefore not verified for these changes. The benchmark validates cell identity and geometry at each scenario's end; it is not a frame-by-frame visual correctness test.

Independent code review found no blocking issue in the range/generation guards or preparation recovery path. Xcode emitted the existing XCTest deployment-target and unused App Intents metadata warnings; no new source warning remains in the final build.

## Reproduce

```sh
python3 Scripts/benchmark-ipad.py \
  --device DEVICE_UDID --team DEVELOPMENT_TEAM \
  --output Benchmarks/new-overhead-run \
  --test TOGridViewExampleTests/GridOverheadBenchmarks
```

The result bundle contains a `grid-overhead.json` attachment. The same rows are logged with the `GRID_OVERHEAD` prefix. Unlike the UI swipe suite, these custom timings are attachments/logs rather than XCTest's built-in exported performance metrics.

Local artifacts are in the git-ignored `Benchmarks/2017-iPad-Pro-overhead/` directory:

- `baseline`, `optimized`, `control-repeat`, `optimized-repeat`: `.log`, parsed `.json`, and `.xcresult` for all four runs.
- `red.xcresult`: expected pre-change regression failures.
- `green.xcresult`: full unit-suite verification after the changes.
- `ui-add-delete`, `ui-drag`, `ui-rotation`: final device UI test logs/results.
