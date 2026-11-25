extends Node2D
## Composition root: one circuit, the player car plus the nine recurring rivals,
## camera and HUD. Owns the asset resolver and wires modules together through
## explicit calls/signals. Racer id == index in cars; 0 is the player, 1..9 are
## the rivals of RivalRoster.
## Modes (chosen on the menu): a race with the player in either control mode, or
## spectating the nine rivals race back to back, at normal or fast simulation.
## Presentation (scenery, effects, audio, HUD extras) only reads race state; it
## can be switched off with presentation_enabled without changing the race.
## Combat (M3): Weapons ON / No Guns is chosen before each race; when on, every
## car follows the same WeaponRules through one deterministic CombatWorld.
## Combat style (M3.5), chosen before the race and independent of No Guns:
## Classic (M3 rules and AI) or Tactical (per-slot cooldowns).

## Esc on the grid when allow_exit is set (the title screen listens).
signal exit_requested
## Garage races: the player asked for the garage after a race (the game root opens it).
signal garage_requested
## Read-only race hooks (achievements): a race started; a race's result is final
## (every car finished, or the race was left after the player finished; cars
## still running are placed in running order). Emitted once per race.
signal race_began
signal race_concluded(order: Array)
## Championship: Fire on the results hands the round's finishing order and
## retirements (racer ids) to the game, which shows the standings.
signal championship_round_done(order: Array, dnf: Array)

enum Choice { FIRE_TO_ACCELERATE, FIRE_TO_BRAKE, SPECTATE }

const CAR_SCENE := preload("res://src/driving/car.tscn")
const MAX_OPPONENTS := 9
const BASE_TICKS := 60
## Spectator: simulated seconds the result stays up before the next race starts.
const RESTART_DELAY := 3.0
## GO! stays briefly (seconds before it fades): the start is the busiest moment.
const GO_BANNER_HOLD := 0.3
## Spectator safety net (not an original rule): only if no unfinished car has
## made any progress for this long (a genuinely stuck race) are the remaining
## cars classified in running order. Long races are never cut short.
const STUCK_RACE_TIMEOUT := 60.0
## Selectable race lengths (laps); the default is the first.
const LAP_OPTIONS: Array[int] = [3, 7, 20, 50]

@export var driving_params: DrivingParams = preload("res://src/driving/default_driving_params.tres")
@export var ai_params: AiParams = preload("res://src/ai/default_ai_params.tres")
## Computer opponents (0-9). The original field is 10 cars: the player + 9.
@export_range(0, MAX_OPPONENTS) var opponent_count := MAX_OPPONENTS
## Player's grid slot in the first race (0 = pole, -1 = back of the grid). PROVISIONAL:
## the original's first-race grid order is unverified; later races use the reversed result.
@export var player_first_grid_slot := -1
## Race variety (set by the game): the rivals' order on a first grid (a new
## race, the first spectator race, championship round 1) is shuffled from the
## race seed, the player still starting last. Off for race scenes built
## directly (tests, probes, fingerprints: rivals in id order). Couch and
## network grids keep their rotation rule.
@export var shuffle_first_grid := false
## Base seed for the rivals' decision randomness. Same seed + same race number
## = same decisions (used to compare normal and fast simulation).
@export var base_seed := 1991
## Simulation multiplier used by the spectator "fast" option.
@export_range(2, 16) var fast_multiplier := 4
## Scenery, effects and audio. Off = bare race (used to prove they change nothing).
@export var presentation_enabled := true
## The game's music player (set by the game root before _ready; null: the
## race audio makes its own).
var music: MusicPlayer = null
## Esc on the grid asks to leave (set by the title screen).
@export var allow_exit := false
@export var weapon_rules: WeaponRules = preload("res://src/combat/default_weapon_rules.tres")
## Track theme variant (1 = baseline). Visual only; set before the scene starts.
@export_range(1, 5) var track_variant := 1
var track_theme: TrackTheme
var hud_track_name := ""
## Track layout for this race scene (null = the classic circuit). The game
## sets it from the title screen's LAYOUT choice; scenes started without the
## game (tests, probes, the editor) may take the developer command line
## (DevLayouts, "--layout=<id>") unless use_command_line_layout is off.
var layout_override: TrackLayout = null
var use_command_line_layout := true
## J1: road level of each car (0 ground, 1 elevated). Always 0 on flat circuits.
var car_levels := PackedInt32Array()
## Cars near a bridge end (transition band): on both levels at once.
var car_transitions := PackedByteArray()
## J3 / J5: the layout's jumps (null on layouts without jumps).
var jumps: JumpWorld = null
var jump_rules: JumpRules = preload("res://src/race/default_jump_rules.tres")
## The Esc race menu (Resume / Leave). While it is open this computer's
## drivers give no commands; a race without network play is paused.
var race_menu: RaceMenu
var menu_open := false
var _menu_paused := false

var resolver: AssetResolver
var session: RaceSession
var racing_line: RacingLine
var cars: Array[Car] = []
## Computer drivers by racer id (null for human-driven cars).
var drivers: Array[AiDriver] = []
## Every car's controls by racer id: humans and AI supply the same commands.
var inputs: Array[DriverInput] = []
var progress: Array[RaceProgress] = []
## grid_order[slot] = racer id, for the current mode.
var grid_order: Array[int] = []
var menu_choice: Choice = Choice.FIRE_TO_ACCELERATE
## Races started so far (seeds the rivals' decisions).
var races_started := 0
var history: RaceHistory
var director := SpectatorDirector.new()
## Spectator: this race's starting grid (fixed order for the camera arrows).
var spectator_start_grid: Array[int] = []
var sim_speed := 1
var _race_grid: Array[int] = []
var _spectator_grid: Array[int] = []
var _restart_timer := -1.0
var _stuck_time := 0.0
var _best_progress := -INF
var effects: RaceEffects
var race_audio: RaceAudio
var scenery: TrackScenery
var _seen_finishers := 0
## Combat simulation for the current race (stepped only with weapons enabled).
var combat: CombatWorld
## Pre-race option: Weapons ON (true) / No Guns (false). Kept across races.
var weapons_enabled := false
## Pre-race option: Classic / Tactical combat. Kept across races.
var combat_style: WeaponRules.Style = WeaponRules.Style.CLASSIC
var combat_view: CombatView
## Race kind: "race" (normal) or "knockout" (last place out at every lap
## the leader completes; the last car standing wins). Set before _ready.
@export var race_mode := "race"
var _ko_lap := 0
## Finished, the rivals still racing (single local player): a short
## celebration, then live spectating of the rest of the race; the results come
## when everyone is in. The game turns it on (watch_enabled); the bare race
## scene keeps the earlier behaviour (results at once) for tests and tools.
const CELEBRATION_TIME := 5.0
const SKIP_SPEED := 8
var watch_enabled := false
var watching := false
var _celebrate_left := -1.0
var _watch_started := false
var _skipping := false
## Kills / deaths / tombstones and the kill feed's entries (this race).
var stats: CombatStats
## Client: combat events and retirements already turned into statistics.
var _stats_event_index := 0
var _stats_dnf := PackedByteArray()
## P2: the images each car is drawn with (index = racer id), see CarArt.look.
var _car_looks: Array[Dictionary] = []
## P2: shared wheel positions and motion (presentation only).
var wheel_layout: WheelLayout = preload("res://src/presentation/default_wheel_layout.tres")
## Chevron over the locally controlled car(s) (presentation only).
var player_marker: PlayerMarker
var jump_view: JumpView = null
## M6: vehicle condition, damage and DNF (host-authoritative; a network client
## shows the host's values). damage_enabled = false is for checks only.
var damage: DamageWorld
var damage_rules: DamageRules = preload("res://src/damage/default_damage_rules.tres")
## Pit lanes: service, limiter and speeding penalties (provisional numbers).
var pit_rules: PitRules = preload("res://src/race/default_pit_rules.tres")
## Pit lanes (null when the circuit has none): host-authoritative pit state.
var pits: PitWorld = null
## This tick's deliberate limiter overrides requested by each driver.
var _pit_requests: Dictionary = {}
## Per car: PitWorld.pack() (host) or the host's snapshot value (client), for
## the HUD and the client's own speed cap.
var pit_state := PackedInt32Array()
## Each car's velocity before the latest physics step (pit collision blame).
var _pit_vel := PackedVector2Array()
## Seconds a car that was driven into stays blameless (pushed into a wall, a
## bay or another car by the culprit).
var _pit_shoved := PackedFloat32Array()
## A car must be closing on the other at this speed (px/s) to be to blame.
const PIT_BLAME_SPEED := 40.0
var damage_enabled := true
## Weapons Hot: weapons stay locked until every car in the race has crossed the
## start line for the first time (or weapons_lock_timeout has passed, so a car
## that never leaves the grid cannot hold everyone's weapons). off = no lock.
var weapons_lock_enabled := true
var weapons_lock_timeout := 15.0
## Wreck recovery: seconds each (car, wreck) pair has been stuck together, and
## the pairs allowed to pass through each other until the wreck is back racing.
const WRECK_STUCK_TIME := 0.5
var _stuck := {}
var _passing := {}
## Per car: has crossed the start line for the first time this race.
var _crossed_start := PackedByteArray()
signal weapons_unlocked
var damage_view: DamageView = null
## Commentary and rival taunts (presentation; off with presentation_enabled).
var voice: VoiceDirector = null
## Rival taunt card when a rival destroys a local player's car (presentation).
var defeat_popup: DefeatPopup = null
## CS-style kill feed (top right).
var kill_feed: KillFeed = null
var voice_enabled := true
var voice_params: VoiceParams = preload("res://src/audio/default_voice_params.tres")
## Barrier / car contacts reported by the cars during their physics step,
## applied (in report order) at the start of the next race tick.
var _impacts: Array = []
## Humans whose DNF banner has been shown this race (presentation).
var _seen_dnf: Array[int] = []
## Lighting pilot (presentation experiment; L toggles). Off by default.
var lighting: LightingPilot
## VoxelRacing: the 3D voxel presentation of this race (null when headless).
var voxel: VoxelStage = null
## Garage race (M3.5): the player's money and weapons for this game session;
## null = quick race (standard loadout, no money). Set before the first race.
var garage: PlayerGarage
## True while the garage screen is open over the grid (grid input paused).
var garage_open := false
var _garage_settled := false
## Physics ticks to ignore grid input after the garage closes (the closing key
## must not also act on the grid panel).
var _grid_input_delay := 0
## Achievements (M3.5): persistent store set by the game root before the scene
## enters the tree; null = no tracking (tests, tools). The tracker only reads.
var achievements: AchievementStore
## Nemesis Welcome: the rival memory a finished single-player race reports to
## (set by the game root for normal races only; null = not remembered).
var rival_memory: RivalMemory = null
var achievement_tracker: AchievementTracker
var _race_open := false
## Start with the lighting pilot on (e.g. for comparison runs).
@export var lighting_on_start := false
## DYNAMIC VEHICLE LIGHTS (setting): real 2D vehicle lights at night, or the
## cheap glow-sprite fallback (presentation only).
var dynamic_vehicle_lights := true
## Settings: the player's headlight colour (LightingPilot.HEADLIGHT_PALETTE index; cosmetic).
var headlight_color := 0
## TIME: NIGHT (race setup / championship): night lighting from the start.
## Presentation only: no physics change (the biome sets the handling).
var night := false
## Championship rewards (single-player and spectating; never in couch or
## network races): the rival car the player drives (0 = the player's own car,
## n = rival n's car in its own colours) and the rivals whose cars the player has
## won - they race in the shared junker body, with their identity unchanged.
var player_car := 0
## Championship round (0-based) this race scene runs, -1 outside a championship;
## the round's starting grid (empty = the usual first grid) and its title.
var championship_round := -1
var championship_grid: Array[int] = []
var championship_label := ""
## Championship points before this round and the points per position (for
## the provisional standings while watching); empty outside a championship.
var championship_points := {}
var championship_scoring := PackedInt32Array()
var provisional_panel: ProvisionalPanel
## Racing for Keeps: what leaving costs (the race menu asks twice), "" = nothing.
var forfeit_warning := ""
var _round_reported := false
var displaced: Array[int] = []
## M4 two-player races: number of humans (1 or 2), set before the scene starts.
## With 2, Player 2 is racer 10, the field stays 10 cars (2 humans + 8 rivals,
## one rival sitting out per race in a fixed rotation), and the garage and
## achievements are off.
@export_range(1, 2) var human_count := 1
## Two-player: each player's device (joypad id, or PlayerControls.KEYBOARD).
var player_devices: Array[int] = [0, 1]
## Two-player safety net: once someone has finished, a human that makes no
## progress for this long (s) no longer holds up the results.
@export var human_stuck_timeout := 30.0
## Two-player races run so far in this session (drives the rival rotation).
var multiplayer_round := 0
var _human_stuck_time := 0.0
## Two-player split-screen on this computer (couch); off for network races.
var split_screen := true
## Network two-player race (M5.1): the session's NetRace (host or client), set
## before the scene enters the tree; null for local play.
var net: NetRace
## The human this computer shows (camera, HUD): the player, or Player 2 on a
## network client.
var local_player_id := RaceSession.PLAYER_ID
## Per-human control mode overrides (network: each computer chooses its own).
var player_control_modes := {}
## Client: the final finishing order received from the host (empty until then).
var network_results: Array[int] = []
## Network race: the other computer is gone (the race is over; back to the menu).
var network_lost := false
## Two-player split-screen views (M4 Stage 2); null in single-player.
var player_views: PlayerViews
## Two-player: the main camera looks at an empty spot far away (the views draw
## the race); positional sound is heard from between the two players.
var _park: Node2D
var _listener: AudioListener2D
var _human_best := -INF

@onready var track: Track = $Track
@onready var car: Car = $Car
@onready var camera: FollowCamera = $FollowCamera
@onready var hud: Hud = $Hud


func _ready() -> void:
	PlayerControls.ensure_actions()
	resolver = AssetResolver.new()
	track_theme = TrackTheme.load_variant(track_variant)
	driving_params = track_theme.driving(driving_params)  # the biome's handling, for every car alike
	if layout_override == null and use_command_line_layout:
		layout_override = DevLayouts.load_selected()
	if layout_override != null:
		track.layout = layout_override
	# J5: jumps work in network races too (host-authoritative, see NetRace)
	track.jumps_enabled = true
	track.build(resolver, track_theme)
	hud_track_name = "%s  -  %s" % [track_theme.display_name, DevLayouts.display_name(DevLayouts.id_of(layout_override))]
	if night:
		hud_track_name += "  -  NIGHT"
	if race_mode == "knockout":
		hud_track_name = "KNOCKOUT  -  " + hud_track_name
	if championship_label != "":
		hud_track_name = "%s  -  %s" % [championship_label, hud_track_name]
	track.checkpoint_reached.connect(_on_checkpoint_reached)
	var two := is_two_player()
	if two:
		garage = null  # garage and achievement progression are single-player only (M4)
		achievements = null
	var names := PackedStringArray(["P1" if two else "YOU"])
	for i in range(1, opponent_count + 1):
		names.append(RivalRoster.short_name(i))
	if two:
		names.append("P2")
	session = RaceSession.new(track.checkpoint_count(), track.layout.lap_count, names)
	if two:
		session.set_humans([RaceSession.PLAYER_ID, RaceSession.PLAYER_2_ID] as Array[int])
	hud.setup(resolver)
	race_menu = RaceMenu.new()
	race_menu.name = "RaceMenu"
	add_child(race_menu)
	race_menu.setup(HyperTheme.build(resolver))
	if championship_round >= 0:
		race_menu.set_leave_text("ABANDON CHAMPIONSHIP")
		race_menu.warning = forfeit_warning
	race_menu.resume_requested.connect(resume_race)
	Input.joy_connection_changed.connect(_on_joy_connection)
	race_menu.leave_requested.connect(leave_race)
	hud.follow_requested.connect(follow_driver)
	hud.follow_step_requested.connect(follow_step)
	var decals := Node2D.new()
	decals.name = "Decals"
	add_child(decals)
	move_child(decals, track.get_index() + 1)
	if presentation_enabled:
		scenery = TrackScenery.new()
		scenery.name = "Scenery"
		add_child(scenery)
		move_child(scenery, decals.get_index() + 1)
		scenery.build(track, resolver, decals)
	camera.target = car
	racing_line = RacingLine.new(track.path, track.layout.road_width, driving_params, ai_params,
		track.half_widths if not track.layout.narrow_sections.is_empty() else PackedFloat32Array(),
		track.layout, driving_params.max_speed * pit_rules.limiter_share)

	car.racer_id = RaceSession.PLAYER_ID
	_car_looks.append(_player_look())
	car.setup(driving_params, session.control_mode, _car_looks[0].body)
	cars.append(car)
	drivers.append(null)
	inputs.append(HumanDriverInput.new(RaceSession.PLAYER_ID,
		PlayerControls.ensure_player_actions(1, player_devices[0]) if two and net == null else ""))
	var rival_ids: Array[int] = []
	var car_textures := {}
	var full_names := {}
	for i in range(1, opponent_count + 1):
		var ai_car: Car = CAR_SCENE.instantiate()
		ai_car.name = "AiCar%d" % i
		ai_car.racer_id = i
		add_child(ai_car)
		move_child(ai_car, car.get_index())
		_car_looks.append(CarArt.look(resolver, _rival_car(i)))
		ai_car.setup(driving_params, CarModel.ControlMode.FIRE_TO_ACCELERATE, _car_looks[i].body)
		if _rival_car(i) == AssetCatalog.CAR_JUNKER:
			ai_car.sprite.modulate = CarArt.JUNKER_TINTS[i % CarArt.JUNKER_TINTS.size()]
		cars.append(ai_car)
		var params: AiParams = load(RivalRoster.params_path(i)) if RivalRoster.has_personality(i) else ai_params
		drivers.append(AiDriver.new(racing_line, params))
		inputs.append(AiDriverInput.new(i, drivers[-1]))
		rival_ids.append(i)
		car_textures[i] = CarArt.icon(resolver, _rival_car(i))
		full_names[i] = RivalRoster.full_name(i)
	if two:
		var car2: Car = CAR_SCENE.instantiate()
		car2.name = "Car2"
		car2.racer_id = RaceSession.PLAYER_2_ID
		add_child(car2)
		move_child(car2, car.get_index() + 1)
		_car_looks.append(CarArt.look(resolver, AssetCatalog.CAR_PLAYER_2))
		car2.setup(driving_params, session.control_mode, _car_looks[-1].body)
		cars.append(car2)
		drivers.append(null)
		if net != null and net.is_host():
			inputs.append(net.remote_input)
		elif net != null:
			inputs.append(HumanDriverInput.new(RaceSession.PLAYER_2_ID))  # the client never simulates
		else:
			inputs.append(HumanDriverInput.new(RaceSession.PLAYER_2_ID, PlayerControls.ensure_player_actions(2, player_devices[1])))
	for c in cars:
		progress.append(RaceProgress.new(track.path))
		c.wall_hit.connect(func(_n: Vector2, speed: float) -> void: _queue_impact(c.racer_id, -1, speed))
		c.car_hit.connect(func(other: Car, speed: float) -> void: _queue_impact(c.racer_id, other.racer_id, speed))
	damage = DamageWorld.new(damage_rules, cars.size())
	car_levels.resize(cars.size())
	car_transitions.resize(cars.size())
	if track.layout.has_jumps() and track.jumps_enabled:
		if track.layout.jump_rules != null:
			jump_rules = track.layout.jump_rules  # tuned for this circuit's jump
		jumps = JumpWorld.new(track.layout, jump_rules, track.path, cars.size())
	combat = CombatWorld.new(weapon_rules, cars.size(), track.path, track.layout.road_width * 0.5)
	stats = CombatStats.new(cars.size())
	if track.layout.pit_branch() >= 0:
		pits = PitWorld.new(pit_rules, cars.size(), TrackLayout.bay_count(track.layout.branches[track.layout.pit_branch()]))
		_pit_vel.resize(cars.size())
		_pit_shoved.resize(cars.size())
	if track.layout.has_elevation() or track.layout.has_jumps():
		combat.layout = track.layout
	if not track.layout.branches.is_empty():
		combat.branch_layout = track.layout  # missiles stop at dividers and the widened edges
	history = RaceHistory.new(rival_ids)
	hud.setup_history(resolver, history, car_textures, full_names)
	car_textures[RaceSession.PLAYER_ID] = _player_icon()
	full_names[RaceSession.PLAYER_ID] = "PLAYER 1" if two else "YOU"
	if two:
		car_textures[RaceSession.PLAYER_2_ID] = CarArt.icon(resolver, AssetCatalog.CAR_PLAYER_2)
		full_names[RaceSession.PLAYER_2_ID] = "PLAYER 2"
	hud.set_field(car_textures, full_names)
	hud.stats = stats
	if presentation_enabled:
		effects = RaceEffects.new()
		effects.name = "Effects"
		add_child(effects)
		effects.setup(cars, resolver, decals, track_theme.dust_color)
		race_audio = RaceAudio.new()
		race_audio.name = "RaceAudio"
		add_child(race_audio)
		race_audio.setup(cars, resolver, self)
		combat_view = CombatView.new()
		combat_view.name = "CombatView"
		add_child(combat_view)
		combat_view.setup(combat, cars, resolver, race_audio)
		combat_view.human_ids = session.human_ids
		if track.layout.has_elevation():  # J2: bridge-level effects draw above the deck
			effects.setup_levels(level_of, decals)
			combat_view.setup_levels(level_of)
		if voice_enabled:
			voice = VoiceDirector.new()
			voice.name = "VoiceDirector"
			add_child(voice)
			voice.setup(self, resolver, voice_params)
		defeat_popup = DefeatPopup.new()
		defeat_popup.name = "DefeatPopup"
		add_child(defeat_popup)
		defeat_popup.setup(self, resolver, car_textures)
		kill_feed = KillFeed.new()
		kill_feed.name = "KillFeed"
		add_child(kill_feed)
		kill_feed.setup(stats, resolver, feed_names(), feed_colors())
		damage_view = DamageView.new()
		damage_view.name = "DamageView"
		add_child(damage_view)
		damage_view.setup(damage, cars, resolver, race_audio)
		if jumps != null:
			jump_view = JumpView.new()
			jump_view.name = "JumpView"
			add_child(jump_view)
			jump_view.setup(jumps, cars, resolver, race_audio)
		player_marker = PlayerMarker.new()
		player_marker.name = "PlayerMarker"
		add_child(player_marker)
		player_marker.setup(cars)
		lighting = LightingPilot.new()
		lighting.name = "LightingPilot"
		add_child(lighting)
		lighting.setup(track, cars, combat, resolver, track_theme, dynamic_vehicle_lights,
			driving_params.max_speed)
		if track.layout.has_elevation():
			lighting.level_of = draw_level_of
		lighting.set_enabled(lighting_on_start or night)
		if track_theme.weather != "":
			var weather := WeatherView.new()
			weather.name = "Weather"
			add_child(weather)
			weather.setup(track_theme.weather, night)
		if VoxelStage.available():  # VoxelRacing: the race shown as a voxel miniature
			voxel = VoxelStage.new()
			add_child(voxel)
			voxel.setup(self)
	if achievements != null:
		achievement_tracker = AchievementTracker.new()
		achievement_tracker.name = "AchievementTracker"
		add_child(achievement_tracker)
		achievement_tracker.setup(self, achievements)
	if net != null:
		split_screen = false
		local_player_id = RaceSession.PLAYER_2_ID if net.is_client() else RaceSession.PLAYER_ID
		add_child(net)
	if two and split_screen:
		_setup_split_screen()
	_set_hud_humans()
	_race_grid = first_grid_two_players(sitting_out_rival(0)) if two else first_grid(cars.size(), player_first_grid_slot)
	if championship_grid.size() == cars.size():
		_race_grid = championship_grid.duplicate()
	_spectator_grid = rival_ids.duplicate()
	if shuffle_first_grid and not two and championship_round <= 0:
		_race_grid = shuffled_rivals(_race_grid, hash([base_seed, "grid"]))
		_spectator_grid = shuffled_rivals(_spectator_grid, hash([base_seed, "spectator grid"]))
	grid_order = _race_grid
	reset_race()
	if net != null:
		net.attach(self)


func _exit_tree() -> void:
	if _menu_paused:  # never leave the game paused behind a freed race
		get_tree().paused = false
		_menu_paused = false
	set_sim_speed(1)
	_conclude_race()
	if garage != null and garage.race_pending():
		garage.abandon_race()


## Presentation: identity colours of the humans in the standings and results
## (Player 1 gold, Player 2 blue; over the network each computer shows itself
## gold). Each HUD box-highlights its own human(s).
func _set_hud_humans() -> void:
	var colors := {}
	for k in session.human_ids.size():
		var id: int = session.human_ids[k]
		colors[id] = HyperTheme.player_color(k)
		if net != null:
			colors[id] = HyperTheme.player_color(0 if id == local_player_id else 1)
	var own: Array[int] = [local_player_id]
	if player_views != null:
		own = session.human_ids.duplicate()
		for v in player_views.views:
			v.hud.copy_field_from(hud)
			v.hud.set_humans(colors, [v.racer_id] as Array[int])
	hud.set_humans(colors, own)
	if lighting != null:  # the player's chosen headlight colour, own car(s) only
		lighting.set_own_headlights([] as Array[int] if session.spectator else own,
			LightingPilot.headlight_color(headlight_color))
	if player_marker != null:  # only the car(s) controlled on this computer
		var marked := {}
		for id in own:
			marked[id] = colors[id]
		player_marker.set_marked(marked)
	if race_audio != null:  # own car(s) always heard, rivals limited to the nearest
		race_audio.local_ids = own


func is_two_player() -> bool:
	return human_count > 1


func _setup_split_screen() -> void:
	player_views = PlayerViews.new()
	player_views.name = "PlayerViews"
	add_child(player_views)
	player_views.setup(session.human_ids, cars, get_viewport().world_2d, resolver)
	hud.layer = 4
	hud.set_info_visible(false)
	hud.set_tower_visible(false)  # each view shows its own standings at its outer edge
	hud.set_message_min_top(PlayerViews.INFO_BOTTOM)  # grid panel / results below both info panels
	hud.set_banner_low(true)
	_park = Node2D.new()
	_park.name = "CameraPark"
	_park.position = Vector2(-1000000, -1000000)
	add_child(_park)
	_listener = AudioListener2D.new()
	add_child(_listener)
	_listener.make_current()


## Two-player rotation: the rival sitting out race r (0-based), Victor first,
## then Rocco ... Nina, and round again.
static func sitting_out_rival(race_round: int) -> int:
	return race_round % RivalRoster.count() + 1


## First two-player grid: the eight racing rivals in id order, then Player 2,
## then Player 1 at the back (as the single player starts last).
static func first_grid_two_players(sitting_out: int) -> Array[int]:
	var order: Array[int] = []
	for i in range(1, RivalRoster.count() + 1):
		if i != sitting_out:
			order.append(i)
	order.append(RaceSession.PLAYER_2_ID)
	order.append(RaceSession.PLAYER_ID)
	return order


## Next two-player grid: the reversed result, with the rival whose turn it is
## to sit out replaced, in the same slot, by the rival returning from sitting
## out. Everyone else keeps their reversed-grid slot.
static func rotated_grid(reversed: Array[int], leaving: int, returning: int) -> Array[int]:
	var order := reversed.duplicate()
	var slot := order.find(leaving)
	if slot >= 0:
		order[slot] = returning
	return order


## The same grid with the rivals' slots shuffled (seeded); humans keep theirs.
static func shuffled_rivals(grid: Array[int], seed_value: int) -> Array[int]:
	var slots: Array[int] = []
	var rivals: Array[int] = []
	for k in grid.size():
		if grid[k] >= 1 and grid[k] <= 9:
			slots.append(k)
			rivals.append(grid[k])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(rivals.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := rivals[i]
		rivals[i] = rivals[j]
		rivals[j] = t
	var out := grid.duplicate()
	for k in slots.size():
		out[slots[k]] = rivals[k]
	return out


## Opponents fill the grid in id order around the player's slot.
static func first_grid(field_size: int, player_slot: int) -> Array[int]:
	var slot := field_size - 1 if player_slot < 0 else mini(player_slot, field_size - 1)
	var order: Array[int] = []
	var next_ai := 1
	for s in field_size:
		if s == slot:
			order.append(RaceSession.PLAYER_ID)
		else:
			order.append(next_ai)
			next_ai += 1
	return order


## Simulation throughput multiplier. Every physics tick still advances the race by
## exactly Car.FIXED_STEP with the same AI inputs and collision calculations; fast
## mode only runs more ticks per real second.
## Short names for the kill feed (the humans: YOU, or P1 / P2).
func feed_names() -> Dictionary:
	var names := {}
	for c in cars:
		names[c.racer_id] = RivalRoster.short_name(c.racer_id) if c.racer_id >= 1 and c.racer_id <= 9 else ""
	var two := is_two_player()
	names[RaceSession.PLAYER_ID] = "P1" if two else "YOU"
	if two:
		names[RaceSession.PLAYER_2_ID] = "P2"
	if net != null:
		names[local_player_id] = "YOU"
	return names


func feed_colors() -> Dictionary:
	var colors := {}
	for k in session.human_ids.size():
		colors[session.human_ids[k]] = HyperTheme.player_color(k)
	if net != null:
		colors[local_player_id] = HyperTheme.GOLD
	return colors


## Championship rewards apply to single-player races and spectating only.
func _rewards_apply() -> bool:
	return human_count == 1 and net == null


## The image a rival races with: its own car, or the junker once the player owns it.
func _rival_car(id: int) -> String:
	if _rewards_apply() and displaced.has(id):
		return AssetCatalog.CAR_JUNKER
	return AssetCatalog.ai_car(id)


## The player's car look: their own red car, or a won rival car as the rival raced it.
func _player_look() -> Dictionary:
	if not _rewards_apply() or player_car <= 0:
		return CarArt.look(resolver, AssetCatalog.CAR_PLAYER)
	return CarArt.look(resolver, AssetCatalog.ai_car(player_car))


func _player_icon() -> Texture2D:
	if not _rewards_apply() or player_car <= 0:
		return CarArt.icon(resolver, AssetCatalog.CAR_PLAYER)
	return CarArt.icon(resolver, AssetCatalog.ai_car(player_car))


func set_sim_speed(multiplier: int) -> void:
	sim_speed = maxi(1, multiplier)
	Engine.physics_ticks_per_second = BASE_TICKS * sim_speed
	Engine.time_scale = sim_speed
	Engine.max_physics_steps_per_frame = maxi(8, sim_speed * 2)
	if effects != null:
		effects.set_enabled(sim_speed == 1)
	if jump_view != null:
		jump_view.enabled = sim_speed == 1
	if damage_view != null:
		damage_view.enabled = sim_speed == 1
	if race_audio != null:
		race_audio.fast = sim_speed > 1
	if combat_view != null:
		combat_view.set_enabled(sim_speed == 1)


## Race length in laps (3 / 7 / 20 / 50); only before the start. Kept for every
## following race, including spectator auto-restarts.
func set_lap_count(laps: int) -> void:
	if session.state != RaceSession.State.MODE_SELECT:
		return
	session.set_lap_count(laps)
	reset_race()


func lap_count() -> int:
	return session.lap_count()


## Weapons ON / No Guns; only changeable before the start.
func set_weapons_enabled(on: bool) -> void:
	if session.state != RaceSession.State.MODE_SELECT:
		return
	weapons_enabled = on
	combat.enabled = on
	_show_menu()


## Classic / Tactical combat; only changeable before the start.
func set_combat_style(style: WeaponRules.Style) -> void:
	if session.state != RaceSession.State.MODE_SELECT:
		return
	combat_style = style
	reset_race()


func _show_menu() -> void:
	if network_lost:
		return
	hud.track_name = hud_track_name
	hud.show_menu(choice_name(menu_choice), weapons_enabled, session.lap_count(), combat_style,
		net.status_text() if net != null and net.race != null else "", laps_fixed())
	hud.show_intro(intro_lines())
	if net != null and net.is_host():
		net.send_setup()


## Knockout (one elimination per lap) and championship rounds (the schedule's
## laps) do not let the grid panel change the race length.
func laps_fixed() -> bool:
	return race_mode == "knockout" or championship_round >= 0


func reset_race() -> void:
	_conclude_race()
	if _replaying():
		voxel.replay.stop()
	_reset_debris()
	_highlights_shown = false
	_replay_hint = ""
	_race_open = false
	_human_stuck_time = 0.0
	_human_best = -INF
	if garage != null and garage.race_pending():
		garage.abandon_race()
	_garage_settled = false
	stats.reset()
	_ko_lap = 0
	_end_watch()
	_watch_started = false
	_stats_event_index = 0
	_stats_dnf.clear()
	session.reset()
	if is_two_player():
		session.set_sitting_out([sitting_out_rival(multiplayer_round)] as Array[int])
	combat.reset()
	combat.enabled = weapons_enabled
	combat.style = combat_style
	_apply_loadouts()
	_apply_upgrades()
	_reset_damage()
	_clear_wreck_passes()
	_restart_timer = -1.0
	_stuck_time = 0.0
	_best_progress = -INF
	car_levels.fill(0)  # the grid is on the ground
	car_transitions.fill(0)
	if jumps != null:
		jumps.reset()
		for c in cars:
			c.airborne = false
	for id in cars.size():
		_show_car(id, grid_order.has(id))
	for slot in grid_order.size():
		var id := grid_order[slot]
		var c := cars[id]
		c.active = false
		c.place(track.grid_transform(slot))
		progress[id].reset(c.global_position)
		session.set_progress(id, progress[id].distance)
	if session.spectator:
		_follow_last_starter()
	_update_camera_target()
	camera.snap_to_target()
	hud.history_panel.visible = session.spectator
	hud.set_banner_low(session.spectator or player_views != null)  # clear of the history panel at the top
	_seen_finishers = 0
	if effects != null:
		effects.clear_marks()
	if race_audio != null:
		race_audio.play_music("menu")
	_refresh_hud()
	_show_menu()


## Weapons each car carries this race. Classic: everyone gets the M3 loadout.
## Tactical: each rival has a personal loadout of equal value (RivalArmoury).
## The player: the garage's equipped rounds in a garage race; otherwise the
## standard loadout of the style (quick races never touch the garage).
func _apply_loadouts() -> void:
	if combat_style == WeaponRules.Style.TACTICAL:
		for id in range(1, cars.size()):
			var l := RivalArmoury.loadout(id)
			combat.set_loadout(id, l[0], l[1], l[2], l[3])
	var garage_player := garage != null and not session.spectator
	if garage_player:
		var g := garage.race_loadout()
		combat.set_loadout(RaceSession.PLAYER_ID, g[0], g[1], g[2], g[3])
		var carried := garage.race_carried()  # weapon cycling: the other owned types
		combat.set_carried(RaceSession.PLAYER_ID, CombatWorld.FRONT, carried[CombatWorld.FRONT])
		combat.set_carried(RaceSession.PLAYER_ID, CombatWorld.REAR, carried[CombatWorld.REAR])
	elif not session.spectator and combat_style == WeaponRules.Style.TACTICAL:
		var q := RivalArmoury.QUICK_RACE_PLAYER
		combat.set_loadout(RaceSession.PLAYER_ID, q[0], q[1], q[2], q[3])
	# longer races carry more rounds: everyone, except a garage player, who
	# races with the rounds they own (the garage economy is unchanged)
	var ids: Array = []
	for id in cars.size():
		if not (garage_player and id == RaceSession.PLAYER_ID):
			ids.append(id)
	combat.scale_ammo(weapon_rules.ammo_scale(session.lap_count()), ids)


## Vehicle upgrades: the garage player's car races with the garage's upgrades
## on top of the environment's handling; every other car (and a spectated
## race) with the stock handling. Rivals are never upgraded.
func _apply_upgrades() -> void:
	var me := cars[RaceSession.PLAYER_ID]
	if me.model == null:
		return
	me.model.params = garage.driving(driving_params) if garage != null and not session.spectator else driving_params


## M6: every car starts at full condition without armour, except the player's
## car in a garage race, which carries its condition and armour.
func _reset_damage() -> void:
	damage.reset()
	_impacts.clear()
	if pits != null:
		pits.reset()
		pits.service_enabled = race_mode != "knockout"  # Knockout: no pit service
		pits.pays_fines.fill(0)
		if garage != null and not session.spectator:
			pits.pays_fines[RaceSession.PLAYER_ID] = 1  # garage races: collision fines cost money
		for c in cars:
			c.model.speed_cap = INF
	if garage != null and not session.spectator:
		damage.set_start(RaceSession.PLAYER_ID, garage.race_condition() / 100.0 * damage_rules.max_condition,
			garage.armour_reduction())


## Two-player safety net: once anyone has finished, unfinished humans that make
## no progress at all for human_stuck_timeout seconds stop holding up the
## results (an active, moving player is never cut short).
func _human_safety(step: float) -> void:
	if session.state != RaceSession.State.RACING or session.finish_order.is_empty():
		return
	var furthest := -INF
	for id in session.human_ids:
		var r := session.racers[id]
		if session.is_participating(id) and not r.is_done():
			furthest = maxf(furthest, r.progress + r.tracker.laps_completed * 100000.0)
	if furthest > _human_best + 1.0:
		_human_best = furthest
		_human_stuck_time = 0.0
	else:
		_human_stuck_time += step
	if _human_stuck_time > human_stuck_timeout:
		session.end_for_humans()


# ------------------------------------------------- network two-player (M5.1)

## A human's own control mode (network: chosen on their own computer).
func set_player_control_mode(id: int, mode: CarModel.ControlMode) -> void:
	player_control_modes[id] = mode


## The other computer disconnected: everything stops and a clear message
## offers the way back to the menu. Nothing is saved (garage / achievements are
## off in network races).
func on_network_lost(text: String) -> void:
	if menu_open:
		resume_race()
	if network_lost:
		return
	network_lost = true
	for c in cars:
		c.active = false
	if race_audio != null:
		race_audio.play_music("menu")
	hud.show_notice("CONNECTION LOST", text, PlayerControls.fmt("{confirm} / {back}: back to the menu"))


## Host: the client readied up or cancelled (shown on the grid panel).
func on_network_peer_ready(_is_ready: bool) -> void:
	_show_menu()


## Client: the host's grid and settings for the next race.
func apply_network_setup(cfg: Dictionary) -> void:
	session.state = RaceSession.State.MODE_SELECT
	weapons_enabled = cfg.weapons
	combat_style = cfg.style
	multiplayer_round = cfg.round
	races_started = cfg.races
	if session.lap_count() != cfg.laps:
		session.set_lap_count(cfg.laps)
	var grid: Array[int] = []
	for id in cfg.grid:
		grid.append(id)
	_race_grid = grid
	grid_order = grid
	reset_race()


## Client: the host started the race (number `race_number`).
func on_network_start(race_number: int = races_started) -> void:
	races_started = race_number
	cars[local_player_id].model.control_mode = session.control_mode  # predicted with this player's own mode
	combat.reset()
	combat.enabled = weapons_enabled
	combat.style = combat_style
	combat.locked = weapons_enabled and weapons_lock_enabled  # until the host says otherwise
	_apply_loadouts()
	hud.hide_message()
	hud.fade_intro()
	hud.flash_banner("GO!", HyperTheme.GOLD, GO_BANNER_HOLD)
	if race_audio != null:
		race_audio.play_cue("race/start_go")
		race_audio.play_music("race")


## Client: the host's final result (reliable; overrides any older snapshot).
## dnf (per racer) and condition (per car) are the host's final values: they
## replace whatever the last snapshot that arrived said (protocol 7).
func apply_network_results(order: PackedInt32Array, times: PackedFloat64Array,
		dnf: PackedByteArray = PackedByteArray(), condition: PackedFloat32Array = PackedFloat32Array()) -> void:
	for id in mini(dnf.size(), session.racers.size()):
		session.racers[id].dnf = dnf[id] == 1
	for c in mini(condition.size(), damage.car_count()):
		damage.condition[c] = clampf(condition[c], 0.0, damage.rules.max_condition)
		damage.retired[c] = 1 if damage.condition[c] <= 0.0 else 0
	var finish: Array[int] = []
	for k in order.size():
		var r := session.racers[order[k]]
		r.finish_position = k + 1
		r.finish_time = times[k]
		finish.append(order[k])
	session.finish_order = finish
	session.state = RaceSession.State.FINISHED
	network_results = finish


## Client physics tick: no simulation, only the network side and the camera.
func _client_physics(step: float) -> void:
	if session.state == RaceSession.State.MODE_SELECT and _grid_input_delay <= 0:
		if _menu_pressed(PlayerControls.STEER_LEFT):
			set_menu_choice(posmod(menu_choice - 1, 2) as Choice)
			net.on_local_mode_changed()
		elif _menu_pressed(PlayerControls.STEER_RIGHT):
			set_menu_choice(posmod(menu_choice + 1, 2) as Choice)
			net.on_local_mode_changed()
		elif allow_exit and _menu_pressed(PlayerControls.BACK):
			exit_requested.emit()
	net.client_tick(step)
	damage.step(step)  # presentation timers only: condition comes from the host
	_client_stats()
	_update_camera_target(step)


## Client: statistics from the host's combat events and retirements; the
## host names the culprit of a collision retirement with a "retired" event
## (2026-11-22; before, such retirements showed unattributed on the client).
func _client_stats() -> void:
	if _stats_event_index > combat.events.size():
		_stats_event_index = 0
	for k in range(_stats_event_index, combat.events.size()):
		var e: Dictionary = combat.events[k]
		if e.kind == "destroyed":
			stats.on_destroyed(e.car, e.owner, e.type, session.elapsed)
		elif e.kind == "ticket":
			stats.on_ticket(e.car, session.elapsed)
			_ticket_banner(e.car, int(e.get("fine", 0)))
		elif e.kind == "retired":  # the host's culprit for a collision retirement
			_stats_dnf.resize(cars.size())
			if _stats_dnf[e.car] == 1:
				stats.attribute_retirement(e.car, e.by)  # (the DNF arrived first)
			else:
				_stats_dnf[e.car] = 1
				stats.on_contact(e.car, e.by, session.elapsed)
				stats.on_retired(e.car, session.elapsed, false)
	_stats_event_index = combat.events.size()
	_stats_dnf.resize(cars.size())
	for id in cars.size():
		if session.racers[id].dnf and _stats_dnf[id] == 0:
			_stats_dnf[id] = 1
			stats.on_retired(id, session.elapsed, true)


# ------------------------------------------------ P003: action replays

var _highlights_shown := false
## "{replay}: highlights" on the results once the race has some.
var _replay_hint := ""


func _replaying() -> bool:
	return voxel != null and voxel.replay != null and voxel.replay.playing


func _highlights_allowed() -> bool:
	return voxel != null and voxel.replay != null and net == null and not is_two_player() and player_views == null


## Once everyone is in, the race's best moments play (once); true while a
## replay runs. The live race is only watched, never changed, by the replay.
func _highlights_tick() -> bool:
	if _replaying():
		return true
	if not _highlights_allowed() or session.state != RaceSession.State.FINISHED or not session.all_finished():
		return false
	if not _highlights_shown:
		_highlights_shown = true
		if voxel.replay.has_highlights():
			_replay_hint = "     {replay}: highlights"
		if voxel.replay.play_highlights():
			return true
	return false


## Reports the race result once it is final (see race_concluded). Only a race
## that reached the flag counts; one left while racing is not reported.
func _conclude_race() -> void:
	if not _race_open or session.state != RaceSession.State.FINISHED:
		return
	_race_open = false
	var order: Array = []
	for r in session.standings():
		order.append(r.id)
	race_concluded.emit(order)
	_remember_race()
	if net != null:
		net.send_results(order)


## The race's memorable moments for the Nemesis Welcome, from its own results
## only: DNFs a rival caused the player (or the player a rival), with the
## weapon and lap, and a first-second finish closer than RivalMemory.CLOSE_GAP.
func _remember_race() -> void:
	if rival_memory == null or session.spectator or is_two_player() or net != null:
		return
	var finish: Array = []
	var laps_at_out := {}
	for r in session.standings():
		finish.append([r.id, r.finish_time, r.is_finished(), r.dnf])
		if r.dnf:
			laps_at_out[r.id] = r.tracker.laps_completed
	var mode := "championship" if championship_round >= 0 else ("garage" if garage != null else "quick")
	var context := {"circuit": track.layout.display_name, "laps": session.lap_count(), "mode": mode}
	rival_memory.record_race(stats.feed, finish, laps_at_out, RaceSession.PLAYER_ID, context)
	rival_memory.save()


## Championship: the round's finishing order (retired cars last, as classified)
## and the retirements, reported once.
func _report_round() -> void:
	_round_reported = true
	_conclude_race()
	var order: Array = []
	var dnf: Array = []
	for r in session.standings():
		order.append(r.id)
		if r.dnf:
			dnf.append(r.id)
	championship_round_done.emit(order, dnf)


## Garage race: once the player has finished, pays the prize and keeps the
## rounds left (exactly once per race; the garage also guards against repeats).
func _settle_garage() -> void:
	if garage == null or session.spectator or _garage_settled or session.state != RaceSession.State.FINISHED:
		return
	_garage_settled = true
	var me := session.racers[RaceSession.PLAYER_ID]
	garage.settle_race(0 if me.dnf else me.finish_position,
		combat.ammo[RaceSession.PLAYER_ID][CombatWorld.FRONT], combat.ammo[RaceSession.PLAYER_ID][CombatWorld.REAR],
		damage.fraction(RaceSession.PLAYER_ID) * 100.0, session.lap_count(),
		pits.fines[RaceSession.PLAYER_ID] if pits != null else 0, combat.rounds_by_type(RaceSession.PLAYER_ID))


## Opens the garage between races (garage races only).
func open_garage() -> void:
	if garage == null or session.state != RaceSession.State.MODE_SELECT:
		return
	garage_open = true
	hud.hide_message()
	garage_requested.emit()


## Garage closed: the new purchases / equipment are loaded, then the race
## starts (start) or the grid panel is shown.
func close_garage(start: bool) -> void:
	garage_open = false
	_grid_input_delay = 3
	if session.state != RaceSession.State.MODE_SELECT:
		return
	reset_race()
	if start:
		start_race()


static func choice_name(choice: Choice) -> String:
	match choice:
		Choice.FIRE_TO_BRAKE: return "FIRE TO BRAKE"
		Choice.SPECTATE: return "SPECTATE RIVALS"
	return "FIRE TO ACCELERATE"


func set_menu_choice(choice: Choice) -> void:
	if session.state != RaceSession.State.MODE_SELECT or (is_two_player() and choice == Choice.SPECTATE):
		return
	menu_choice = choice
	var spectate := choice == Choice.SPECTATE
	if not spectate:
		session.control_mode = CarModel.ControlMode.FIRE_TO_BRAKE if choice == Choice.FIRE_TO_BRAKE else CarModel.ControlMode.FIRE_TO_ACCELERATE
	if spectate != session.spectator:
		session.set_spectator(spectate)
		grid_order = _spectator_grid if spectate else _race_grid
		reset_race()
	_show_menu()


func _physics_process(_delta: float) -> void:
	var step := Car.FIXED_STEP
	if network_lost:
		if _menu_pressed(PlayerControls.CONFIRM) or _menu_pressed(PlayerControls.BACK):
			exit_requested.emit()
		return
	if net != null and net.is_client():
		_client_physics(step)
		return
	_settle_garage()
	_watch_tick(step)
	match session.state:
		RaceSession.State.MODE_SELECT:
			if garage_open:
				return
			if _grid_input_delay > 0:
				_grid_input_delay -= 1
				return
			var choices := 2 if is_two_player() else 3  # no spectating in two-player races
			if _menu_pressed(PlayerControls.STEER_LEFT):
				set_menu_choice(posmod(menu_choice - 1, choices) as Choice)
			elif _menu_pressed(PlayerControls.STEER_RIGHT):
				set_menu_choice(posmod(menu_choice + 1, choices) as Choice)
			elif _menu_pressed(PlayerControls.FIRE_FRONT) or _menu_pressed(PlayerControls.FIRE_REAR):
				set_weapons_enabled(not weapons_enabled)
			elif _menu_pressed(PlayerControls.TOGGLE_STYLE):
				set_combat_style(WeaponRules.Style.TACTICAL if combat_style == WeaponRules.Style.CLASSIC else WeaponRules.Style.CLASSIC)
			elif _menu_pressed(PlayerControls.HISTORY_VIEW) and not laps_fixed():
				var i := LAP_OPTIONS.find(session.lap_count())
				set_lap_count(LAP_OPTIONS[(i + 1) % LAP_OPTIONS.size()])
			elif _menu_pressed(PlayerControls.FIRE):
				if net == null or net.can_start():
					start_race()
			elif allow_exit and _menu_pressed(PlayerControls.BACK):
				exit_requested.emit()
			return
		RaceSession.State.FINISHED:
			if _highlights_tick():
				pass  # the action replay first; the results wait for it
			elif _watch_active():
				_watch_input()  # the rest of the race goes on below
			elif not session.spectator:
				if watching or _celebrate_left >= 0.0:
					_end_watch()  # everyone is in: the results
				if _menu_pressed(PlayerControls.REPLAY) and _highlights_allowed() and voxel.replay.play_highlights(true):
					return  # watch the highlights again
				var skip_garage := garage != null and _menu_pressed(PlayerControls.HISTORY_VIEW)
				if championship_round >= 0:
					if _menu_pressed(PlayerControls.CONFIRM) and not _round_reported:
						_report_round()
					return
				if _menu_pressed(PlayerControls.CONFIRM) or skip_garage:
					if is_two_player():
						var leaving := sitting_out_rival(multiplayer_round + 1)
						var returning := sitting_out_rival(multiplayer_round)
						multiplayer_round += 1
						_race_grid = rotated_grid(session.reversed_grid(), leaving, returning)
						grid_order = _race_grid
						reset_race()
						return
					_race_grid = session.reversed_grid()
					grid_order = _race_grid
					reset_race()
					if skip_garage:
						start_race()
					elif garage != null:
						open_garage()
					return
	if session.spectator and not _replaying() and _spectator_input():
		return
	_apply_impacts(step)
	_update_progress()
	_update_levels()
	_update_jumps(Car.FIXED_STEP)
	_debris_tick(step)
	_drive_cars(step)
	_update_pits(step)
	if combat.enabled:
		_combat_tick(step)
		_update_wreck_passes(step)
	session.tick(step)
	if race_mode == "knockout":
		_knockout_tick()
	if is_two_player():
		_human_safety(step)
	_settle_garage()
	if session.state == RaceSession.State.FINISHED and session.all_finished():
		_conclude_race()
	if session.spectator:
		_spectator_tick(step)
	_update_camera_target(step)
	if net != null:
		net.host_after_tick()


## Grid panel and results controls: the default actions, and in two-player
## races each player's own controller as well.
func _menu_pressed(action: String) -> bool:
	if Input.is_action_just_pressed(action):
		return true
	if is_two_player():
		for n in [1, 2]:
			var a := PlayerControls.player_prefix(n) + action
			if InputMap.has_action(a) and Input.is_action_just_pressed(a):
				return true
	return false


func start_race() -> void:
	if session.state != RaceSession.State.MODE_SELECT:
		return
	races_started += 1
	# Weapons Hot: locked for everyone until the whole field is through the start line
	combat.locked = combat.enabled and weapons_lock_enabled
	_crossed_start.resize(cars.size())
	_crossed_start.fill(0)
	for id in session.human_ids:
		if id < cars.size():
			cars[id].model.control_mode = player_control_modes.get(id, session.control_mode)
	for id in grid_order:
		cars[id].active = true
		inputs[id].begin_race(race_seed(races_started, id))
	session.start()
	if session.spectator:
		_follow_last_starter()
	_race_open = true
	race_began.emit()
	if net != null:
		net.on_race_started()
	if garage != null and not session.spectator:
		garage.begin_race()
	hud.hide_message()
	hud.fade_intro()
	hud.flash_banner("GO!", HyperTheme.GOLD, GO_BANNER_HOLD)
	if race_audio != null:
		race_audio.play_cue("race/start_go")
		race_audio.play_music("race")


## Seed of a rival's decisions in a given race (stable across sessions).
func race_seed(race_number: int, racer_id: int) -> int:
	return hash([base_seed, race_number, racer_id])


func _spectator_input() -> bool:
	if Input.is_action_just_pressed(PlayerControls.SIM_SPEED):
		set_sim_speed(1 if sim_speed > 1 else fast_multiplier)
	if Input.is_action_just_pressed(PlayerControls.HISTORY_VIEW):
		hud.history_panel.toggle_view()
	if Input.is_action_just_pressed(PlayerControls.TOGGLE_PANEL):
		hud.history_panel.visible = not hud.history_panel.visible
	if Input.is_action_just_pressed(PlayerControls.STEER_LEFT):
		hud.history_panel.scroll_columns(-3)
	if Input.is_action_just_pressed(PlayerControls.STEER_RIGHT):
		hud.history_panel.scroll_columns(3)
	return false


## Records each finished race, shows the result briefly, then starts the next
## race from the reversed grid.
func _spectator_tick(step: float) -> void:
	if session.state == RaceSession.State.RACING:
		var furthest := -INF
		for r in session.participants():
			if not r.is_done():
				furthest = maxf(furthest, r.progress + r.tracker.laps_completed * 100000.0)
		if furthest > _best_progress + 1.0:
			_best_progress = furthest
			_stuck_time = 0.0
		else:
			_stuck_time += step
		if _stuck_time > STUCK_RACE_TIMEOUT:
			session.classify_remaining()
	if session.state == RaceSession.State.FINISHED:
		if _highlights_tick():
			return  # the next race waits for the action replay
		if _restart_timer < 0.0:
			history.add_race(session.finish_order, weapons_enabled, session.lap_count())
			hud.history_panel.refresh()
			_restart_timer = RESTART_DELAY
			hud.show_results(session.standings(), "Next race starting...")
		_restart_timer -= step
		if _restart_timer <= 0.0:
			_spectator_grid = session.reversed_grid()
			grid_order = _spectator_grid
			reset_race()
			start_race()


## Cars not in this race (the player when spectating, a rival sitting out) are
## hidden, without collision, and parked far away.
func _show_car(id: int, on: bool) -> void:
	var c := cars[id]
	c.visible = on
	_apply_car_collision(id, on)
	if not on:
		c.active = false
		c.place(Transform2D(0.0, Vector2(-100000, -100000)))


## Collision layers for a car's presence and road level. Only touches the
## physics body when they change: re-assigning the same collision layers
## re-registers the body and changes contact order.
func _apply_car_collision(id: int, present: bool) -> void:
	var c := cars[id]
	var want := Track.car_collision(car_levels[id], car_transitions[id] == 1, c.airborne) \
		if present and not damage.is_retired(id) else Vector2i.ZERO
	if jumps != null and jumps.is_down_in_flyover(id):
		want = Vector2i.ZERO  # down in a flyover's ravine, under the road crossing it
	if c.collision_layer != want.x or c.collision_mask != want.y:
		c.collision_layer = want.x
		c.collision_mask = want.y


## J1: each car's road level from its progress along its own branch; a car
## changes level (and collision layers) only at the ends of an elevation zone,
## which the layout keeps clear of the other road. Flat circuits: nothing.
func _update_levels() -> void:
	if not track.layout.has_elevation():
		return
	for id in grid_order:
		var level := track.level_at_distance(progress[id].distance)
		var band := 1 if track.in_transition(progress[id].distance) else 0
		if level != car_levels[id] or band != car_transitions[id]:
			car_levels[id] = level
			car_transitions[id] = band
			_apply_car_collision(id, true)


## J3: takeoff over a ramp lip, flight, landing, and falling into the gap
## (the car stops; after the recovery time it is set back on the road just past
## the gap). Deterministic: arc distance and speed along the road each tick.
func _update_jumps(step: float) -> void:
	if jumps == null:
		return
	for id in grid_order:
		var c := cars[id]
		var s: float = progress[id].distance
		var along := c.model.velocity.dot(track.path.tangent_at(s))
		match jumps.step(id, step, s, along, c.active):
			"takeoff":
				c.airborne = true
				_apply_car_collision(id, true)
			"landed":
				c.airborne = false
				_apply_car_collision(id, true)
			"fell":
				c.airborne = false
				c.active = false
				c.model.velocity = Vector2.ZERO
				_apply_car_collision(id, true)
				inputs[id].on_destroyed()
				if _takes_damage(id) and damage.damage(id, damage_rules.jump_fall_damage):
					_retire(id)
			"recovered":
				var back := jumps.recovery_distance(jumps.jump_of[id])
				c.place(Transform2D(track.path.tangent_at(back).angle(), track.path.point_at(back)))
				progress[id].update(c.global_position)
				session.set_progress(id, progress[id].distance)
				jumps.place(id, fposmod(progress[id].distance, track.path.length))
				jumps.jump_of[id] = -1
				_apply_car_collision(id, true)
				if session.state == RaceSession.State.RACING and not combat.is_wrecked(id) and not damage.is_retired(id):
					c.active = true
		if jumps.is_down(id):
			c.active = false  # stays down in the gap (also after a weapon respawn)


## A car's road level as this computer knows it (a network client reads the
## host's progress from the snapshots).
func level_of(id: int) -> int:
	if not track.layout.has_elevation():
		return 0
	if net != null and net.is_client():
		return track.level_at_distance(session.racers[id].progress)
	return car_levels[id]


## The level a car is drawn on: the bridge level while on it and also near
## either bridge end, so a car straddling the deck's edge is drawn whole above
## it (never half under it).
func draw_level_of(id: int) -> int:
	if not track.layout.has_elevation():
		return 0
	var s: float = session.racers[id].progress if net != null and net.is_client() else progress[id].distance
	return 1 if level_of(id) == 1 or track.in_transition(s) else 0


## J2: cars on the bridge draw above the deck, cars below it underneath
## (presentation only; flat circuits: nothing).
func _present_levels() -> void:
	if not track.layout.has_elevation() and jumps == null:
		return
	for i in cars.size():
		var z := Track.UPPER_Z_OFFSET * draw_level_of(i)
		if cars[i].airborne:
			z = maxi(z, Track.UPPER_Z_OFFSET)  # flying: drawn over the cars on the road
		elif jumps != null and jumps.is_down_in_flyover(i):
			z = 0  # down in a flyover's ravine
		if cars[i].z_index != z:
			cars[i].z_index = z


## Esc (any player's Back) during a race opens the race menu.
func _check_race_menu() -> void:
	var racing := session.state == RaceSession.State.RACING or (session.spectator and session.state == RaceSession.State.FINISHED)
	if menu_open or network_lost or not racing or _replaying():
		return
	if _menu_pressed(PlayerControls.BACK):
		open_race_menu()


## Opens the Esc menu. Single-player, spectator and couch races pause; a
## network race goes on for the other player (this computer's car brakes).
func open_race_menu() -> void:
	if menu_open:
		return
	menu_open = true
	_menu_paused = net == null
	if _menu_paused:
		get_tree().paused = true
	race_menu.set_context(_race_identity())
	race_menu.open(net != null)


## A controller unplugged during a local race pauses it (couch: only a
## player's own pad; single player: when no controller is left), so nobody
## crashes while reaching for the cable. Plugging it back in and resuming is
## enough: pad bindings follow the device id.
func _on_joy_connection(device: int, connected: bool) -> void:
	if connected or net != null or session.spectator or session.state != RaceSession.State.RACING:
		return
	var who := ""
	if is_two_player():
		var k := player_devices.find(device)
		if k < 0:
			return
		who = "PLAYER %d: " % (k + 1)
	elif not Input.get_connected_joypads().is_empty():
		return
	open_race_menu()
	race_menu.set_note(who + "CONTROLLER DISCONNECTED  -  reconnect it, then resume", true)


## Back to the same race, exactly where it was.
func resume_race() -> void:
	if not menu_open:
		return
	menu_open = false
	race_menu.close()
	if _menu_paused:
		get_tree().paused = false
		_menu_paused = false


## Leaves the race for the main menu (a network race disconnects; an unfinished
## garage race pays nothing and uses no rounds: see _exit_tree).
func leave_race() -> void:
	resume_race()
	set_sim_speed(1)
	exit_requested.emit()


## Spectator camera: every race starts on the car in the last grid slot.
func _follow_last_starter() -> void:
	spectator_start_grid = grid_order.duplicate()
	if not spectator_start_grid.is_empty():
		director.follow(spectator_start_grid[-1])


## Spectator: follow this driver (clicked in the standings). Presentation only.
func follow_driver(id: int) -> void:
	if (session.spectator or watching) and session.is_participating(id) and grid_order.has(id):
		director.follow(id)


## Spectator: previous (-1) / next (+1) driver in this race's starting-grid order
## (watching after the finish: the next car still racing).
func follow_step(direction: int) -> void:
	if session.spectator:
		follow_driver(SpectatorDirector.grid_neighbour(spectator_start_grid, director.target_id, direction))
	elif watching:
		var id := director.target_id
		for k in grid_order.size():
			id = SpectatorDirector.grid_neighbour(grid_order, id, direction)
			if id >= 0 and not session.racers[id].is_done() and not session.human_ids.has(id):
				follow_driver(id)
				return


# ------------------------------------------------- finished: watch the rest

func _watch_applies() -> bool:
	return watch_enabled and not session.spectator and human_count == 1 and net == null


## The local player is done (finished or out) and rivals are still racing
## (also in the frame before the watch has started).
func _watch_active() -> bool:
	return (_watch_started or (_watch_applies() and session.state == RaceSession.State.FINISHED)) \
		and not session.all_finished()


## Celebration countdown, live spectating, the end of the watch; a stuck
## field is classified as in spectator races (never invented positions).
func _watch_tick(step: float) -> void:
	if not _watch_applies() or session.state != RaceSession.State.FINISHED:
		return
	if not _watch_started:
		if session.all_finished():
			return  # everyone in already: straight to the results
		_watch_started = true
		_celebrate_left = CELEBRATION_TIME
		_best_progress = -INF
		_stuck_time = 0.0
		var me := session.racers[local_player_id]
		if me.dnf:
			hud.show_caption(out_caption(), "RACE CONTINUES - WATCH YOUR RIVALS!", HyperTheme.RED)
		else:
			hud.show_caption("%s PLACE - YOU FINISHED!" % Hud.ordinal(me.finish_position).to_upper(),
				"RACE CONTINUES - WATCH YOUR RIVALS!")
		hud.set_watch_hint(PlayerControls.fmt("{confirm}: watch now      {history_view}: skip to the results"))
		hud.hide_message()  # nothing of the results before everyone is in
		hud.set_results_up(false)
	if session.all_finished():
		_end_watch()
		return
	if _celebrate_left > 0.0:
		_celebrate_left -= step / maxf(1.0, sim_speed)  # real seconds, also when skipping
		if _celebrate_left <= 0.0:
			_begin_watching()
	# the same stuck net as spectator races: a field with no progress for a minute is classified
	var furthest := -INF
	for r in session.participants():
		if not r.is_done():
			furthest = maxf(furthest, r.progress + r.tracker.laps_completed * 100000.0)
	if furthest > _best_progress + 1.0:
		_best_progress = furthest
		_stuck_time = 0.0
	else:
		_stuck_time += step
	if _stuck_time > STUCK_RACE_TIMEOUT:
		session.classify_remaining()


## The caption when the local player is out.
func out_caption() -> String:
	if race_mode == "knockout" and session.racers[local_player_id].knockout_lap > 0:
		return "ELIMINATED AFTER LAP %d!" % session.racers[local_player_id].knockout_lap
	return "OUT - DNF!"


# ------------------------------------------------------------------ Knockout

## Racers still in a Knockout race (not finished, eliminated or retired).
func knockout_remaining() -> Array[int]:
	var out: Array[int] = []
	for r in session.standings():
		if not r.is_done():
			out.append(r.id)
	return out


## Each time the leader completes a lap, the last-placed racer still in is
## eliminated (live standings: laps and checkpoints); combat retirements just
## leave earlier. The last one standing wins at once.
func _knockout_tick() -> void:
	if session.state == RaceSession.State.MODE_SELECT:
		return
	var leader_laps := 0
	for r in session.participants():
		leader_laps = maxi(leader_laps, r.tracker.laps_completed)
	while _ko_lap < leader_laps:
		_ko_lap += 1
		var left := knockout_remaining()
		if left.size() >= 2:
			var out: int = left[-1]
			session.racers[out].knockout_lap = _ko_lap
			_retire(out, false, true)
			if hud != null and (not session.human_ids.has(out) or not _watch_applies()):
				hud.flash_banner("%s OUT!" % ("YOU ARE" if session.human_ids.has(out) and not is_two_player()
					else session.racers[out].display_name.to_upper()), HyperTheme.RED, 1.2)
	var left := knockout_remaining()
	if left.size() == 1 and not session.all_finished():
		session.finish_now(left[0])


## The Knockout line on the HUD ("" outside Knockout).
func knockout_text() -> String:
	if race_mode != "knockout" or session.state == RaceSession.State.MODE_SELECT:
		return ""
	var left := knockout_remaining().size()
	if session.all_finished() or left <= 1:
		return "KNOCKOUT  -  WINNER: %s" % (session.standings()[0].display_name.to_upper())
	var text := "KNOCKOUT  -  %d LEFT  -  LAST PLACE OUT AT THE END OF LAP %d" % [left, _ko_lap + 1]
	if knockout_danger() >= 0 and session.human_ids.has(knockout_danger()) and not session.spectator:
		text += "  -  %s IN THE DROP ZONE!" % ("YOU ARE" if not is_two_player() else session.racers[knockout_danger()].display_name.to_upper() + " IS")
	return text


## Knockout: who would be eliminated if the leader completed the lap now
## (the last of the racers still in), -1 outside Knockout or when decided.
func knockout_danger() -> int:
	if race_mode != "knockout" or session.state != RaceSession.State.RACING:
		return -1
	var left := knockout_remaining()
	return left[-1] if left.size() >= 2 else -1


## The provisional championship standings, while watching a championship round.
func _refresh_watch_panel() -> void:
	# while watching, and with the final results (the standings after this round)
	var show := championship_round >= 0 and not championship_scoring.is_empty() \
		and (watching or (session.state == RaceSession.State.FINISHED and session.all_finished() and not session.spectator))
	if not show:
		if provisional_panel != null:
			provisional_panel.visible = false
		return
	if provisional_panel == null:
		provisional_panel = ProvisionalPanel.new()
		provisional_panel.setup(HyperTheme.build(resolver))
		hud.add_child(provisional_panel)
	provisional_panel.refresh(championship_points, championship_scoring, session.standings(), feed_names(), local_player_id)
	provisional_panel.visible = true
	provisional_panel.reset_size()
	provisional_panel.position = Vector2(1280.0 - provisional_panel.get_combined_minimum_size().x - 14.0, 230.0)


func _watch_input() -> void:
	if _menu_pressed(PlayerControls.HISTORY_VIEW) and not _skipping:
		_skipping = true  # fast-forward the real race (nothing is invented)
		if not watching:
			_begin_watching()
		set_sim_speed(SKIP_SPEED)
		hud.set_watch_hint("Skipping to the results...")
		return
	if not watching:
		if _menu_pressed(PlayerControls.CONFIRM):
			_begin_watching()
		return
	if _menu_pressed(PlayerControls.STEER_LEFT):
		follow_step(-1)
	elif _menu_pressed(PlayerControls.STEER_RIGHT):
		follow_step(1)


func _begin_watching() -> void:
	if watching:
		return
	watching = true
	_celebrate_left = 0.0
	director.locked = false
	hud.hide_caption()
	if not _skipping:
		hud.set_watch_hint(PlayerControls.fmt("WATCHING THE RACE      {steer_left} / {steer_right}: switch car      {history_view}: skip to the results"))
	_update_camera_target()


func _end_watch() -> void:
	if _skipping:
		set_sim_speed(1)
	_skipping = false
	watching = false
	_celebrate_left = -1.0
	if hud != null:
		hud.hide_caption()
		hud.set_watch_hint("")
	director.locked = false


func _update_camera_target(step: float = 0.0) -> void:
	if player_views != null:
		camera.target = _park
		camera.position_smoothing_enabled = false
		return
	if not session.spectator and not watching:
		camera.target = cars[local_player_id]
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2.ONE
		return
	var view: Array = []
	for r in session.participants():
		view.append({"id": r.id, "progress": r.progress, "finished": r.is_done() if watching else r.is_finished()})
	if watching and director.locked and director.target_id >= 0 and session.racers[director.target_id].is_done():
		director.locked = false  # the followed car is in (or out): back to the closest battle
	var id := director.update(view, step)
	if id > 0:
		camera.target = cars[id]
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 4.0
	camera.zoom = Vector2(0.85, 0.85)


func _process(_delta: float) -> void:
	if net != null and net.race != null:
		hud.set_net_quality("" if network_lost else net.quality_text(), net.connection_bad())
	if lighting != null and Input.is_action_just_pressed(PlayerControls.TOGGLE_LIGHTING):
		lighting.set_enabled(not lighting.enabled)
	_check_race_menu()
	# the finish banner first, so results shown in the same frame wait for it
	_present_retirements()
	_present_finishers()
	_present_levels()
	_refresh_hud()
	if _listener != null:
		var mid := Vector2.ZERO
		for id in session.human_ids:
			mid += cars[id].global_position
		_listener.global_position = mid / session.human_ids.size()


## Finish celebrations (presentation only): the player's finish in a race, the
## winner's finish when spectating.
func _present_finishers() -> void:
	var count := session.finish_order.size()
	if count <= _seen_finishers:
		_seen_finishers = mini(_seen_finishers, count)
		return
	for k in range(_seen_finishers, count):
		var id: int = session.finish_order[k]
		if session.racers[id].dnf:
			continue  # classified at the end, not a finish
		var human := session.human_ids.has(id) and not session.spectator
		var celebrate := human or (session.spectator and k == 0)
		if human and _watch_applies() and not session.all_finished():
			celebrate = false  # the finish caption says it (and that the race goes on)
			if effects != null:
				effects.celebrate(track.checkpoint_transform(0).origin)
			if race_audio != null:
				race_audio.play_cue("race/finish")
		if celebrate:
			var text := "FINISH!"
			if session.spectator:
				text = "%s WINS!" % RivalRoster.short_name(id).to_upper()
			elif is_two_player():
				text = "%s FINISHED!" % session.racers[id].display_name
			hud.flash_banner(text)
			if effects != null:
				effects.celebrate(track.checkpoint_transform(0).origin)
			if race_audio != null:
				race_audio.play_cue("race/finish")
	_seen_finishers = count


## M6: a human out of the race gets a red banner (the results wait for it,
## as for FINISH!). Also on a network client, from the host's DNF.
func _present_retirements() -> void:
	if session.state == RaceSession.State.MODE_SELECT:
		_seen_dnf.clear()
		return
	if session.spectator:
		return
	for id in session.human_ids:
		if session.racers[id].dnf and not _seen_dnf.has(id):
			_seen_dnf.append(id)
			if _watch_applies() and not session.all_finished():
				continue  # the out caption says it
			hud.flash_banner("%s OUT!" % session.racers[id].display_name if is_two_player() else "OUT - DNF!", HyperTheme.RED)


## The service bay frames: gold when free, red while a car holds the bay.
func _refresh_bays() -> void:
	if track == null or track.bay_frames.is_empty():
		return
	var held := PackedByteArray()
	held.resize(track.bay_frames.size())
	for st in pit_state:
		var k := PitWorld.packed_bay(st)
		if k >= 0 and k < held.size():
			held[k] = 1
	for k in track.bay_frames.size():
		track.bay_frames[k].default_color = BAY_TAKEN if held[k] == 1 else Track.PIT_MARK


const BAY_TAKEN := Color(0.9, 0.25, 0.2)


func _refresh_hud() -> void:
	_refresh_bays()
	if network_lost:
		return
	hud.set_follow(session.spectator or watching, director.target_id)
	hud.danger_id = knockout_danger()
	hud.set_mode_line(knockout_text())
	hud.set_mode_line_alert(hud.danger_id >= 0 and session.human_ids.has(hud.danger_id) and not session.spectator)
	hud.update_tower(session.standings())
	if session.spectator:
		var leader := session.standings()[0] if session.racer_count() > 0 else null
		var following := RivalRoster.short_name(director.target_id) if director.target_id > 0 else "-"
		hud.update_spectator(history.race_count() + (0 if session.state == RaceSession.State.FINISHED else 1),
			leader.tracker.current_lap() if leader != null else 1, session.racers[0].tracker.lap_count,
			session.elapsed, "x%d" % sim_speed, following, weapons_enabled)
		hud.update_combat(false, 0, 0, 0, 0, 0.0)
		_refresh_condition(hud, director.target_id, director.target_id > 0, false)
		return
	if player_views != null:
		var standings := session.standings()
		for v in player_views.views:
			v.hud.set_results_up(session.state == RaceSession.State.FINISHED)
			_refresh_player_hud(v.hud, v.racer_id)
			v.hud.danger_id = hud.danger_id
			v.hud.update_tower(standings)
		if session.state == RaceSession.State.FINISHED:
			hud.show_results(session.standings())
		return
	var me := local_player_id
	var p := session.racers[me]
	var time := p.end_time() if p.is_done() else session.elapsed
	hud.update_race(p.tracker.current_lap(), p.tracker.lap_count, time,
		session.position_of(me), session.racer_count())
	hud.update_combat(weapons_enabled, combat.weapon_of(me, CombatWorld.FRONT), combat.ammo[me][CombatWorld.FRONT],
		combat.weapon_of(me, CombatWorld.REAR), combat.ammo[me][CombatWorld.REAR], combat.wreck_left[me],
		_cooldown_fraction(CombatWorld.FRONT, me), _cooldown_fraction(CombatWorld.REAR, me),
		combat.slot_types(me, CombatWorld.FRONT), combat.slot_types(me, CombatWorld.REAR))
	_refresh_condition(hud, me)
	_refresh_pit(hud, me)
	hud.set_weapons_locked(combat.enabled and combat.locked and session.state != RaceSession.State.FINISHED)
	_refresh_watch_panel()
	if session.state == RaceSession.State.FINISHED and not _watch_active():
		if _replaying():
			return
		if net != null:
			hud.show_results(session.standings(), "{confirm}: next race" if net.is_host() else "Waiting for the host to continue")
		elif championship_round >= 0 and garage != null and _garage_settled:  # a career round
			hud.show_results(session.standings(), ("Prize money: $%d" % garage.last_prize) + ("  -  pit collision fines $%d" % garage.last_fine if garage.last_fine > 0 else "")
				+ "     {confirm}: championship standings" + _replay_hint)
		elif championship_round >= 0:
			hud.show_results(session.standings(), "{confirm}: championship standings" + _replay_hint)
		elif garage != null and _garage_settled:
			hud.show_results(session.standings(), ("Prize money: $%d" % garage.last_prize) + ("  -  pit collision fines $%d" % garage.last_fine if garage.last_fine > 0 else "")
				+ "     {confirm}: garage     {history_view}: skip shopping, next race" + _replay_hint)
		else:
			hud.show_results(session.standings(), "{confirm}: race again (reversed grid)" + _replay_hint)


## One human's HUD: their own position, lap, time, weapons and cooldowns.
func _refresh_player_hud(view_hud: Hud, id: int) -> void:
	var r := session.racers[id]
	view_hud.update_race(r.tracker.current_lap(), r.tracker.lap_count, r.end_time() if r.is_done() else session.elapsed,
		session.position_of(id), session.racer_count())
	view_hud.update_combat(weapons_enabled, combat.weapon_of(id, CombatWorld.FRONT), combat.ammo[id][CombatWorld.FRONT],
		combat.weapon_of(id, CombatWorld.REAR), combat.ammo[id][CombatWorld.REAR], combat.wreck_left[id],
		_cooldown_fraction(CombatWorld.FRONT, id), _cooldown_fraction(CombatWorld.REAR, id),
		combat.slot_types(id, CombatWorld.FRONT), combat.slot_types(id, CombatWorld.REAR))
	_refresh_condition(view_hud, id)
	_refresh_pit(view_hud, id)
	view_hud.set_weapons_locked(combat.enabled and combat.locked and session.state != RaceSession.State.FINISHED)


## Pit collision tickets from last tick's contacts: a meaningful impact (above
## the damage model's own thresholds) by a car in the pit lane: into a
## barrier, a divider, a bay or another car. With two cars, the one that drove
## into the other is to blame (a stopped car never is). One ticket per
## incident (PitWorld.collision); contacts on the racing road never count.
func _pit_collisions() -> void:
	if pits == null or session.state != RaceSession.State.RACING:
		return
	var culprits: Array[int] = []
	for imp in _impacts:  # car contacts first: whoever was driven into is blameless for what follows
		if imp[1] >= 0 and imp[2] >= damage_rules.car_threshold:
			var c := _pit_blame(imp[0], imp[1])
			if c >= 0:
				_pit_shoved[imp[1] if c == imp[0] else imp[0]] = pit_rules.incident_gap
				culprits.append(c)
	for imp in _impacts:
		if imp[1] < 0 and imp[2] >= damage_rules.wall_threshold and _pit_shoved[imp[0]] <= 0.0:
			culprits.append(imp[0])
	for culprit in culprits:
		if pits.in_lane[culprit] == 0 or _pit_shoved[culprit] > 0.0 or session.racers[culprit].is_done() or damage.is_retired(culprit):
			continue
		var fine := pits.collision(culprit)
		if fine > 0:
			var charged := fine if pits.pays_fines[culprit] == 1 else 0
			combat.events.append({"kind": "ticket", "car": culprit, "fine": charged, "reason": "collision"})
			stats.on_ticket(culprit, session.elapsed)
			_ticket_banner(culprit, charged)


## Which of two cars drove into the other (-1: neither was really moving at it).
func _pit_blame(a: int, b: int) -> int:
	var d := (cars[b].global_position - cars[a].global_position).normalized()
	var va := _pit_vel[a].dot(d)
	var vb := _pit_vel[b].dot(-d)
	if maxf(va, vb) < PIT_BLAME_SPEED:
		return -1
	return a if va >= vb else b


## A pit collision ticket for a human on this computer: one brief banner.
func _ticket_banner(id: int, fine: int) -> void:
	if hud == null or not session.human_ids.has(id) or (net != null and id != local_player_id):
		return
	var what := ("PIT COLLISION  -  FINE $%d" % fine) if fine > 0 else "PIT COLLISION  -  TICKET"
	if player_views != null:  # couch: in the offending player's own view only
		var v := player_views.view_for(id)
		if not v.is_empty():
			v.hud.flash_banner("PIT LANE VIOLATION!\n" + what, HyperTheme.RED, 1.6, 40)
			return
	hud.flash_banner("PIT LANE VIOLATION!\n" + what, HyperTheme.RED, 1.6, 56)


## The pit line for a human's car: service progress with the repair it brings,
## no free bay, the limiter with the override gesture, or the override.
func _refresh_pit(view_hud: Hud, id: int) -> void:
	if pits == null and pit_state.is_empty():
		return
	var st := pit_state[id] if id < pit_state.size() else 0
	var limiter := st & 1 == 1
	var over := st & 2 == 2
	var served := st & 4 == 4
	var service := float((st >> 3) & 31) / 31.0
	var bay := PitWorld.packed_bay(st)
	var in_lane := limiter or over or service > 0.0 or bay >= 0 or served
	var now := damage.fraction(id) * 100.0
	var wants := in_lane and not served and bay < 0 and now < 99.5 and race_mode != "knockout" \
		and not session.racers[id].is_done()
	if service > 0.0:
		var after := minf(100.0, now + pit_rules.repair_points)
		view_hud.update_pit("PIT %d SERVICE  -  REPAIRING\nCONDITION: %d%%  ->  %d%%" % [bay + 1, roundi(now), roundi(after)], HyperTheme.GOLD, service)
	elif wants and occupied_bays() >= bay_total():
		view_hud.update_pit("PIT FULL  -  NO FREE PIT BAY\nWAIT FOR A BAY OR DRIVE ON", HyperTheme.RED)
	elif limiter:
		view_hud.update_pit(PlayerControls.fmt("PIT LIMITER  -  %d%%\nDOUBLE-TAP {fire} TO OVERRIDE" % roundi(pit_rules.limiter_share * 100.0)))
	elif over and in_lane:
		view_hud.update_pit("LIMITER OFF  -  COLLISIONS IN THE PITS ARE FINED", HyperTheme.RED)
	else:
		view_hud.update_pit("")


## Service bays on this circuit (0 = no pit lane).
func bay_total() -> int:
	var k := track.layout.pit_branch() if track != null else -1
	return TrackLayout.bay_count(track.layout.branches[k]) if k >= 0 else 0


## Bays held right now (from the host's pit state: the same on every computer).
func occupied_bays() -> int:
	var n := 0
	for st in pit_state:
		n += int(PitWorld.packed_bay(st) >= 0)
	return n


## M6: a HUD's condition row for racer id (own_car: the DNF notice is shown).
func _refresh_condition(view_hud: Hud, id: int, show: bool = true, own_car: bool = true) -> void:
	if id < 0 or id >= cars.size():
		view_hud.update_condition(1.0, 999.0, false, false, false)
		return
	view_hud.update_condition(damage.fraction(id), damage.since_hit[id], damage.is_critical(id),
		session.racers[id].dnf, show, own_car)


## 0 = ready, 1 = just fired (a human's slot, for the HUD bar).
func _cooldown_fraction(slot: int, id: int = RaceSession.PLAYER_ID) -> float:
	var length := combat.slot_cooldown_length(slot)
	return clampf(combat.slot_wait(id, slot) / maxf(0.001, length), 0.0, 1.0)


# ------------------------------------------------------------- damage (M6)

## A car reported a contact during its physics step (other = -1: a barrier).
## Only the simulating computer counts damage, and only during a race.
func _queue_impact(id: int, other: int, speed: float) -> void:
	if (not damage_enabled and pits == null) or (net != null and net.is_client()) or session.state == RaceSession.State.MODE_SELECT:
		return  # (pit lanes need the contacts for their tickets even without damage)
	_impacts.append([id, other, speed])


## Whether a car can be damaged now: racing in this race, not finished, not out.
func _takes_damage(id: int) -> bool:
	return damage_enabled and session.state != RaceSession.State.MODE_SELECT and grid_order.has(id) \
		and session.is_participating(id) and not session.racers[id].is_done()


## Last tick's contacts, in the order the cars reported them, then the
## retired cars' timers (a retired wreck leaves the road after a while).
func _apply_impacts(step: float) -> void:
	damage.step(step)
	if session.state == RaceSession.State.FINISHED and session.all_finished():
		_impacts.clear()  # everyone is in: the race is over, bumps after it change nothing
	_pit_collisions()
	for imp in _impacts:
		var id: int = imp[0]
		var other: int = imp[1]
		if other < 0:
			if _takes_damage(id) and damage.wall_impact(id, imp[2]):
				_retire(id)
		else:
			var before := [damage.condition[id], damage.condition[other]]
			var outs := damage.car_impact(id, other, imp[2], _takes_damage(id), _takes_damage(other))
			if damage.condition[id] < before[0]:
				stats.on_contact(id, other, session.elapsed)
			if damage.condition[other] < before[1]:
				stats.on_contact(other, id, session.elapsed)
			for out in outs:
				_retire(out)
	_impacts.clear()
	for id in grid_order:
		if damage.is_retired(id) and cars[id].visible and damage.retired_age[id] >= damage_rules.retired_show_time:
			cars[id].visible = false


## The race introduction (HUD card before the start): what, where and - in a
## championship after its first round - the standings that matter, from the
## points so far (never invented).
func intro_lines() -> PackedStringArray:
	var what := championship_label
	if what == "":
		if session.spectator:
			what = "SPECTATING  -  THE NINE RIVALS"
		elif race_mode == "knockout":
			what = "KNOCKOUT  -  LAST PLACE IS OUT EVERY LAP"
		elif net != null:
			what = "NETWORK RACE"
		elif is_two_player():
			what = "TWO-PLAYER RACE"
		elif garage != null:
			what = "GARAGE RACE"
		else:
			what = "QUICK RACE"
	var where := "%s  -  %s  -  %s  -  %d laps%s" % [DevLayouts.display_name(DevLayouts.id_of(track.layout)).to_upper(),
		track_theme.display_name, "NIGHT" if night else "DAY", session.lap_count(),
		"" if weapons_enabled else "  -  NO GUNS"]
	return PackedStringArray([what, where, championship_line(championship_points, local_player_id)])


## "Rocco "Mad Dog" leads the championship - you are 2nd, 7 points behind".
## "" before any points are scored.
static func championship_line(points: Dictionary, me: int) -> String:
	if points.is_empty():
		return ""
	var ids: Array = points.keys()
	var total := 0
	for id in ids:
		total += int(points[id])
	if total <= 0:
		return ""
	ids.sort_custom(func(a: int, b: int) -> bool: return points[a] > points[b] or (points[a] == points[b] and a < b))
	var leader: int = ids[0]
	var who := func(id: int) -> String: return "you" if id == me else RivalRoster.full_name(id)
	if leader == me:
		var second: int = ids[1]
		var gap: int = int(points[me]) - int(points[second])
		return ("You lead the championship by %d point%s from %s" % [gap, "" if gap == 1 else "s", who.call(second)]) if gap > 0 \
			else "You share the championship lead with %s" % who.call(second)
	var pos := ids.find(me) + 1
	var behind: int = int(points[leader]) - int(points.get(me, 0))
	return "%s leads the championship  -  you are %s, %d point%s behind" % [who.call(leader),
		["", "1st", "2nd", "3rd"][pos] if pos <= 3 else "%dth" % pos, behind, "" if behind == 1 else "s"]


## "ROOKIE CUP - ROUND 2 OF 3\nLARKSPUR RING - The Raceway - DAY - 3 laps": the
## race's identity for the pause menu and the race introduction.
func _race_identity() -> String:
	var where := "%s  -  %s  -  %s  -  %d laps" % [DevLayouts.display_name(DevLayouts.id_of(track.layout)).to_upper(),
		track_theme.display_name, "NIGHT" if night else "DAY", session.lap_count()]
	var what := championship_label
	if what == "" and race_mode == "knockout":
		what = "KNOCKOUT"
	return (what + "\n" + where) if what != "" else where


## Zero condition: the car is out of the race (DNF). It stops where it is, no
## longer collides or takes part in combat, and leaves the road shortly after.
func _retire(id: int, by_weapon := false, eliminated := false) -> void:
	if eliminated:
		stats.on_eliminated(id, session.elapsed)  # by position: no statistics
		damage.retired[id] = 1  # out like a DNF: no collisions, never back (also after a weapon wreck)
	else:
		stats.on_retired(id, session.elapsed, by_weapon)
		var last: Dictionary = stats.feed[-1] if not stats.feed.is_empty() else {}
		if net != null and net.is_host() and last.get("victim", -2) == id and last.get("weapon", -1) == CombatStats.COLLISION:
			# the culprit of a collision retirement, for the client's kill feed (reliable EVENTS)
			combat.events.append({"kind": "retired", "car": id, "by": int(last.attacker)})
	var c := cars[id]
	c.active = false
	c.model.velocity = Vector2.ZERO
	c.airborne = false
	_apply_car_collision(id, true)
	inputs[id].on_destroyed()
	session.retire(id)


func _update_progress() -> void:
	for id in grid_order:
		progress[id].update(cars[id].global_position)
		session.set_progress(id, progress[id].distance)


## Every car in the race takes its command for this tick from its DriverInput.
# ------------------------------------------------ P003: debris costs grip

## Off to compare the old handling exactly (debug / tuning).
var debris_traction := true
var debris_field := DebrisField.new()
var _debris_cursor := 0
var _debris_share := PackedFloat32Array()
var _debris_out := PackedByteArray()


## Wrecks and lost bodywork leave debris (DebrisField); cars on it slide more
## and sweep it about. Every car alike, player or rival.
func _debris_tick(step: float) -> void:
	if not debris_traction:
		return
	if _debris_share.size() != cars.size():
		_debris_share.resize(cars.size())
		_debris_share.fill(1.0)
		_debris_out.resize(cars.size())
		_debris_out.fill(0)
	if combat != null:
		if _debris_cursor > combat.events.size():
			_debris_cursor = 0
		while _debris_cursor < combat.events.size():
			var e: Dictionary = combat.events[_debris_cursor]
			_debris_cursor += 1
			if e.kind == "destroyed" and int(e.car) >= 0 and int(e.car) < cars.size():
				debris_field.deposit(cars[e.car].global_position, DebrisField.WRECK_AMOUNT, DebrisField.WRECK_RADIUS)
	for i in cars.size():
		var c := cars[i]
		if damage != null:
			var f := damage.fraction(i)
			if f < _debris_share[i] - 0.001 and c.visible:
				debris_field.deposit(c.global_position, (_debris_share[i] - f) * DebrisField.DAMAGE_AMOUNT, DebrisField.DAMAGE_RADIUS)
			_debris_share[i] = f
			var out := damage.is_retired(i)
			if out and _debris_out[i] == 0 and c.visible:
				debris_field.deposit(c.global_position, DebrisField.WRECK_AMOUNT, DebrisField.WRECK_RADIUS)
			_debris_out[i] = 1 if out else 0
		if c.model == null:
			continue
		if not c.visible or c.airborne:
			c.model.grip_scale = 1.0
			continue
		c.model.grip_scale = debris_field.grip_scale(c.global_position)
		debris_field.sweep(c.global_position, c.model.velocity, step)


func _reset_debris() -> void:
	debris_field.clear()
	_debris_share.resize(cars.size())
	_debris_share.fill(1.0)
	_debris_out.resize(cars.size())
	_debris_out.fill(0)
	_debris_cursor = combat.events.size() if combat != null else 0
	for c in cars:
		if c.model != null:
			c.model.grip_scale = 1.0


func _drive_cars(step: float) -> void:
	_pit_requests.clear()
	for id in grid_order:
		var cmd := inputs[id].drive(self, step)
		cars[id].steer = cmd.steer
		cars[id].fire = cmd.fire
		if cmd.get("pit_override", false):
			_pit_requests[id] = true


## Pit lanes, one tick (host): where each car is, the limiter's speed cap,
## deliberate overrides (a ticket: an event for the feed, the announcer and the
## network; a fine or a penalty), and service in the box (+condition).
func _update_pits(step: float) -> void:
	if pits == null:
		return
	var layout := track.layout
	var length := track.path.length
	var cap := driving_params.max_speed * pit_rules.limiter_share
	for id in grid_order:
		var s: float = progress[id].distance
		var lat: float = progress[id].lateral
		var racing := session.state == RaceSession.State.RACING and not session.racers[id].is_done()
		var lane := racing and cars[id].active and layout.in_pit_lane(s, length, lat)
		var bay := layout.bay_at(s, length, lat) if lane else -1
		if lane and _pit_requests.has(id):
			pits.request_override(id)  # (allowed: no ticket for speeding)
		_pit_vel[id] = cars[id].model.velocity  # (before this tick's contacts: who drove into whom)
		_pit_shoved[id] = maxf(0.0, _pit_shoved[id] - step)
		var add := pits.step(id, lane, bay, cars[id].model.velocity.length(), damage.condition[id],
			damage_rules.max_condition, damage.is_retired(id) or not racing, step)
		if add > 0.0:
			damage.condition[id] = minf(damage_rules.max_condition, damage.condition[id] + add)
			combat.events.append({"kind": "pit_service", "car": id})
		cars[id].model.speed_cap = cap if pits.limiter_on(id) else INF
	pit_state.resize(cars.size())
	for id in cars.size():
		pit_state[id] = pits.pack(id)


func _on_checkpoint_reached(index: int, body: Node2D) -> void:
	if net != null and net.is_client():
		return  # laps come from the host
	var c := body as Car
	if c == null or not c.active:
		return
	session.checkpoint_reached(index, c.racer_id)


## Combat for one tick: the humans' Up/Down presses and then the rivals'
## decisions become fire requests (same rules for all), then the combat world
## advances; destroyed cars stop where they are, respawned cars carry on.
func _combat_tick(step: float) -> void:
	_update_weapons_lock()
	var states := _combat_states()
	for id in session.human_ids:
		if grid_order.has(id):
			var cmd := inputs[id].weapons(self, step, states)
			if not combat.locked:  # presses while locked are dropped, never fired later
				_request_weapons(id, cmd, states)
	if session.state != RaceSession.State.MODE_SELECT and not combat.locked:
		for id in grid_order:  # (rivals do not even decide while locked: nothing stockpiled)
			if not inputs[id].is_human():
				_request_weapons(id, inputs[id].weapons(self, step, states), states)
	var first_event := combat.events.size()
	var result := combat.step(step, states)
	for k in range(first_event, combat.events.size()):  # M6: a destruction also wears the car down
		var e: Dictionary = combat.events[k]
		if e.kind != "destroyed":
			continue
		stats.on_destroyed(e.car, e.owner, e.type, session.elapsed)
		if _takes_damage(e.car) and damage.weapon_hit(e.car, e.type):
			_retire(e.car, true)
	for k in range(first_event, combat.events.size()):  # Micro Nemesis: who did it
		var ev: Dictionary = combat.events[k]
		if ev.kind == "destroyed":
			inputs[ev.car].on_destroyed_by(ev.owner)
	for id in result.destroyed:
		cars[id].active = false
		cars[id].model.velocity = Vector2.ZERO
		inputs[id].on_destroyed()
	for id in result.respawned:
		cars[id].model.velocity = Vector2.ZERO
		if session.state != RaceSession.State.MODE_SELECT and not damage.is_retired(id):
			cars[id].active = true


## Wreck recovery: a racing car held against a stationary weapon wreck for
## WRECK_STUCK_TIME may drive through that one wreck (the first impact is
## normal). The exception ends once the wreck is racing again and the two
## are apart. Racing cars always collide with each other; retired (DNF) cars
## already collide with nothing.
func _update_wreck_passes(step: float) -> void:
	for w in grid_order:
		if not combat.is_wrecked(w):
			continue
		for id in grid_order:
			if id == w or not cars[id].active:
				continue
			var key := Vector2i(id, w)
			if _passing.has(key):
				continue
			var c := cars[id]
			if c.global_position.distance_to(cars[w].global_position) < 72.0 and c.model.velocity.length() < 90.0:
				_stuck[key] = _stuck.get(key, 0.0) + step
				if _stuck[key] >= WRECK_STUCK_TIME:
					c.add_collision_exception_with(cars[w])
					cars[w].add_collision_exception_with(c)
					_passing[key] = true
			else:
				_stuck.erase(key)
	for key in _passing.keys():
		var w: int = key.y
		if not combat.is_wrecked(w) and cars[key.x].global_position.distance_to(cars[w].global_position) > 90.0:
			cars[key.x].remove_collision_exception_with(cars[w])
			cars[w].remove_collision_exception_with(cars[key.x])
			_passing.erase(key)


func _clear_wreck_passes() -> void:
	for key in _passing:
		cars[key.x].remove_collision_exception_with(cars[key.y])
		cars[key.y].remove_collision_exception_with(cars[key.x])
	_passing.clear()
	_stuck.clear()


## Weapons Hot: unlocks once every car still in the race has crossed the
## start line for the first time (race distance from below zero to zero or
## more), or after weapons_lock_timeout seconds of racing.
func _update_weapons_lock() -> void:
	if not combat.locked or session.state != RaceSession.State.RACING:
		return
	var all_through := true
	for id in grid_order:
		if progress[id].distance >= 0.0:
			_crossed_start[id] = 1  # a real first crossing; later moves never undo it
		if not session.is_participating(id) or session.racers[id].is_done():
			continue  # retired / finished cars never hold the field
		if _crossed_start[id] == 0:
			all_through = false
	if all_through or session.elapsed >= weapons_lock_timeout:
		combat.unlock()
		for id in grid_order:
			inputs[id].discard_pending_shots()
		weapons_unlocked.emit()


func _request_weapons(id: int, cmd: Dictionary, states: Array) -> void:
	if damage.is_retired(id):
		return
	if cmd.get("cycle_front", false):  # weapon cycling first: a press in the same tick fires the new type
		combat.cycle(id, CombatWorld.FRONT)
	if cmd.get("cycle_rear", false):
		combat.cycle(id, CombatWorld.REAR)
	if cmd.front:
		combat.request(id, CombatWorld.FRONT, states)
	if cmd.rear:
		combat.request(id, CombatWorld.REAR, states)


func _combat_states() -> Array:
	var states: Array = []
	for i in cars.size():
		states.append({"position": cars[i].global_position, "heading": cars[i].model.heading,
			"present": grid_order.has(i) and not damage.is_retired(i)})
		if combat.layout != null:  # J4: road level for elevation-aware weapons
			states[i]["level"] = car_levels[i]
			states[i]["band"] = car_transitions[i] == 1
			states[i]["index"] = progress[i].index
			states[i]["air"] = cars[i].airborne
	return states
