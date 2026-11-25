extends SceneTree
## Test helper, run in a fresh Godot process by the determinism tests:
##   godot --headless --path <project> --fixed-fps 60 -s res://tests/support/sim_probe.gd -- \
##         mode=race|spectate speed=1 presentation=1 ticks=900 weapons=0|1 style=0|1 achievements=0|1 theme=1..3 layout=<dev layout id> pause=<tick> damage=0|1 lock=0|1 contact=0|1
## lock=0 switches the Weapons Hot start lock off, contact=0 the contact yaw
## (with damage=0 lock=0 contact=0 the race is exactly the pre-M6 race).
## damage=0 switches M6 vehicle damage off (the race must then be identical to
## the pre-M6 fingerprints); with damage on, the cars' condition is hashed too.
## Prints "PROBE <md5>" of every car's and driver's exact state after `ticks`.
## A fresh process matters: Godot's physics broadphase keeps history between
## scenes in one process, which changes the order multi-car contacts resolve.

var main: Node2D
var opts := {"mode": "spectate", "speed": "1", "presentation": "1", "ticks": "900", "weapons": "0", "lighting": "0", "style": "0", "achievements": "0", "theme": "1", "damage": "1", "lock": "1", "contact": "1"}
var tick := 0
const PROBE_STORE := "user://probe_achievements.cfg"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	main = load("res://src/main/main.tscn").instantiate()
	main.presentation_enabled = opts.presentation == "1"
	if "lighting_on_start" in main:
		main.lighting_on_start = opts.lighting == "1"
	if opts.achievements == "1":
		main.achievements = AchievementStore.new(PROBE_STORE)
	if "track_variant" in main:
		main.track_variant = int(opts.theme)
	if "damage_enabled" in main:
		main.damage_enabled = opts.damage == "1"
	if "weapons_lock_enabled" in main:
		main.weapons_lock_enabled = opts.lock == "1"
	if opts.contact == "0" and "contact_yaw_factor" in main.driving_params:
		main.driving_params = main.driving_params.duplicate()
		main.driving_params.contact_yaw_factor = 0.0
	if opts.has("layout") and DevLayouts.LAYOUTS.has(opts.layout):
		main.layout_override = load(DevLayouts.LAYOUTS[opts.layout])
	root.add_child(main)
	physics_frame.connect(_on_tick)


var _paused_left := 0


func _paused_frame() -> void:
	_paused_left -= 1
	if _paused_left == 0:
		process_frame.disconnect(_paused_frame)
		main.resume_race()
		_paused_left = -1  # paused once


func _on_tick() -> void:
	# pause=<tick>: open the race menu (paused) at that tick for 90 frames, then
	# resume; paused frames do not count, so the race must end identical
	if main.get("menu_open"):
		return  # paused: no race tick
	if opts.has("pause") and tick == int(opts.pause) and _paused_left == 0 and not main.menu_open:
		main.open_race_menu()
		_paused_left = 90
		process_frame.connect(_paused_frame)  # physics frames stop while paused
		return
	tick += 1
	if tick == 2:
		if main.has_method("set_weapons_enabled"):
			main.set_weapons_enabled(opts.weapons == "1")
		if opts.style != "0":
			main.set_combat_style(int(opts.style))
		if opts.mode == "spectate":
			main.set_menu_choice(2)
		main.set_sim_speed(int(opts.speed))
		main.start_race()
		if opts.mode == "race":
			Input.action_press("fire")
	if opts.mode == "race" and tick > 2:
		# Scripted player steering, identical in every run.
		if tick % 90 == 30:
			Input.action_press("steer_right")
		elif tick % 90 == 45:
			Input.action_release("steer_right")
	if tick == 2 + int(opts.ticks):
		var s := []
		for c in main.cars:
			s.append_array([c.global_position, c.model.velocity, c.model.heading])
		for d in main.drivers:
			if d != null:
				s.append_array([d.lane_bias, d.commitment, d.fluster_time])
		for r in main.session.racers:
			s.append_array([r.progress, r.tracker.laps_completed, r.tracker.next_checkpoint])
		if opts.weapons == "1" and main.get("combat") != null:
			s.append(main.combat.state_snapshot())
		if opts.damage == "1" and main.get("damage") != null:
			s.append(main.damage.state_snapshot())
			for r in main.session.racers:
				s.append(r.dnf)
		print("PROBE ", var_to_bytes(s).hex_encode().md5_text())
		if opts.achievements == "1":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE_STORE))
		main.set_sim_speed(1)
		quit()
