class_name ProbeRunner
extends RefCounted
## Runs tests/support/sim_probe.gd in a fresh Godot process and returns its state hash.


static func run(args: PackedStringArray) -> String:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
		"-s", "res://tests/support/sim_probe.gd", "--"])
	cmd.append_array(args)
	var out: Array = []
	OS.execute(OS.get_executable_path(), cmd, out, true)
	for line in "\n".join(out).split("\n"):
		if line.begins_with("PROBE "):
			return line.substr(6).strip_edges()
	return "no-probe-output: " + "\n".join(out).right(400)
