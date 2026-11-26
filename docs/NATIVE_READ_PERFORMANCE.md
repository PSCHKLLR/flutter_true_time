# Native clock-read allocation investigation

Issue #10 remains open until representative Android and iOS release-build latency and allocation evidence is collected. Windows AOT comparisons are host observations and do not qualify mobile devices.

## Ownership and conservative sampling

Windows and Linux/Android clocks allocate one scratch buffer per clock, reused for synchronous native samples. Its `Finalizable` owner remains alive throughout each read. A static `NativeFinalizer` uses the allocator's matching native free callback when that owner becomes unreachable; attachment and clock-construction failures free immediately. Finalization is not prompt disposal or a process-exit hook. Engines do not close injected clocks, so disposing one engine cannot free a shared clock. The scratch owner and closures capturing it cannot be sent to another isolate; construct a clock in each isolate instead. Pointers must not escape the internal synchronous read callback.

Nested reads allocate separate temporary scratch and free it in `finally`. Explicit internal close is idempotent, rejects an active read, and detaches finalization before freeing. It is used for failed construction and tests. Ordinary sampling also reuses one Stopwatch; nested sampling uses its own watch. Every returned snapshot remains immutable. Uncertainty is still native resolution plus the elapsed synchronous sample duration; no fixed smaller error bound is substituted. Clock domains, sleep continuity, quotient/remainder tick conversions, and session-only fallback are unchanged. Darwin's timebase buffer remains construction-only.

The ownership model follows Dart's [Finalizable lifetime rules](https://api.dart.dev/dart-ffi/Finalizable-class.html), [NativeFinalizer contract](https://api.dart.dev/dart-ffi/NativeFinalizer-class.html), and [isolate send restrictions](https://api.dart.dev/dart-isolate/SendPort/send.html). Tests cover scratch reuse, isolated nested pointers, exception recovery, close rejection/double close, isolate-send rejection, immutable/error-floor samples, large elapsed values, and engines sharing a clock. These ownership checks and the matching native free callback do not constitute physical-device allocator/leak profiling.

## Reproducible latency fixture

`tool/benchmark_native_reads.dart`, the standalone mobile entry point, and the mobile integration entry point share the offline fixture in `example/lib/src/native_read_fixture.dart` (originally `example/integration_test/support/read_benchmark.dart`, with identical contents). Each mode creates a platform clock and an engine, accepts two deterministic source intervals, warms up, and measures 25 batches of 10,000 calls by default. The clock domain and resolution are recorded. Snapshot/read checksums consume UTC/elapsed and uncertainty fields; now consumes UTC. Returned readings remain ordinary immutable public objects. No network, epoch provider, or storage backend is involved.

Modes are `baseline`, `snapshot`, `read`, and `now`. Baseline measures loop/callback overhead; it is reported separately, without subtracting noisy measurements. Quantiles describe **batch-average** microseconds per call, not individual-call tail latency. Throughput is measured calls divided by measured elapsed ticks. Allocation bytes and GC are explicitly unmeasured by this fixture. Use matching settings and the identical fixture/toolchain for before/after runs, retain raw results and binary/source hashes, and run at least three repetitions.

From the repository root:

```sh
dart compile exe tool/benchmark_native_reads.dart -o <executable>
<executable> --revision=<runtime-source-commit> --foreground=true
<executable> --revision=<runtime-source-commit> --foreground=false
```

Optional `--mode=...`, `--warmup=N`, `--count=N`, and `--batches=N` select an isolated mode or larger workloads. JSON records runtime/OS versions, configuration, checksums, batch means, quantiles, and throughput. Foreground mode includes expiry maintenance triggered by sampled error-bound changes; foreground=false separates that maintenance from the read path. Do not compare the two configurations as if they measured the same work.

[Windows baseline data](evidence/native-read-before-windows.json) records three runs for each foreground setting on runtime revision `305b204`. The artifact contains the exact Dart runtime/OS strings, native clock source hash, benchmark fixture hash, and AOT executable hash. This is host evidence only. It does not measure native allocation/free traffic, total allocated bytes, GC pause latency, or mobile behavior.

## Representative mobile collection still required

For a true release build, run the standalone entry point from `example/`:

```sh
flutter run --release -d <physical-target> -t lib/native_read_benchmark.dart \
  --dart-define=BENCHMARK_DEVICE=<public-model-label> \
  --dart-define=BENCHMARK_REVISION=<runtime-source-commit> \
  --dart-define=BENCHMARK_FOREGROUND=true
```

The app displays the JSON and a copy button. Save three fresh-process runs for each foreground setting and revision. For the before build, copy the exact fixture and entry point into an otherwise unchanged baseline checkout. Record hashes to establish that both builds used identical fixtures. This entry point avoids depending on a VM-service driver in release mode.

For a separate profile lane, `integration_test/read_benchmark_test.dart` rejects debug builds and reports through the supplied driver:

```sh
flutter drive --profile -d <physical-target> \
  --driver=integration_test/support/benchmark_driver.dart \
  --target=integration_test/read_benchmark_test.dart \
  --dart-define=BENCHMARK_DEVICE=<public-model-label> \
  --dart-define=BENCHMARK_REVISION=<runtime-source-commit> \
  --dart-define=BENCHMARK_FOREGROUND=true
```

The driver saves `build/integration_response_data.json`; rename each result before the next run. See Flutter's [integration profiling instructions](https://docs.flutter.dev/cookbook/testing/integration/profiling). Both entry points require the model/revision labels. Retain device model, OS, CPU/architecture, Flutter/Dart/Xcode/Android toolchain, thermal/power state, command, source revision, and build artifact identity alongside the report. Never put private device/installation identifiers in public evidence.

Collect a separate allocation/GC trace for the same workload and configuration, clearly naming what the tool measures and its instrumentation overhead. Flutter release and profile measurements are different lanes. Host AOT GC logs, Dart heap allocations, and native allocator calls must not be presented as interchangeable. Physical targets were not available during initial host collection; their qualification remains pending.

## Separate host GC telemetry

`tool/benchmark_native_gc.dart` warms up 100,000 calls and marks a two-million-call loop. Run baseline/snapshot/read/now and both foreground settings three times each for both source revisions:

```sh
dart compile aot-snapshot tool/benchmark_native_gc.dart -o <snapshot.aot>
dartaotruntime --verbose-gc <snapshot.aot> read false 2> <raw-log.txt>
dart tool/summarize_native_gc.dart <raw-log.txt>
```

The parser preserves marked scavenge rows and rejects missing collection IDs, unsupported collection kinds, or ambiguous markers. It sums young used-before minus the preceding used-after over complete intervals, omitting initial/final partial intervals, and divides by the full measured call count. VM heap values are rounded to 0.1 MiB; the reported worst-case rounding contribution is intervals × 0.1 MiB / calls. Missing edge spans are a separate limitation. Baseline without collections reports no bytes-per-call estimate, rather than claiming zero allocation. Reported GC durations are also rounded; sums/maxima describe the instrumented collection observations, not individual-call latency or a complete pause profile.

This estimates observed young-generation growth, including allocator accounting. It excludes native and old-generation allocation and does not establish exact managed allocation bytes or object counts. Instrumented GC runs are separate from uninstrumented latency runs. See the [Dart 3.14 VM reporting implementation](https://github.com/dart-lang/sdk/blob/3.14.0/runtime/vm/heap/heap.cc) and [AOT runtime instructions](https://dart.dev/tools/dartaotruntime).

## Recorded Windows comparison

The [paired latency artifact](evidence/native-read-paired-windows.json) compares runtime `305b204` with `d42520c`, using the identical fixture content and Dart 3.14.0 AOT on Windows x64 / Intel Core i5-7300HQ. Before/after executions alternate within each repetition. Ranges below span the three run medians in microseconds per call; each median is computed over batch means.

| Foreground maintenance | Operation | Before | After |
| --- | --- | --- | --- |
| Disabled | snapshot | 0.355–0.380 | 0.233–0.249 |
| Disabled | read | 0.480–0.492 | 0.335–0.339 |
| Disabled | now | 0.446–0.470 | 0.331–0.365 |
| Enabled | snapshot | 0.371–0.387 | 0.244–0.250 |
| Enabled | read | 0.594–0.663 | 0.349–0.369 |
| Enabled | now | 0.678–0.785 | 0.350–0.386 |

Loop/callback baseline medians ranged 0.00565–0.01258 µs. Thermal/power state was uncontrolled, and other host verification/SDK preparation could contend with these runs. The results support a host improvement for this workload, not a universal speedup or individual-call tail guarantee. Foreground runs also include timer cancellation/rearming when the sampled error bound changes; the changed sampling duration affects that work, so their larger improvement cannot be attributed solely to removed object allocation.

The [paired GC artifact](evidence/native-read-gc-paired-windows.json) retains all 48 marked runs as raw numeric rows plus summaries, source/fixture/parser/snapshot hashes, and toolchain identity. Before and after groups ran sequentially, separately from the latency runs. With foreground maintenance disabled, observed young growth was approximately 208 → 144 bytes/snapshot and 462 → 398 bytes/read or now. The respective rounding contributions were at most about 10.4 → 7.2 and 23.2 → 19.9 bytes/call; omitted edge spans remain additional uncertainty. Foreground read/now observations ranged about 683–705 → 435–448 bytes/call, including timer maintenance. No-read controls produced no marked scavenges and therefore no growth estimate. These are rounded young-heap observations, not exact allocation totals or proof of native allocator behavior.

Local validation passed 253 Dart core tests, 258 Flutter core/facade tests, two example tests, and formatting. Analysis of the changed files passed; whole-example analysis on the installed newer SDK also reports the pre-existing Material import deprecation in `example/lib/main.dart`. The attempted Windows standalone release-app build could not run without a suitable Visual Studio toolchain. Android/iOS CI now compiles the benchmark entry point separately from the demo; no build check establishes runtime/device qualification. Representative mobile timing, allocation/GC, and native-resource profiling remain pending, so #10 is not closed by this comparison.
