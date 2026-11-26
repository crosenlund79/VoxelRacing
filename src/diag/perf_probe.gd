class_name PerfProbe
extends RefCounted
## DIAGNOSTIC ONLY (Performance Investigation 001, branch
## claude/perf-investigation-001; never merged into the playable game).
## Accumulates wall-clock microseconds spent in instrumented functions during
## the current rendered frame. The probes are inserted by
## tools/perf/apply_probes.py; PerfBench reads and clears them every frame.

static var on := false
static var acc: Dictionary = {}
static var calls: Dictionary = {}


static func add(name: StringName, t0: int) -> void:
	if not on:
		return
	acc[name] = int(acc.get(name, 0)) + (Time.get_ticks_usec() - t0)
	calls[name] = int(calls.get(name, 0)) + 1


static func take() -> Dictionary:
	var d := acc
	acc = {}
	calls = {}
	return d
