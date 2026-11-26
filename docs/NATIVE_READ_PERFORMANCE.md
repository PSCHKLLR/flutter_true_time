# Native clock-read allocation investigation

Issue #10 remains open. The current artifact is a pre-optimization Windows AOT latency baseline, not evidence of an allocation reduction or representative Android/iOS qualification. Native scratch reuse, ownership/reentrancy validation, allocation/GC measurements, and paired after measurements remain required.

## Reproducible latency fixture

`tool/benchmark_native_reads.dart` and the mobile integration entry point share the offline fixture in `example/integration_test/support/read_benchmark.dart`. Each mode creates a platform clock and an engine, accepts two deterministic source intervals, warms up, and measures 25 batches of 10,000 calls by default. The clock domain and resolution are recorded. Snapshot/read checksums consume UTC/elapsed and uncertainty fields; now consumes UTC. Returned readings remain ordinary immutable public objects. No network, epoch provider, or storage backend is involved.

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

Use `example/integration_test/read_benchmark_test.dart` on representative Android and iOS hardware with `--release` (or separately labeled `--profile`) and dart-defines `BENCHMARK_DEVICE` and `BENCHMARK_REVISION`. Debug builds are rejected. The integration binding's `reportData` contains the result object. Use an integration-test driver that saves that report; retain device model, OS, CPU/architecture, Flutter/Dart/Xcode/Android toolchain, thermal/power state, command, source revision, and build artifact identity alongside it. Never put private device/installation identifiers in public evidence.

Collect a separate allocation/GC trace for the same workload and configuration, clearly naming what the tool measures and its instrumentation overhead. Flutter release and profile measurements are different lanes. Host AOT GC logs, Dart heap allocations, and native allocator calls must not be presented as interchangeable. Physical targets were not available during initial host collection; their qualification remains pending.
