# Consensus scaling and deadline behavior

Issue #20 replaces repeated full interval scans with sorted endpoint events, incremental active-source/provider counts, and ordered low/high boundary multisets. Runtime work is O(n log n), retained sweep state is O(n), and winning source evidence is materialized once. Closed intervals that touch still overlap. Unknown provider labels cannot supply diversity, and equally supported disjoint winners still fail.

The supported limit is 1,024 configured sources, validated before any query. Collection checks an independent monotonic elapsed budget before invoking sources and after results return, and yields after 32 attempts per worker. This prevents an immediate-future chain from relying solely on a starved Timer. Already accepted evidence may finalize after expiry; finalization checks the budget, closes pending work, and does not begin a storage wait after expiry. The bounded sweep, one nonpreemptible synchronous callback/check step, and OS scheduling remain overhead. This is not a hard real-time guarantee.

## Reproduction

Run `dart compile exe tool/benchmark_consensus.dart -o <executable>` and execute it on each revision. The benchmark uses offline sources, a fixed monotonic clock, unique endpoints, alternating provider groups, and centers spaced one microsecond apart. It measures complete sync cycles with a 30-second collection budget, five warmups and fifteen measured repetitions per source count. It also counts provider-label accesses as an observable work measure. Those accesses are not an allocation-byte measurement.

The before revision is `e7dacfe` (the previous main). Both binaries used the identical benchmark source and Dart 3.14.0 stable Windows x64 AOT toolchain. Measurements were collected on 25 November 2026 on this Windows host. Whole-cycle times include deliberate collection yields; these can add noise and modest overhead at small source counts.

| Sources | Before median / p95, microseconds | After median / p95, microseconds | Provider reads before / after |
| --- | ---: | ---: | ---: |
| 64 | 993 / 1,486 | 1,200 / 10,689 | 4,288 / 128 |
| 128 | 3,327 / 4,878 | 1,313 / 3,185 | 16,768 / 256 |
| 256 | 14,242 / 22,443 | 3,092 / 9,089 | 66,304 / 512 |
| 512 | 47,727 / 56,868 | 5,499 / 10,243 | 263,680 / 1,024 |
| 1,024 | 207,866 / 496,143 | 15,741 / 31,868 | 1,051,648 / 2,048 |

The largest fixture's median improved about 13 times; the smallest fixture did not improve. Provider-label accesses grew linearly after the change. The sweep stores at most two endpoint entries and two boundary-count entries per accepted sample, plus bounded source/provider lists, replacing repeated temporary full active-set construction. Allocation bytes and representative Android/iOS performance were not measured; those qualification limits remain open. These host observations do not establish a universal latency bound.

Regression coverage includes the inclusive source limit, synchronous budget expiry before acceptance, preservation of a predeadline quorum, lifecycle callback fairness, and 120 seeded generated interval sets compared with an exhaustive endpoint/span oracle. Existing touching, diversity, ambiguity, cancellation, and portable uncertainty tests remain required.
