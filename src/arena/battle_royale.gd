class_name BattleRoyale
extends Node2D
## GO RACING! > BATTLE ROYALE: ten cars in the Scrapyard, everyone against
## everyone, no laps and no respawns - a destroyed car is out for good, and the
## last car standing wins. Weapons never run out (front missiles and mines on
## their own cooldowns; no homing or super missiles). After ZONE_START seconds
## the safe zone closes in and wears down any car outside it, so every match
## ends. Built from the existing systems: Car (driving and contacts),
## CombatWorld (unlimited, Tactical cooldowns from arena_weapon_rules.tres),
## DamageWorld (condition: collisions and the zone; zero = out), CombatStats
## (kill feed, K / D / tombstones), the HUD, effects, audio, lighting and
## weather. Local single-player only (not over the network).

signal exit_requested
## Tab on the result: another match.
signal restart_requested

const CAR_SCENE := preload("res://src/driving/car.tscn")
const WEAPON_RULES := preload("res://src/arena/arena_weapon_rules.tres")
const DAMAGE_RULES := preload("res://src/damage/default_damage_rules.tres")
const PLAYER := RaceSession.PLAYER_ID
const FIGHT_DELAY := 2.0
const ZONE_START := 70.0
const ZONE_CLOSE_TIME := 90.0
const ZONE_MIN_RADIUS := 240.0
## Condition (%) lost per second outside the zone.
const ZONE_DAMAGE := 8.0
## Condition (%) a weapon hit costs (a hit also stuns the car for the rules'
## wreck_time); zero condition = eliminated. Five missiles, or a couple of
## mines and some ramming.
const HIT_DAMAGE := {WeaponRules.Weapon.FRONT_MISSILE: 20.0, WeaponRules.Weapon.REAR_MISSILE: 20.0,
	WeaponRules.Weapon.MINE: 34.0}
## Seconds after FIGHT! before the weapons go hot.
const WEAPONS_HOT_AFTER := 3.0
const CELEBRATION_TIME := 4.0
const SKIP_SPEED := 8

var track_variant := 1
var night := false
## Settings: the player's headlight colour (LightingPilot.HEADLIGHT_PALETTE index; cosmetic).
var headlight_color := 0
var player_car := 0
var displaced: Array[int] = []
var presentation_enabled := true
## The game's music player (set by the game root; null: the race audio makes its own).
var music: MusicPlayer = null
var base_seed := 0
## Tests / demos: the player's car is driven by the arena AI too.
var player_ai := false
var allow_exit := true

var resolver: AssetResolver
var theme: TrackTheme
var arena: Arena
var cars: Array[Car] = []
var ais: Array = []
var human_input: HumanDriverInput
var session: RaceSession
var combat: CombatWorld
var damage: DamageWorld
var stats: CombatStats
var hud: Hud
var camera: FollowCamera
var kill_feed: KillFeed
var defeat_popup: DefeatPopup
## The defeat popup appears only for the hit that eliminates the player.
var eliminations_only := true
var race_menu: RaceMenu
var lighting: LightingPilot
var combat_view: CombatView
var race_audio: RaceAudio
var effects: RaceEffects
var damage_view: DamageView
## Compatibility with the race scene's presentation helpers (DefeatPopup).
var net = null
var player_views = null
var races_started := 1
var local_player_id := PLAYER

var zone_radius := 0.0
var winner := -1
var watching := false
var follow_id := -1
var _fight_left := FIGHT_DELAY
var _impacts: Array = []
var _stall := PackedFloat32Array()
var _celebrate_left := -1.0
var _skipping := false
var _menu_paused := false
## The Esc menu is open (the human's car brakes; read by HumanDriverInput).
var menu_open := false
var _driving_params: DrivingParams
var _shown_result := false
## Per car: the last weapon hit {by, weapon, time} (credits an elimination).
var _last_hit: Array = []


func _ready() -> void:
	PlayerControls.ensure_actions()
	resolver = AssetResolver.new()
	theme = TrackTheme.load_variant(track_variant)
	_driving_params = theme.driving(load("res://src/driving/default_driving_params.tres"))
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build(resolver, theme)
	var decals := Node2D.new()
	decals.name = "Decals"
	add_child(decals)
	var names := PackedStringArray(["YOU"])
	for i in range(1, 10):
		names.append(RivalRoster.short_name(i))
	session = RaceSession.new(2, 1, names)  # (no laps in the arena: never driven through)
	var textures := {}
	var full_names := {}
	for i in 10:
		var c: Car = CAR_SCENE.instantiate()
		c.name = "Car%d" % i
		c.racer_id = i
		add_child(c)
		var logical := _car_image(i)
		var look := CarArt.look(resolver, logical)
		c.setup(_driving_params, CarModel.ControlMode.FIRE_TO_ACCELERATE, look.body)
		if logical == AssetCatalog.CAR_JUNKER:
			c.sprite.modulate = CarArt.JUNKER_TINTS[i % CarArt.JUNKER_TINTS.size()]
		c.collision_layer = Track.CAR_LAYER
		c.collision_mask = Track.WALL_LAYER | Track.CAR_LAYER
		c.place(arena.layout.spawns[i])
		c.active = false
		c.wall_hit.connect(func(_n: Vector2, speed: float) -> void: _impacts.append([i, -1, speed]))
		c.car_hit.connect(func(other: Car, speed: float) -> void: _impacts.append([i, other.racer_id, speed]))
		cars.append(c)
		textures[i] = CarArt.icon(resolver, logical)
		full_names[i] = "YOU" if i == PLAYER else RivalRoster.full_name(i)
		if look.wheels and presentation_enabled:
			CarWheels.new().setup(c, resolver.get_texture(AssetCatalog.WHEEL), preload("res://src/presentation/default_wheel_layout.tres"), look.body_logical)
		ais.append(null if i == PLAYER and not player_ai else ArenaAi.new(
			load(RivalRoster.params_path(i)) if i > 0 else load(RivalRoster.params_path(2)), hash([base_seed, i])))
	human_input = HumanDriverInput.new(PLAYER)
	_stall.resize(10)
	for i in 10:
		_last_hit.append({})
	combat = CombatWorld.new(WEAPON_RULES, 10)
	combat.style = WeaponRules.Style.TACTICAL
	combat.unlimited = true
	combat.blocked = func(p: Vector2) -> bool: return arena.layout.blocked(p)
	combat.enabled = true
	combat.locked = true  # FIGHT! first, weapons a moment later
	for i in 10:
		combat.set_loadout(i, WeaponRules.Weapon.FRONT_MISSILE, 999, WeaponRules.Weapon.MINE, 999)
	damage = DamageWorld.new(DAMAGE_RULES, 10)
	stats = CombatStats.new(10)
	zone_radius = arena.layout.radius()
	camera = FollowCamera.new()
	add_child(camera)
	camera.target = cars[PLAYER]
	camera.make_current()
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(resolver)
	hud.set_field(textures, full_names)
	hud.stats = stats
	hud.track_name = "BATTLE ROYALE  -  THE SCRAPYARD"
	hud.results_title = "BATTLE ROYALE  -  RESULTS"
	race_menu = RaceMenu.new()
	add_child(race_menu)
	race_menu.setup(HyperTheme.build(resolver))
	race_menu.set_leave_text("LEAVE THE ARENA")
	race_menu.resume_requested.connect(_resume)
	race_menu.leave_requested.connect(func() -> void:
		_resume()
		exit_requested.emit())
	if presentation_enabled:
		var zone := ZoneView.new()
		zone.name = "Zone"
		zone.arena = self
		add_child(zone)
		effects = RaceEffects.new()
		add_child(effects)
		effects.setup(cars, resolver, decals, theme.dust_color)
		race_audio = RaceAudio.new()
		add_child(race_audio)
		race_audio.setup(cars, resolver, self)
		combat_view = CombatView.new()
		add_child(combat_view)
		combat_view.setup(combat, cars, resolver, race_audio)
		combat_view.human_ids = [PLAYER] as Array[int]
		damage_view = DamageView.new()
		add_child(damage_view)
		damage_view.setup(damage, cars, resolver, race_audio)
		var marker := PlayerMarker.new()
		add_child(marker)
		marker.setup([cars[PLAYER]] as Array[Car])
		kill_feed = KillFeed.new()
		add_child(kill_feed)
		var short := {PLAYER: "YOU"}
		for i in range(1, 10):
			short[i] = RivalRoster.short_name(i)
		kill_feed.setup(stats, resolver, short, {PLAYER: HyperTheme.GOLD})
		defeat_popup = DefeatPopup.new()
		add_child(defeat_popup)
		defeat_popup.setup(self, resolver, textures)
		lighting = LightingPilot.new()
		add_child(lighting)
		lighting.setup(null, cars, combat, resolver, theme)
		var lamp := resolver.get_texture(AssetCatalog.LAMP_POST)
		for spot in arena.lamp_spots:
			lighting.add_lamp(spot[0], spot[1], lamp)
		lighting.set_own_headlights([PLAYER] as Array[int], LightingPilot.headlight_color(headlight_color))
		lighting.set_enabled(night)
		if theme.weather != "":
			var weather := WeatherView.new()
			add_child(weather)
			weather.setup(theme.weather, night)
		race_audio.play_music("battle")  # its own theme (docs/MUSIC.md)
	session.start()
	hud.flash_banner("FIGHT!", HyperTheme.RED, FIGHT_DELAY - 0.6)
	if race_audio != null:
		race_audio.play_cue("race/start_go")


func _car_image(id: int) -> String:
	if id == PLAYER:
		return AssetCatalog.ai_car(player_car) if player_car > 0 else AssetCatalog.CAR_PLAYER
	return AssetCatalog.CAR_JUNKER if displaced.has(id) else AssetCatalog.ai_car(id)


func is_two_player() -> bool:
	return false


func alive() -> Array[int]:
	var out: Array[int] = []
	for i in 10:
		if not session.racers[i].is_done():
			out.append(i)
	return out


func _exit_tree() -> void:
	if _menu_paused:
		get_tree().paused = false
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ the fight

func _physics_process(_delta: float) -> void:
	var step := Car.FIXED_STEP
	if session.state == RaceSession.State.FINISHED and winner >= 0:
		_after_tick(step)
		if _skipping:
			_set_speed(1)
			_skipping = false
		if Input.is_action_just_pressed(PlayerControls.CONFIRM):
			exit_requested.emit()
		elif Input.is_action_just_pressed(PlayerControls.HISTORY_VIEW):
			restart_requested.emit()
		return
	if Input.is_action_just_pressed(PlayerControls.BACK) and not race_menu.is_open():
		_open_menu()
		return
	if _fight_left > 0.0:
		_fight_left -= step
		if _fight_left <= 0.0:
			for i in 10:
				cars[i].active = true
		_after_tick(step)
		return
	session.tick(step)
	if combat.locked and session.elapsed >= WEAPONS_HOT_AFTER:
		combat.unlock()
	_apply_impacts()
	_drive(step)
	_combat_step(step)
	_zone_step(step)
	_unstick(step)
	_check_winner()
	_watch_tick(step)
	_after_tick(step)


func _drive(step: float) -> void:
	var others_all: Array = []
	for i in alive():
		var c := cars[i]
		others_all.append({"id": i, "position": c.global_position, "heading": c.model.heading,
			"velocity": c.model.velocity, "condition": damage.fraction(i)})
	var states := _states()
	for i in alive():
		var c := cars[i]
		if not c.active:
			continue
		var cmd: Dictionary
		if ais[i] == null:
			var h := human_input.drive(self, step)
			var w := human_input.weapons(self, step, states)
			cmd = {"steer": h.steer, "fire": h.fire, "front": w.front, "rear": w.rear}
		else:
			var others := others_all.filter(func(o: Dictionary) -> bool: return o.id != i)
			cmd = ais[i].decide({"id": i, "position": c.global_position, "heading": c.model.heading, "velocity": c.model.velocity},
				others, arena.layout, step, combat.can_fire(i, CombatWorld.FRONT), combat.can_fire(i, CombatWorld.REAR))
		c.steer = cmd.steer
		c.fire = cmd.fire
		if cmd.front:
			combat.request(i, CombatWorld.FRONT, states)
		if cmd.rear:
			combat.request(i, CombatWorld.REAR, states)


func _states() -> Array:
	var states: Array = []
	for i in 10:
		states.append({"position": cars[i].global_position, "heading": cars[i].model.heading,
			"present": not session.racers[i].is_done()})
	return states


## Weapons: a hit costs condition and stuns the car briefly; at zero
## condition the car is eliminated for good (no respawn).
func _combat_step(step: float) -> void:
	var first := combat.events.size()
	var result := combat.step(step, _states())
	for k in range(first, combat.events.size()):
		var e: Dictionary = combat.events[k]
		if e.kind != "destroyed" or session.racers[e.car].is_done():
			continue
		if e.owner >= 0 and e.owner != e.car:
			_last_hit[e.car] = {"by": e.owner, "weapon": e.type, "time": session.elapsed}
		if ais[e.car] != null:
			ais[e.car].hit_by(e.owner)
		if damage.damage(e.car, HIT_DAMAGE.get(e.type, 20.0)):
			_eliminate(e.car, true, e.owner, e.type)
	for id in result.destroyed:
		if not session.racers[id].is_done():
			cars[id].active = false  # stunned by the hit
			cars[id].model.velocity *= 0.2
	for id in result.respawned:
		if not session.racers[id].is_done():
			cars[id].active = true


## Car and wall contacts wear the cars down as on a circuit (zero = out).
func _apply_impacts() -> void:
	damage.step(Car.FIXED_STEP)
	for imp in _impacts:
		var id: int = imp[0]
		var other: int = imp[1]
		if session.racers[id].is_done():
			continue
		if other < 0:
			if damage.wall_impact(id, imp[2]):
				_eliminate(id, false)
			continue
		if session.racers[other].is_done():
			continue
		var before := [damage.condition[id], damage.condition[other]]
		var outs := damage.car_impact(id, other, imp[2])
		if damage.condition[id] < before[0]:
			stats.on_contact(id, other, session.elapsed)
			if ais[id] != null:
				ais[id].hit_by(other)
		if damage.condition[other] < before[1]:
			stats.on_contact(other, id, session.elapsed)
			if ais[other] != null:
				ais[other].hit_by(id)
		for out in outs:
			_eliminate(out, false)
	_impacts.clear()


## After ZONE_START the safe circle closes towards the middle; outside it a
## car loses ZONE_DAMAGE % per second.
func _zone_step(step: float) -> void:
	var t := session.elapsed - ZONE_START
	if t <= 0.0:
		return
	zone_radius = lerpf(arena.layout.radius(), ZONE_MIN_RADIUS, clampf(t / ZONE_CLOSE_TIME, 0.0, 1.0))
	for i in alive():
		if cars[i].global_position.length() > zone_radius:
			if damage.damage(i, ZONE_DAMAGE * step):
				_eliminate(i, false)


## A car stalled nose-first against a wall (no reverse gear) gets turned a
## little so it can drive off again - the same for every driver.
func _unstick(step: float) -> void:
	for i in alive():
		var c := cars[i]
		if c.active and c.fire and c.model.velocity.length() < 20.0:
			_stall[i] += step
			if _stall[i] > 1.5:
				c.model.yaw_rate = 1.4
				_stall[i] = 0.0
		else:
			_stall[i] = 0.0


## A car is out. by_weapon: a weapon's hit took the last condition (credited
## to its owner, with its icon); otherwise (collisions, walls, the zone) a
## recent weapon hit or damaging contact is credited, as on a circuit.
func _eliminate(id: int, by_weapon: bool, owner: int = -1, weapon: int = -1) -> void:
	if session.racers[id].is_done():
		return
	var hit: Dictionary = _last_hit[id]
	if not by_weapon and not hit.is_empty() and session.elapsed - float(hit.time) <= CombatStats.ATTRIBUTION_TIME:
		by_weapon = true  # worn out right after a weapon hit: that driver's elimination
		owner = hit.by
		weapon = hit.weapon
	if by_weapon:
		stats.on_destroyed(id, owner, weapon, session.elapsed)
	stats.on_retired(id, session.elapsed, by_weapon)
	session.set_progress(id, session.elapsed)  # later out = ranked higher
	session.racers[id].result_note = "OUT %s" % Hud.format_time(session.elapsed).left(5)
	session.retire(id)
	var c := cars[id]
	c.active = false
	c.model.velocity = Vector2.ZERO
	c.collision_layer = 0
	c.collision_mask = 0
	if id == follow_id:
		follow_id = -1
	if id == PLAYER and not player_ai and hud != null:
		hud.show_caption("ELIMINATED!", "THE FIGHT GOES ON - WATCH THE SURVIVORS", HyperTheme.RED)
		hud.set_watch_hint(PlayerControls.fmt("{confirm}: watch now      {history_view}: skip to the result"))
		_celebrate_left = CELEBRATION_TIME
	elif hud != null:
		hud.flash_banner("%s OUT!" % session.racers[id].display_name.to_upper(), HyperTheme.RED, 0.8)


func _check_winner() -> void:
	var left := alive()
	if left.size() > 1 or winner >= 0:
		return
	winner = left[0] if left.size() == 1 else -1
	if winner < 0:  # (everyone out on the same tick: the last one eliminated wins)
		winner = session.standings()[0].id
	session.racers[winner].result_note = "WINNER"
	session.finish_now(winner)
	cars[winner].fire = false
	watching = false
	if hud != null:
		hud.hide_caption()
		hud.set_watch_hint("")
		hud.flash_banner("YOU WIN!" if winner == PLAYER else "%s WINS!" % session.racers[winner].display_name.to_upper(),
			HyperTheme.GOLD, 2.0)
	if effects != null:
		effects.celebrate(cars[winner].global_position)


# ------------------------------------------------- eliminated: watch the rest

func _watch_tick(step: float) -> void:
	if player_ai or not session.racers[PLAYER].is_done() or winner >= 0:
		return
	if Input.is_action_just_pressed(PlayerControls.HISTORY_VIEW) and not _skipping:
		_skipping = true
		_begin_watching()
		_set_speed(SKIP_SPEED)
		hud.set_watch_hint("Skipping to the result...")
	if not watching:
		_celebrate_left -= step / maxf(1.0, Engine.time_scale)
		if _celebrate_left <= 0.0 or Input.is_action_just_pressed(PlayerControls.CONFIRM):
			_begin_watching()
		return
	if Input.is_action_just_pressed(PlayerControls.STEER_LEFT):
		_follow_step(-1)
	elif Input.is_action_just_pressed(PlayerControls.STEER_RIGHT):
		_follow_step(1)


func _begin_watching() -> void:
	if watching:
		return
	watching = true
	hud.hide_caption()
	if not _skipping:
		hud.set_watch_hint(PlayerControls.fmt("WATCHING      {steer_left} / {steer_right}: switch car      {history_view}: skip to the result"))


func _follow_step(dir: int) -> void:
	var left := alive()
	if left.is_empty():
		return
	var k := left.find(follow_id)
	follow_id = left[posmod(k + dir, left.size())] if k >= 0 else left[0]


## The car the camera shows while watching: the chosen one, else the one with
## the most action (closest to an opponent).
func _watch_target() -> int:
	var left := alive()
	if left.has(follow_id):
		return follow_id
	var best := -1
	var best_d := INF
	for a in left:
		for b in left:
			if a < b:
				var d := cars[a].global_position.distance_to(cars[b].global_position)
				if d < best_d:
					best_d = d
					best = a
	follow_id = best
	return best


func _set_speed(multiplier: int) -> void:
	Engine.physics_ticks_per_second = 60 * multiplier
	Engine.time_scale = multiplier
	Engine.max_physics_steps_per_frame = maxi(8, multiplier * 2)
	if effects != null:
		effects.set_enabled(multiplier == 1)
	if combat_view != null:
		combat_view.set_enabled(multiplier == 1)


# --------------------------------------------------------------- presentation

func _after_tick(_step: float) -> void:
	if hud == null:
		return
	if watching and winner < 0:
		var t := _watch_target()
		if t >= 0:
			camera.target = cars[t]
	elif winner >= 0:
		camera.target = cars[winner]
	var left := alive().size() + (1 if winner >= 0 else 0)
	hud.update_battle(left, 10, stats.kills[PLAYER], session.elapsed)
	var zone_note := ""
	if session.elapsed > ZONE_START - 10.0 and winner < 0:
		zone_note = "  -  ZONE CLOSING" if session.elapsed >= ZONE_START else "  -  ZONE CLOSES IN %d" % ceili(ZONE_START - session.elapsed)
	hud.set_mode_line("BATTLE ROYALE  -  %d LEFT%s" % [left, zone_note] if winner < 0 else
		"BATTLE ROYALE  -  WINNER: %s" % session.racers[winner].display_name.to_upper())
	var me := PLAYER
	hud.update_combat(true, combat.weapon_of(me, CombatWorld.FRONT), 999, combat.weapon_of(me, CombatWorld.REAR), 999, 0.0,
		_cooldown(CombatWorld.FRONT), _cooldown(CombatWorld.REAR))
	hud.update_condition(damage.fraction(me), damage.since_hit[me], damage.is_critical(me), false, not session.racers[me].is_done())
	hud.set_follow(false, follow_id)
	hud.update_tower(session.standings())
	if winner >= 0 and not _shown_result:
		_shown_result = true
	if winner >= 0 and not hud.banner_showing():
		hud.show_results(session.standings(), "{confirm}: back to the menu      {history_view}: fight again")


func _cooldown(slot: int) -> float:
	return clampf(combat.slot_wait(PLAYER, slot) / maxf(0.001, combat.slot_cooldown_length(slot)), 0.0, 1.0)


# ------------------------------------------------------------------ the menu

func _open_menu() -> void:
	menu_open = true
	race_menu.open(false)
	get_tree().paused = true
	_menu_paused = true


func _resume() -> void:
	menu_open = false
	race_menu.close()
	if _menu_paused:
		get_tree().paused = false
		_menu_paused = false
