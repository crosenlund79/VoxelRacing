class_name GameSeed
extends RefCounted
## The session seed for race variety: `--seed=N` among the user arguments
## (after `--` on the command line) for a reproducible session, otherwise a
## random one.


static func from_args(args: PackedStringArray) -> int:
	for a in args:
		if a.begins_with("--seed=") and a.substr(7).is_valid_int():
			return absi(int(a.substr(7)))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()
