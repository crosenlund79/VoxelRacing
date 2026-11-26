extends Node
## DIAGNOSTIC ONLY (Performance Investigation 001, branch
## claude/perf-investigation-001; never merged into the playable game).
##
## Deterministic benchmark scenarios with per-frame sampling. Inert unless the
## game is started with a user argument --bench=<scenario>:
##   godot --path . -- --bench=race --out=/tmp/b [options]
##   VoxelRacing.exe -- --bench=race --out=C:/bench [options]
## Options:
##   --out=DIR          results folder (CSV per frame + JSON summary)
##   --tag=NAME         run label (file prefix)
##   --secs=S           measured seconds (default 20)
##   --warm=S           warm-up seconds excluded from the statistics (default 5)
##   --res=WxH          window size (the 3D view renders at this size)
##   --cap=N            frame-rate cap (0 = uncapped, VSync off: the default)
##   --vsync=1          VSync on (capped pacing test)
##   --layout=ID --variant=1..5 --night=0|1 --laps=N
##   --iso=a,b,...      diagnostic isolation switches (see _isolate)
## Scenarios: menu, setup, race, combat, long, replay, garage, photo,
##   transitions, split, load.

const SCENARIOS := ["menu", "setup", "race", "combat", "long", "replay", "garage", "photo", "transitions", "split", "load"]

var scenario := ""
var args := {}
var out_dir := "user://bench"
var tag := ""
var _game: Node
var _main: Node
var _rows: Array = []
var _phase := "boot"
var _phase_t := 0.0
var _last_us := 0
var _last_phys := 0
var _vp_rid: RID
var _marks: Array = []
var _iso: PackedStringArray = []
var _log: Array = []
## Every viewport's RID (re-scanned twice a second): their render times are summed.
var _all_vps: Array = []  # Viewport nodes
var _vp_scan := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	scenario = str(args.get("bench", ""))
	if scenario == "":
		queue_free()
		return
	process_priority = 1000  # sample after everything else this frame
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = str(args.get("out", "user://bench"))
	tag = str(args.get("tag", scenario))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_iso = str(args.get("iso", "")).split(",", false)
	var cap := int(args.get("cap", "0"))
	Engine.max_fps = cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if str(args.get("vsync", "0")) == "1" else DisplayServer.VSYNC_DISABLED)
	if args.has("res"):
		var wh := str(args.res).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	PerfProbe.on = true
	_note("bench %s tag %s res %s cap %d vsync %s iso %s" % [scenario, tag, str(get_window().size), cap,
		str(args.get("vsync", "0")), ",".join(_iso)])
	_note("renderer %s / %s / %s" % [RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	_note("adapter vendor %s api %s debug_build %s" % [RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(), str(OS.is_debug_build())])
	_last_us = Time.get_ticks_usec()
	_last_phys = Engine.get_physics_frames()
	_run.call_deferred()


func _note(t: String) -> void:
	var line := "[%.2f] %s" % [Time.get_ticks_msec() / 1000.0, t]
	print("BENCH ", line)
	_log.append(line)


# ------------------------------------------------------------------ sampling

func _process(delta: float) -> void:
	if scenario == "":
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_us) / 1000.0
	_last_us = now
	var pf := Engine.get_physics_frames()
	var ticks := pf - _last_phys
	_last_phys = pf
	_phase_t += delta
	var probes := PerfProbe.take()
	_vp_scan -= 1
	if _vp_scan <= 0:
		_vp_scan = 10
		_all_vps.clear()
		var stack: Array = [get_tree().root]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			if x is Viewport:
				RenderingServer.viewport_set_measure_render_time((x as Viewport).get_viewport_rid(), true)
				_all_vps.append(x)
			stack.append_array(x.get_children())
	var gpu_all := 0.0
	var cpu_all := 0.0
	for v in _all_vps:
		if not is_instance_valid(v):
			continue
		var rid: RID = (v as Viewport).get_viewport_rid()
		gpu_all += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu_all += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var row := {
		"t": now / 1e6, "phase": _phase, "frame_ms": frame_ms, "ticks": ticks,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu(),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
		"render_gpu_all_ms": gpu_all, "render_cpu_all_ms": cpu_all + RenderingServer.get_frame_setup_time_cpu(), "viewports": _all_vps.size(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects_alive": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"mem_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buf_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"phys2d_active": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"phys2d_pairs": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		"probes": probes,
	}
	_rows.append(row)


func _set_phase(p: String) -> void:
	_phase = p
	_phase_t = 0.0
	_note("phase " + p)


## Waits n seconds of real time (frames keep being sampled).
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _until(cond: Callable, timeout_s: float = 600.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			_note("TIMEOUT waiting")
			return false
		await get_tree().process_frame
	return true


func _measure(label: String, secs: float = -1.0) -> void:
	_set_phase("measure:" + label)
	await _wait(secs if secs > 0.0 else float(args.get("secs", "20")))
	_set_phase("idle")


# ------------------------------------------------------------------ scenarios

func _run() -> void:
	await _frames(2)
	# the game's own main scene (the title) was loaded too: remove it, so each
	# scenario measures only what it builds itself
	var cs := get_tree().current_scene
	if cs != null:
		var cs_name := String(cs.name)
		cs.queue_free()
		await _frames(3)
		_note("removed the default main scene %s" % cs_name)
	match scenario:
		"menu": await _sc_menu()
		"setup": await _sc_setup()
		"race": await _sc_race()
		"combat": await _sc_combat()
		"long": await _sc_long()
		"replay": await _sc_replay()
		"garage": await _sc_garage()
		"photo": await _sc_photo()
		"transitions": await _sc_transitions()
		"split": await _sc_split()
		"load": await _sc_load()
		"gamerace": await _sc_gamerace()
		_: _note("unknown scenario " + scenario)
	_write()
	get_tree().quit()


func _new_game() -> void:
	_game = load("res://src/main/game.tscn").instantiate()
	_game.greetings_enabled = false
	get_tree().root.add_child(_game)
	PlayerControls.device_kind = PlayerControls.DEVICE_KEYBOARD  # (no device picker in benchmarks)
	await _frames(3)


func _sc_menu() -> void:
	await _new_game()
	_game.title._show_main()
	_set_phase("warmup")
	await _wait(float(args.get("warm", "5")))
	_isolate_menu()
	await _measure("menu_idle")
	# navigation: move focus every 0.5 s through the menu buttons
	_set_phase("measure:menu_nav")
	var end := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < end:
		var e := InputEventAction.new()
		e.action = "ui_down"
		e.pressed = true
		Input.parse_input_event(e)
		await _wait(0.5)


func _sc_setup() -> void:
	await _new_game()
	var t = _game.title
	t._show_main()
	await _wait(2.0)
	t._open_setup("quick")
	_set_phase("warmup")
	await _wait(float(args.get("warm", "5")))
	await _measure("setup_idle", 10.0)
	# cycling: one change every 1.5 s, as a player browsing
	_set_phase("measure:setup_cycle")
	for k in 12:
		var t0 := Time.get_ticks_usec()
		match k % 3:
			0: t._cycle_layout(1)
			1: t._cycle_track(1)
			2: t._cycle_time()
		_marks.append({"what": ["layout", "env", "time"][k % 3], "ms": (Time.get_ticks_usec() - t0) / 1000.0, "t": t0 / 1e6})
		await _wait(1.5)
	# revisits: the same combinations again (preview cache)
	_set_phase("measure:setup_revisit")
	for k in 12:
		var t0 := Time.get_ticks_usec()
		match k % 3:
			0: t._cycle_layout(1)
			1: t._cycle_track(1)
			2: t._cycle_time()
		_marks.append({"what": "revisit_" + ["layout", "env", "time"][k % 3], "ms": (Time.get_ticks_usec() - t0) / 1000.0, "t": t0 / 1e6})
		await _wait(1.0)
	_set_phase("idle")


## A race scene with the given settings; the player's car is driven by an AI
## driver so every run is identical (seeded) and the race HUD and camera are
## the ordinary player ones.
func _new_race(spectate := false, humans := 1) -> void:
	_main = load("res://src/main/main.tscn").instantiate()
	_main.use_command_line_layout = false
	_main.layout_override = DevLayouts.load_layout(str(args.get("layout", "kestrel_ridge")))
	_main.track_variant = int(args.get("variant", "1"))
	_main.night = str(args.get("night", "0")) == "1"
	_main.voice_enabled = str(args.get("voice", "1")) == "1"
	_main.weapons_lock_enabled = true
	if humans == 2:
		_main.human_count = 2
		_main.player_devices = [PlayerControls.KEYBOARD, 0] as Array[int]
	var t0 := Time.get_ticks_usec()
	get_tree().root.add_child(_main)
	_set_phase("load")
	await _until(func() -> bool: return DisplayServer.get_name() == "headless" or (_main.voxel != null and _main.voxel.ready_3d))
	var vb: int = _main.voxel.build_msec if _main.voxel != null else -1
	_marks.append({"what": "race_scene_ready_ms", "ms": (Time.get_ticks_usec() - t0) / 1000.0, "voxel_build_msec": vb})
	_note("race ready in %.0f ms (voxel build %d ms)" % [(Time.get_ticks_usec() - t0) / 1000.0, vb])
	_main.set_menu_choice(2 if spectate else 0)
	_main.set_weapons_enabled(str(args.get("weapons", "1")) == "1")
	_main.set_lap_count(int(args.get("laps", "3")))
	if not spectate:
		_ai_seat(RaceSession.PLAYER_ID)
		if humans == 2:
			_ai_seat(RaceSession.PLAYER_2_ID)
	_isolate_race()
	_main.start_race()


func _ai_seat(id: int) -> void:
	var params: AiParams = load(RivalRoster.params_path(3))  # a neutral, competent driver
	var d := AiDriver.new(_main.racing_line, params)
	var inp := AiDriverInput.new(id, d)
	_main.inputs[id] = inp
	inp.begin_race(_main.race_seed(_main.races_started, id))


func _racing() -> bool:
	return _main.session.state == RaceSession.State.RACING


func _sc_race() -> void:
	await _new_race(str(args.get("spectate", "0")) == "1")
	_set_phase("warmup")
	await _until(_racing, 60.0)
	await _wait(float(args.get("warm", "5")))
	await _measure("race")
	if str(args.get("micro", "0")) == "1":
		_micro()


## Micro-timings of suspect functions, called directly (diagnostic only; the
## race is paused around them so nothing else is measured).
func _micro() -> void:
	var s: RaceSession = _main.session
	var t0 := Time.get_ticks_usec()
	for k in 2000:
		s.standings()
	var std_us := (Time.get_ticks_usec() - t0) / 2000.0
	t0 = Time.get_ticks_usec()
	for k in 2000:
		s.position_of(k % 10)
	var pos_us := (Time.get_ticks_usec() - t0) / 2000.0
	t0 = Time.get_ticks_usec()
	for k in 200:
		_main._combat_states()
	var states_us := (Time.get_ticks_usec() - t0) / 200.0
	var rfx = _main.voxel.race_fx
	var dmg: VoxelCarDamage = rfx.damage[1]
	dmg.break_to(0.25, Vector3(1, 0, 0))
	t0 = Time.get_ticks_usec()
	for k in 10:
		dmg.dirty = true
		dmg.rebuild()
	var remesh_ms := (Time.get_ticks_usec() - t0) / 10000.0
	t0 = Time.get_ticks_usec()
	for k in 5:
		dmg._hull = null
		dmg.hull_mesh()
	var hull_ms := (Time.get_ticks_usec() - t0) / 5000.0
	dmg.restore()
	t0 = Time.get_ticks_usec()
	var pieces := 0
	for k in 3:
		var dd: VoxelCarDamage = rfx.damage[2 + k]
		pieces += dd.explode().size()
		dd.restore()
	var explode_ms := (Time.get_ticks_usec() - t0) / 3000.0
	var people := (_main.voxel.life._people as Array).size() if _main.voxel.life != null else 0
	var lights := 0
	var lights_on := 0
	for n in _all(_main.voxel):
		if n is OmniLight3D or n is SpotLight3D:
			lights += 1
			if (n as Node3D).is_visible_in_tree():
				lights_on += 1
	var info := {"what": "micro", "standings_us": std_us, "position_of_us": pos_us, "combat_states_us": states_us,
		"car_remesh_ms": remesh_ms, "car_hull_ms": hull_ms, "car_explode_ms": explode_ms, "explode_pieces_avg": pieces / 3.0,
		"people": people, "point_spot_lights": lights, "point_spot_lights_visible": lights_on,
		"car_grid": str(dmg.grid.size()) if dmg.get("grid") != null else "?"}
	_marks.append(info)
	_note("micro %s" % str(info))


## A race reached through the game's own flow (title, loading race, grid):
## lists every SubViewport and whether it renders while the race runs.
func _sc_gamerace() -> void:
	await _new_game()
	_game.title._show_main()
	await _wait(3.0)
	_game.start_race(2)
	await _until(func() -> bool: return _game.race != null and _game.race.voxel != null and _game.race.voxel.ready_3d and not _game._starting, 300.0)
	var race: Node = _game.race
	await _until(func() -> bool: return race.session.state == RaceSession.State.RACING, 60.0)
	await _wait(float(args.get("warm", "4")))
	var vps: Array = []
	for n in _all(get_tree().root):
		if n is SubViewport:
			var sv := n as SubViewport
			var shown := true
			var parent := sv.get_parent()
			if parent is CanvasItem:
				shown = (parent as CanvasItem).is_visible_in_tree()
			vps.append({"path": str(sv.get_path()), "size": str(sv.size), "update": sv.render_target_update_mode,
				"container_visible": shown, "own_world_3d": sv.own_world_3d, "disable_3d": sv.disable_3d})
	_marks.append({"what": "viewports", "list": vps})
	_note("viewports: %s" % str(vps))
	if _iso.has("no_hidden_vps"):
		for v in vps:
			if not bool(v.container_visible):
				var sv: SubViewport = get_tree().root.get_node(NodePath(String(v.path)))
				sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
				_note("disabled hidden viewport " + String(v.path))
	await _measure("gamerace")


## Heavy combat: every car fires whatever it can every 0.5 s (weapons forced,
## not the AI's choice), and a car is wrecked every 2 s, so explosions, debris,
## burn marks and crowd reactions pile up. Diagnostic load only.
func _sc_combat() -> void:
	await _new_race()
	_set_phase("warmup")
	await _until(func() -> bool: return _racing() and not _main.combat.locked, 90.0)
	await _wait(1.0)
	_set_phase("measure:combat")
	var end := Time.get_ticks_msec() + int(float(args.get("secs", "20")) * 1000.0)
	var k := 0
	while Time.get_ticks_msec() < end:
		_force_fire()
		if k % 4 == 3:
			_force_wreck(1 + (k / 4) % 9)
		k += 1
		await _wait(0.5)
	_set_phase("idle")


func _force_fire() -> void:
	var states: Array = _main._combat_states()
	for id in _main.grid_order:
		for slot in [CombatWorld.FRONT, CombatWorld.REAR]:
			if _main.combat.ammo[id][slot] <= 0:
				_main.combat.ammo[id][slot] = 3
			_main.combat.request(id, slot, states)


func _force_wreck(id: int) -> void:
	var t0 := Time.get_ticks_usec()
	var dw: DamageWorld = _main.damage
	if not dw.is_retired(id):
		dw.damage(id, dw.rules.max_condition * 0.55)
	_marks.append({"what": "force_damage", "car": id, "ms": (Time.get_ticks_usec() - t0) / 1000.0, "t": t0 / 1e6})


## Long race: 20 laps with combat forced now and then; measured windows at the
## start, the middle and the end, accelerated (x4) in between.
func _sc_long() -> void:
	args["laps"] = args.get("laps", "20")
	await _new_race()
	_set_phase("warmup")
	await _until(func() -> bool: return _racing() and not _main.combat.locked, 90.0)
	await _wait(2.0)
	var windows := int(args.get("windows", "5"))
	for w in windows:
		_snapshot_world("window_%d" % w)
		await _measure("long_w%d" % w, float(args.get("secs", "15")))
		if w == windows - 1:
			break
		# accelerate to the next window, with combat forced every second
		_main.set_sim_speed(4)
		_set_phase("accel")
		var end := Time.get_ticks_msec() + int(float(args.get("gap", "40")) * 1000.0)
		var k := 0
		while Time.get_ticks_msec() < end and _main.session.state == RaceSession.State.RACING:
			_force_fire()
			if k % 6 == 5:
				_force_wreck(1 + (k / 6) % 9)
			k += 1
			await _wait(1.0)
		_main.set_sim_speed(1)
		await _wait(1.0)
	_snapshot_world("end")


## Counts of the accumulating things (debris, burns, recorder) at a moment.
func _snapshot_world(label: String) -> void:
	var st: Node = _main.voxel
	var info := {"what": "world", "label": label, "race_time": _main.session.elapsed,
		"lap": _main.session.racers[0].tracker.laps_completed}
	if st != null:
		var fx = st.race_fx.fx if st.race_fx != null else null
		if fx != null:
			var flying := 0
			var settled := 0
			for k in fx._d_high:
				var stt: int = fx.d_state[k]
				if stt == 1:
					flying += 1
				elif stt == 2:
					settled += 1
			info["debris_flying"] = flying
			info["debris_settled"] = settled
			info["debris_high"] = fx._d_high
			info["debris_hash_cells"] = (fx._hash as Dictionary).size()
			info["debris_visible_instances"] = (fx._debris as MultiMesh).visible_instance_count
		if st.get("recorder") != null:
			var r = st.recorder
			info["rec_ring"] = (r.ring as Array).size()
			info["rec_captures"] = r.captures.size()
			var cap_samples := 0
			for c in r.captures:
				cap_samples += (c.get("samples", []) as Array).size()
			info["rec_capture_samples"] = cap_samples
			info["rec_launches"] = (r._launches as Array).size()
	info["debris_field_total"] = _main.debris_field.total() if _main.get("debris_field") != null else -1
	# what the scene holds, by node class (to find what accumulates)
	var hist := {}
	for n in _all(_main):
		var cls: String = n.get_class()
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path != "":
			cls += ":" + sc.resource_path.get_file()
		hist[cls] = int(hist.get(cls, 0)) + 1
	var top: Array = hist.keys()
	top.sort_custom(func(a, b) -> bool: return hist[a] > hist[b])
	var short := {}
	for k in top.slice(0, 14):
		short[k] = hist[k]
	info["node_classes"] = short
	info["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	info["mem_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_marks.append(info)
	_note("world %s" % str(info))


## Replay: a 1-lap race with forced combat, then the highlights are measured.
func _sc_replay() -> void:
	args["laps"] = args.get("laps", "1")
	await _new_race(true)  # (highlights play by themselves after a spectated race)
	await _until(func() -> bool: return _racing() and not _main.combat.locked, 90.0)
	_set_phase("race")
	var k := 0
	while _main.session.state == RaceSession.State.RACING:
		if k % 3 == 0:
			_force_fire()
		if k % 8 == 7:
			_force_wreck(1 + (k / 8) % 9)
		k += 1
		await _wait(0.5)
	_set_phase("finished")
	var rp = _main.voxel.replay
	await _until(func() -> bool: return rp != null and rp.playing, 120.0)
	_set_phase("measure:replay")
	var t_start := Time.get_ticks_msec()
	await _until(func() -> bool: return not rp.playing, 300.0)
	_marks.append({"what": "replay_length_s", "s": (Time.get_ticks_msec() - t_start) / 1000.0})
	_set_phase("after_replay")
	await _wait(3.0)


func _sc_garage() -> void:
	await _new_game()
	_game.title._show_main()
	await _wait(2.0)
	_game.title.hide_title()
	_game.garage.condition = 40.0
	_game.garage_screen.set_garage(_game.garage)
	_game.garage_screen.open()
	_set_phase("warmup")
	await _wait(float(args.get("warm", "5")))
	await _measure("garage_idle", 10.0)
	_set_phase("measure:garage_repair")
	for k in 3:
		_game.garage.money = 100000
		_game.garage_screen._repair_some.pressed.emit()
		await _wait(3.0)
	_set_phase("idle")


func _sc_photo() -> void:
	await _new_race()
	await _until(_racing, 60.0)
	await _wait(6.0)
	var pm = _main.voxel.photo
	_set_phase("warmup")
	pm._enter()
	await _wait(2.0)
	await _measure("photo_still", 8.0)
	# orbit the camera (as dragging the mouse / the right stick)
	_set_phase("measure:photo_orbit")
	var end := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < end:
		if pm.get("_yaw") != null:
			pm._yaw += 0.03
		if pm.get("_dist") != null:
			pm._dist = maxf(2.0, float(pm._dist) - 0.02)
		await get_tree().process_frame
	_set_phase("idle")


## Menu -> race -> (replay) -> results -> menu, n times; resources after each.
func _sc_transitions() -> void:
	await _new_game()
	var n := int(args.get("cycles", "4"))
	for c in n:
		_game.title._show_main()
		await _wait(3.0)
		_snapshot_global("menu_%d" % c)
		_set_phase("cycle_%d_load" % c)
		_game.start_race(2)  # spectate: an identical field every time
		await _until(func() -> bool: return _game.race != null and _game.race.voxel != null and _game.race.voxel.ready_3d and not _game._starting, 300.0)
		var race: Node = _game.race
		await _until(func() -> bool: return race.session.state != RaceSession.State.MODE_SELECT, 30.0)
		_set_phase("cycle_%d_race" % c)
		await _wait(6.0)
		var s: RaceSession = race.session
		for id in race.grid_order:
			s.finish_now(id)
		_set_phase("cycle_%d_after" % c)
		await _until(func() -> bool: return race.voxel.replay == null or not race.voxel.replay.playing or true, 5.0)
		await _wait(4.0)
		if race.voxel.replay != null and race.voxel.replay.playing:
			race.voxel.replay.stop()
		await _wait(2.0)
		race.leave_race()
		await _until(func() -> bool: return _game.race == null, 60.0)
		await _wait(3.0)
	_game.title._show_main()
	await _wait(3.0)
	_snapshot_global("menu_final")


func _snapshot_global(label: String) -> void:
	var info := {"what": "global", "label": label,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"mem_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buf_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"rss_mb": _rss_mb()}
	_marks.append(info)
	_note("global %s" % str(info))


func _rss_mb() -> float:
	if OS.get_name() != "Linux":
		return -1.0
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	for l in f.get_as_text().split("\n"):
		if l.begins_with("VmRSS:"):
			return float(l.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
	return -1.0


func _sc_split() -> void:
	await _new_race(false, 2)
	_set_phase("warmup")
	await _until(_racing, 60.0)
	await _wait(float(args.get("warm", "5")))
	await _measure("split")


## Loading: the game's own flow (title -> loading race -> grid), twice in one
## process (the second is "warm": in-process caches).
func _sc_load() -> void:
	await _new_game()
	_game.title._show_main()
	await _wait(3.0)
	for c in 2:
		_snapshot_global("before_load_%d" % c)
		var t0 := Time.get_ticks_usec()
		_set_phase("load_%d" % c)
		_game.start_race(2)
		await _until(func() -> bool: return _game.race != null and _game.race.voxel != null and _game.race.voxel.ready_3d, 300.0)
		var t_world := Time.get_ticks_usec()
		await _until(func() -> bool: return not _game._starting and not _game.loading.visible, 120.0)
		var t_grid := Time.get_ticks_usec()
		_marks.append({"what": "load", "n": c, "world_ready_ms": (t_world - t0) / 1000.0, "grid_ms": (t_grid - t0) / 1000.0,
			"voxel_build_msec": _game.race.voxel.build_msec})
		_set_phase("grid_%d" % c)
		await _wait(5.0)
		_snapshot_global("race_%d" % c)
		_game.race.leave_race()
		await _until(func() -> bool: return _game.race == null, 60.0)
		await _wait(3.0)


# ------------------------------------------------------------------ isolation

## Diagnostic switches (runtime only, nothing in the game changes): each turns
## one system off in this process so its cost can be compared with a baseline.
func _isolate_race() -> void:
	if _iso.is_empty():
		return
	(func() -> void:
		await _until(func() -> bool: return _main.voxel != null and _main.voxel.ready_3d, 300.0)
		await _frames(2)
		_apply_iso(_main.voxel)).call()


func _isolate_menu() -> void:
	if _iso.has("menu_preview_hidden"):
		pass


func _apply_iso(st: Node) -> void:
	for s in _iso:
		match s:
			"no_crowd":  # spectators, marshals (VoxelLife people MultiMeshes) not drawn, not animated
				if st.life != null:
					st.life.process_mode = Node.PROCESS_MODE_DISABLED
					st.life.visible = false
			"no_people":  # spectators and marshals only (people MultiMeshes hidden; their animation is in the shader)
				if st.life != null:
					for n in st.life.get_children():
						if n is MultiMeshInstance3D:
							(n as Node3D).visible = false
			"no_dressing":  # VoxelKit set dressing (barns, sheds, towers, toys...) hidden
				if st.life != null and st.life.get_node_or_null("Dressing") != null:
					st.life.get_node("Dressing").visible = false
			"no_life_lights":  # VoxelLife's own lights (stand roofs, dressing at night)
				if st.life != null:
					for n in _all(st.life):
						if n is Light3D:
							(n as Light3D).visible = false
			"no_life_process":  # VoxelLife's per-frame work only (still drawn)
				if st.life != null:
					st.life.set_process(false)
			"no_shadows":
				for n in _all(st):
					if n is Light3D:
						(n as Light3D).shadow_enabled = false
			"no_dir_shadow":
				for n in _all(st):
					if n is DirectionalLight3D:
						(n as DirectionalLight3D).shadow_enabled = false
			"no_omni_spot":  # every point / spot light hidden (night lighting)
				for n in _all(st):
					if n is OmniLight3D or n is SpotLight3D:
						(n as Light3D).visible = false
			"no_car_lights":
				for d in st.cars3d:
					for l in d.lights:
						if l is Node3D:
							(l as Node3D).visible = false
			"no_props":
				var props := st.get_node_or_null("Props")
				if props != null:
					props.visible = false
			"no_stands":
				var props := st.get_node_or_null("Props")
				if props != null:
					for n in props.get_children():
						var mi := n as MeshInstance3D
						if mi != null and mi.mesh != null and mi.mesh.has_meta("grandstand"):
							mi.visible = false
			"no_kit":  # VoxelKit set dressing
				for n in _all(st):
					if String(n.name).begins_with("Kit"):
						(n as Node3D).visible = false
			"no_fx":  # debris / sparks / smoke system (VoxelFx) neither simulated nor drawn
				var fx = st.race_fx.fx
				if fx != null:
					fx.process_mode = Node.PROCESS_MODE_DISABLED
					fx.visible = false
			"no_fx_draw":  # VoxelFx simulated, not drawn
				st.race_fx.fx.visible = false
			"no_race_fx":
				st.race_fx.visible = false
			"no_decals":  # tyre marks / burn marks offscreen viewport
				st.decal_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			"no_ssao":
				st.world_env.environment.ssao_enabled = false
			"no_glow":
				st.world_env.environment.glow_enabled = false
			"no_post":  # SSAO, glow, fog, tilt-shift
				var e: Environment = st.world_env.environment
				e.ssao_enabled = false
				e.glow_enabled = false
				e.fog_enabled = false
				if st.get("_tilt") != null:
					st._tilt.visible = false
			"no_tilt":
				if st.get("_tilt") != null:
					st._tilt.visible = false
			"no_recorder":
				if st.get("recorder") != null:
					st.recorder.process_mode = Node.PROCESS_MODE_DISABLED
			"no_audio":
				AudioServer.set_bus_mute(0, true)
				for n in _all(_main):
					if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
						n.process_mode = Node.PROCESS_MODE_DISABLED
			"no_hud":
				_main.hud.visible = false
			"no_legacy2d":  # the hidden HyperCars 2D presentation nodes stop processing
				for n in _all(_main):
					var p := String(n.get_script().resource_path) if n.get_script() != null else ""
					if p.ends_with("race_effects.gd") or p.ends_with("combat_view.gd") or p.ends_with("damage_view.gd") \
							or p.ends_with("jump_view.gd") or p.ends_with("track_scenery.gd"):
						n.process_mode = Node.PROCESS_MODE_DISABLED
			"no_2d_lights":  # the hidden HyperCars 2D lighting (PointLight2D head / tail lights, lens sprites)
				if _main.lighting != null:
					_main.lighting.set_process(false)
				for n in _all(_main):
					if n is PointLight2D:
						(n as PointLight2D).enabled = false
			"no_terrain":
				if st.vtrack != null:
					st.vtrack.visible = false
			"no_flowers_grass":
				for n in _all(st.vtrack):
					if n is MultiMeshInstance3D:
						(n as Node3D).visible = false
		_note("isolation applied: " + s)


func _all(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		out.append(x)
		stack.append_array(x.get_children())
	return out


# ------------------------------------------------------------------ output

func _write() -> void:
	var probe_names := {}
	for r in _rows:
		for k in (r.probes as Dictionary):
			probe_names[k] = true
	var pnames: Array = probe_names.keys()
	pnames.sort()
	var cols := ["t", "phase", "frame_ms", "ticks", "process_ms", "physics_ms", "render_cpu_ms", "render_gpu_ms", "render_gpu_all_ms",
		"render_cpu_all_ms", "viewports",
		"draw_calls", "objects", "primitives", "nodes", "orphans", "objects_alive", "resources", "mem_static_mb",
		"video_mem_mb", "tex_mem_mb", "buf_mem_mb", "phys2d_active", "phys2d_pairs"]
	var f := FileAccess.open("%s/%s_frames.csv" % [out_dir, tag], FileAccess.WRITE)
	var head := PackedStringArray(cols)
	for p in pnames:
		head.append("p:" + String(p))
	f.store_line(",".join(head))
	for r in _rows:
		var vals := PackedStringArray()
		for c in cols:
			vals.append(str(r[c]))
		for p in pnames:
			vals.append("%.3f" % ((r.probes as Dictionary).get(p, 0) / 1000.0))
		f.store_line(",".join(vals))
	f.close()
	# per-phase summaries
	var phases := {}
	for r in _rows:
		if not phases.has(r.phase):
			phases[r.phase] = []
		(phases[r.phase] as Array).append(r)
	var summary := {"scenario": scenario, "tag": tag, "args": args, "log": _log, "marks": _marks,
		"window": [get_window().size.x, get_window().size.y], "phases": {}}
	for ph in phases:
		var rs: Array = phases[ph]
		if rs.size() < 3:
			continue
		var ft: Array = rs.map(func(r: Dictionary) -> float: return float(r.frame_ms))
		var s := _stats(ft)
		var ticks := 0
		for r in rs:
			ticks += int(r.ticks)
		s["frames"] = rs.size()
		s["ticks"] = ticks
		for k in ["process_ms", "physics_ms", "render_cpu_ms", "render_gpu_ms", "render_gpu_all_ms", "render_cpu_all_ms", "viewports", "draw_calls", "objects", "primitives",
				"nodes", "mem_static_mb", "video_mem_mb", "phys2d_active"]:
			var vs: Array = rs.map(func(r: Dictionary) -> float: return float(r[k]))
			s[k + "_mean"] = _mean(vs)
			s[k + "_max"] = vs.max()
		var probe_tot := {}
		for r in rs:
			for k in (r.probes as Dictionary):
				probe_tot[k] = int(probe_tot.get(k, 0)) + int(r.probes[k])
		var pr := {}
		for k in probe_tot:
			pr[String(k)] = {"ms_per_frame": probe_tot[k] / 1000.0 / rs.size(),
				"ms_per_tick": (probe_tot[k] / 1000.0 / maxi(1, ticks)) if String(k).begins_with("sim.") else null}
		s["probes"] = pr
		summary.phases[ph] = s
	var jf := FileAccess.open("%s/%s_summary.json" % [out_dir, tag], FileAccess.WRITE)
	jf.store_string(JSON.stringify(summary, "  "))
	jf.close()
	_note("wrote %s/%s_*.csv/json (%d frames)" % [out_dir, tag, _rows.size()])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / a.size()


func _stats(ft: Array) -> Dictionary:
	var s := ft.duplicate()
	s.sort()
	var n := s.size()
	var mean := _mean(s)
	var var_ := 0.0
	for v in s:
		var_ += (float(v) - mean) * (float(v) - mean)
	var sd := sqrt(var_ / n)
	var med: float = s[n / 2]
	var slow1: Array = s.slice(int(n * 0.99), n)
	var low1_ms := _mean(slow1) if not slow1.is_empty() else float(s[-1])
	var spikes := 0
	var over33 := 0
	for v in ft:
		if float(v) > 2.0 * med:
			spikes += 1
		if float(v) > 33.3:
			over33 += 1
	return {"avg_fps": 1000.0 / mean, "mean_ms": mean, "median_ms": med, "p95_ms": s[int(n * 0.95)],
		"p99_ms": s[mini(n - 1, int(n * 0.99))], "max_ms": s[-1], "low1_fps": 1000.0 / low1_ms, "stdev_ms": sd,
		"spikes_2x_median": spikes, "frames_over_33ms": over33}
