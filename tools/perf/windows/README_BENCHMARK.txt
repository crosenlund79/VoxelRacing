VoxelRacing - Performance Investigation 001 - DIAGNOSTIC BENCHMARK KIT
======================================================================

This is NOT the playable release. It is the game with timing probes added,
built from the claude/perf-investigation-001 branch, so the performance
investigation can be repeated on a real Windows PC with a real graphics card.

1. Extract this folder anywhere.
2. Close other programs (browsers, launchers, recording software).
3. Double-click run_benchmarks.bat and do not touch the PC until it says
   "Done" (about 25 minutes; windows open and close by themselves, races
   are driven by the computer).
4. Zip the "results" folder that appears next to the .bat and send it back.

The results folder holds, per scenario, a per-frame CSV, a JSON summary and
a log, plus systeminfo.txt and dxdiag.txt (CPU, GPU, driver, memory).
Nothing is uploaded anywhere by the kit.

Started by hand, the kit is the ordinary game (the benchmark only runs with
the --bench=... argument the .bat passes).
