# 2017 iPad Pro scrolling benchmark — 26 September 2026

The lightweight example did not reveal a sustained scrolling bottleneck on the connected 10.5-inch iPad Pro. Across 100 retained fast swipes, XCTest reported one 8.34 ms hitch, in landscape. The other four scenarios reported none. Increasing the model from 256 to 10,000 items kept peak app memory near 25 MB and did not introduce recorded hitches.

These results establish a baseline for this sample, not a guarantee for image-heavy cells or sustained 120 Hz presentation. No library implementation was changed.

## Conditions and method

- Physical iPad Pro 10.5-inch, model iPad7,4, iPadOS 17.7.11 (21H461), connected by USB.
- Library revision `bb14440`; Release build, Xcode 27.0 (27A5252f), iOS 27 SDK, iOS 15 deployment target. Automatic development signing.
- Existing sample cell: label, separators, selection/reorder symbols. Default sample uses two columns in portrait and three in landscape on this device.
- Each scenario launches a fresh app, performs one warm-up swipe, then uses XCTest's measure loop: five retained repetitions, each containing two fast upward and two fast downward swipes. XCTest's additional warm-up iteration is excluded from the exported measurements.
- `XCTOSSignpostMetric.scrollingAndDecelerationMetric`, `XCTCPUMetric(application:)`, and `XCTMemoryMetric(application:)`. Instruments was not running during the baseline measurements.
- CPU figures are app-process CPU seconds per four-swipe measurement, including automation waits and accessibility servicing. They are **not** milliseconds of grid layout or CPU utilization percentages. Memory is the mean of each repetition's physical-memory peak, in decimal MB.
- The test asserts the model count remains correct and cell elements remain present after scrolling. Existing tests separately check reuse, visible ranges, preparation, edits, drag ordering, and rotation selection/layout.

## Results

| Scenario | Items | Preparation | Hitches / 20 swipes | Total hitch time | Mean hitch ratio | CPU seconds / 4 swipes | Mean peak memory |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| Portrait | 256 | On | 0 | 0 ms | 0 ms/s | 1.027 | 25.30 MB |
| Portrait | 256 | Off | 0 | 0 ms | 0 ms/s | 1.103 | 25.71 MB |
| Landscape | 256 | On | 1 | 8.34 ms | 0.665 ms/s | 1.236 | 25.48 MB |
| Portrait, large model | 10,000 | On | 0 | 0 ms | 0 ms/s | 1.150 | 25.44 MB |
| Portrait, editing | 256 | On | 0 | 0 ms | 0 ms/s | 1.033 | 24.18 MB |

The landscape hitch occurred in one repetition; that repetition's ratio was 3.326 ms/s, with the remaining four at zero. This isolated event is insufficient to identify a library defect or attribute its cause.

Preparation-on and preparation-off both scrolled without recorded hitches. The CPU-time ranges overlap (on: 0.895–1.131 s; off: 1.064–1.138 s), and the runs were not randomized or thermally controlled. Do not interpret the modest mean difference as a proven speedup. This cheap-cell workload does not establish how preparation performs with expensive client callbacks.

The 39-fold increase in item count did not produce comparable CPU or memory growth. This is consistent with viewport-bounded cell recycling. Measured memory changes per repetition were small (largest absolute delta across the scenarios: approximately 0.26 MB); this short run is not a leak or long-session endurance test.

## Behavior and tooling

All 70 unit tests passed on the iPad. Add/select/delete, drag reordering, and rotation/full-window UI checks also passed, as did all five benchmark scenarios after isolated reruns. The rotation check retained selection through portrait → landscape → portrait. The drag check moved the first cell to the expected destination and retained the item count.

The original combined run reported 74 passes and four failures. Every failure was `Lost connection to testmanagerd`, occurring between cases before the affected test's setup. Running each affected case in a fresh runner produced successful results without changing library code. The repeatable script isolates UI cases for this reason. Xcode sometimes took over a minute to finalize an already-completed test bundle.

XCTest's frame-count metric returned zero for every retained measurement while its FPS metric returned varying nonzero values. Those fields are internally inconsistent and are excluded from conclusions. A separate Instruments attempt initially captured an idle/background app while Xcode delayed runner startup; subsequent attachment attempts could not resolve the live app process even though `devicectl` could list it. These captures do not validate sustained 60/120 FPS or locate a CPU hot path. The XCTest hitch figures above are reported as collected, with this tooling limitation kept explicit.

The original rotation screenshot was captured mid-transition; it is not evidence of a persistent layout defect. A separate screenshot after rotation settled was captured for visual inspection.

## Practical conclusion and limits

There is no measured reason here to change the grid's scrolling implementation. Keep this device as a regression target, particularly for landscape and more expensive cells. No newer-device baseline was run, so this report does not claim a quantified old-versus-new hardware slowdown.

The next workload that could expose a meaningful bottleneck is a representative app cell: cover images, actual decoding/loading, and realistic synchronous configuration. Visible cells still require immediate configuration when a fling outruns preparation; these simple text cells do not stress that path. These tests also do not measure long thermal soak, cold-start scrolling, continuous gesture interruptions, rotation during deceleration, or drag autoscrolling at the edges. Rotation and drag were verified for behavior, not given independent animation-performance measurements.

## Reproducing and reviewing

Run from the repository root on an unlocked device:

```sh
python3 Scripts/benchmark-ipad.py \
  --device DEVICE_UDID --team DEVELOPMENT_TEAM \
  --output Benchmarks/new-device-run --include-behavior-tests
```

The script creates the Release build, enables the otherwise-skipped performance tests in the `.xctestrun` environment, runs each case separately, and exports metrics. The sample accepts opt-in launch environment values for item count and preparation; its default behavior remains unchanged.

Local raw artifacts are in the git-ignored `Benchmarks/2017-iPad-Pro/` directory:

- `baseline.xcresult`: 70 unit tests, successful add/delete and rotation checks, landscape/preparation-off measurements, and the original runner failures.
- `testPortraitPreparationOn.xcresult`, `testLargeDataSet.xcresult`, `testEditingScroll.xcresult`, `testDragReordersCells.xcresult`: successful isolated reruns.
- `baseline-metrics.json`, `portrait-on-metrics.json`, `large-metrics.json`, `editing-metrics.json`, and `summary.json`: exported measurements and aggregates.
- `diagnostics/`: original test-runner diagnostics.
- `landscape-settled.png`: settled layout screenshot.
- Additional profiling attempts are retained for diagnosis and excluded from the baseline table.
