class_name RivalRoster
extends RefCounted
## The nine recurring rivals. Racer id n (1..9) is always the same driver, car
## colour (cars/car_ai_n) and personality, in every race and every session.
## Every rival has a personality file (M2.1 pilot: Victor, Rocco, Ellie; M2.3:
## the other six). A rival without one would use the shared default AI.

const DEFAULT_PARAMS := "res://src/ai/default_ai_params.tres"
const RIVALS := [
	{"name": "Victor", "nickname": "The Professor", "params": "res://src/ai/personalities/victor.tres"},
	{"name": "Rocco", "nickname": "Mad Dog", "params": "res://src/ai/personalities/rocco.tres"},
	{"name": "Ellie", "nickname": "Sparrow", "params": "res://src/ai/personalities/ellie.tres"},
	{"name": "Hank", "nickname": "The Wall", "params": "res://src/ai/personalities/hank.tres"},
	{"name": "Maya", "nickname": "Ghost", "params": "res://src/ai/personalities/maya.tres"},
	{"name": "Dante", "nickname": "Showboat", "params": "res://src/ai/personalities/dante.tres"},
	{"name": "Greta", "nickname": "Clockwork", "params": "res://src/ai/personalities/greta.tres"},
	{"name": "Finn", "nickname": "Wildcard", "params": "res://src/ai/personalities/finn.tres"},
	{"name": "Nina", "nickname": "The Hunter", "params": "res://src/ai/personalities/nina.tres"},
]


static func count() -> int:
	return RIVALS.size()


## Short name used in tables, e.g. "Victor".
static func short_name(id: int) -> String:
	return RIVALS[id - 1].name


## Full name, e.g. Victor "The Professor".
static func full_name(id: int) -> String:
	return '%s "%s"' % [RIVALS[id - 1].name, RIVALS[id - 1].nickname]


## Nickname, e.g. "The Professor".
static func nickname(id: int) -> String:
	return RIVALS[id - 1].nickname


static func params_path(id: int) -> String:
	var path: String = RIVALS[id - 1].params
	return path if not path.is_empty() else DEFAULT_PARAMS


static func has_personality(id: int) -> bool:
	return not String(RIVALS[id - 1].params).is_empty()
