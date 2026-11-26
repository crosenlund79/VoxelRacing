class_name CombatView
extends Node2D
## Combat presentation that is not geometry: weapon sounds (launches, empty
## clicks, cycling, explosions) and the pulsing red warning halo under each
## mine, painted on the ground (decal layer, under the cars). The missiles,
## mines, blasts and wreck smoke themselves are voxels (VoxelRaceFx).
## Read-only: it reads the combat state and its append-only event log through
## its own cursor, and never changes combat, cars or the race.

const W := WeaponRules.Weapon
const MINE_HALO_RADIUS := 17.0
const MINE_HALO_COLOR := Color(0.95, 0.22, 0.12)
const LAUNCH_SOUNDS := {W.MINE: "weapons/mine_drop", W.HOMING_MISSILE: "weapons/homing_launch",
	W.SUPER_MISSILE: "weapons/super_launch"}

var enabled := true
## Racer ids whose empty-weapon clicks are heard (the humans).
var human_ids: Array[int] = [RaceSession.PLAYER_ID]
var _combat: CombatWorld
var _cars: Array[Car] = []
var _audio: RaceAudio
## Mine halos are drawn on this node (ground decals).
var halos: Node2D
var level_of: Callable
var _cursor := 0


func setup(combat: CombatWorld, cars: Array[Car], _resolver: AssetResolver, audio: RaceAudio) -> void:
	_combat = combat
	_cars = cars
	_audio = audio
	halos = Node2D.new()
	halos.name = "MineHalos"
	halos.draw.connect(_draw_halos)
	add_child(halos)


## Elevated layouts: kept for the race scene's call (mines on the bridge
## are shown by their voxel model; their halo is on the ground layer only).
func setup_levels(p_level_of: Callable) -> void:
	level_of = p_level_of


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	if not on:
		_cursor = _combat.events.size()


func _process__perf(_delta: float) -> void:
	if not enabled or _combat == null:
		return
	if _cursor > _combat.events.size():
		_cursor = 0  # combat was reset for a new race
	while _cursor < _combat.events.size():
		_show_event(_combat.events[_cursor])
		_cursor += 1
	halos.queue_redraw()


func _show_event(e: Dictionary) -> void:
	match e.kind:
		"fire":
			_play(LAUNCH_SOUNDS.get(e.type, "weapons/missile_launch"), e.pos)
		"empty":
			if human_ids.has(e.car):
				_play("weapons/empty", e.pos)
		"switch":  # weapon cycling (only a human cycles): a soft click at the car
			if human_ids.has(e.car):
				_play("ui/ui_move", _cars[e.car].global_position)
		"explode", "mine_blast":
			_play("weapons/explosion", e.pos)


## Red halo under each mine on the ground, pulsing with its blink.
func _draw_halos() -> void:
	for k in _combat.mines.size():
		var m: Dictionary = _combat.mines[k]
		if int(m.get("level", 0)) == 1:
			continue
		var fast_blink: bool = m.age > _combat.rules.mine_fuse - 1.0
		var pulse := 0.5 + 0.5 * sin(m.age * TAU * (4.0 if fast_blink else 1.5))
		halos.draw_circle(m.pos, MINE_HALO_RADIUS, Color(MINE_HALO_COLOR, lerpf(0.12, 0.3, pulse)))
		halos.draw_arc(m.pos, MINE_HALO_RADIUS, 0.0, TAU, 28, Color(MINE_HALO_COLOR, lerpf(0.45, 0.85, pulse)), 2.0, true)


func _play(logical: String, pos: Vector2) -> void:
	if _audio != null:
		_audio.play_at(logical, pos)


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(_delta)
	PerfProbe.add(&"legacy2d.combat_view", __t)
