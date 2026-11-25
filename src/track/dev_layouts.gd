class_name DevLayouts
extends RefCounted
## Track layouts by id. Players choose among PLAYER_LAYOUTS on the title screen
## (LAYOUT button, never saved: every launch starts on DEFAULT, Kestrel Ridge).
## The legacy layouts (the Classic Circuit and the experimental Figure Eight,
## development and test environments) stay loadable for automated regression
## tests and for developers, with a command-line argument after "--", e.g.
##   godot --path . -- --layout=exp_figure8_01
## which preselects that layout on the title screen. The visual theme (TRACK
## button: Green Valley / Heather Moor / Snow Pass) is independent of the
## layout. Unknown ids are ignored with a warning. Id "" = the race scene's own
## layout (the Classic Circuit; race scenes started without the title: tests,
## probes, the editor).

const LAYOUTS := {
	"kestrel_ridge": "res://src/track/layouts/kestrel_ridge.tres",
	"larkspur_ring": "res://src/track/layouts/larkspur_ring.tres",
	"ravenhook": "res://src/track/layouts/ravenhook.tres",
	"classic_01": "res://src/track/circuit_01.tres",
	"exp_figure8_01": "res://src/track/layouts/exp_figure8_01.tres",
}
## Layouts offered to players, in menu order.
const PLAYER_LAYOUTS: Array[String] = ["kestrel_ridge", "larkspur_ring", "ravenhook"]
const DEFAULT := "kestrel_ridge"
const ARG := "--layout="
const CLASSIC := ""
const NAMES := {
	"": "Classic Circuit",
	"kestrel_ridge": "Kestrel Ridge",
	"larkspur_ring": "Larkspur Ring",
	"ravenhook": "Ravenhook",
	"classic_01": "Classic Circuit (Legacy)",
	"exp_figure8_01": "Figure Eight (Experimental)",
}


## Layout ids the LAYOUT button cycles through: the player layouts, plus a
## legacy one a developer preselected on the command line.
static func ids(current: String = "") -> Array[String]:
	var out: Array[String] = PLAYER_LAYOUTS.duplicate()
	if not current.is_empty() and not out.has(current) and LAYOUTS.has(current):
		out.append(current)
	return out


static func display_name(id: String) -> String:
	return NAMES.get(id, id)


## The layout resource for an id (null = the scene's classic circuit).
static func load_layout(id: String) -> TrackLayout:
	return load(LAYOUTS[id]) if LAYOUTS.has(id) else null


## The id of a loaded layout ("" for the scene's classic circuit or an unknown one).
static func id_of(layout: TrackLayout) -> String:
	if layout != null:
		for id in LAYOUTS:
			if LAYOUTS[id] == layout.resource_path and id != "classic_01":
				return id
	return CLASSIC


## Id given on the command line ("" when none or unknown).
static func selected_id(args: PackedStringArray = OS.get_cmdline_user_args()) -> String:
	for a in args:
		if a.begins_with(ARG):
			var id := a.substr(ARG.length())
			if LAYOUTS.has(id):
				return id
			push_warning("DevLayouts: unknown layout '%s' (known: %s)" % [id, ", ".join(LAYOUTS.keys())])
	return ""


## The title screen's starting layout: the command-line one, else DEFAULT.
static func initial_id(args: PackedStringArray = OS.get_cmdline_user_args()) -> String:
	var id := selected_id(args)
	return id if not id.is_empty() else DEFAULT


## The command-line layout, or null for the race scene's own circuit.
static func load_selected(args: PackedStringArray = OS.get_cmdline_user_args()) -> TrackLayout:
	var id := selected_id(args)
	return load(LAYOUTS[id]) if not id.is_empty() else null
