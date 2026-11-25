extends Node
## Game root (run/main_scene): owns the title screen and starts the race scene
## (src/main/main.tscn) as a child with the chosen mode, fading between them.
## Loads and applies the saved audio settings. The race scene itself is
## unchanged and still runs on its own (tests use it directly).
## Garage races (M3.5): one PlayerGarage lives for the whole game session (money
## and weapons carry over between garage races until the game quits); the
## garage screen opens before the first garage race and after each one.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const MAIN_SCRIPT := preload("res://src/main/main.gd")

## Where achievements and rival careers are saved (tests use a scratch file).
@export var achievements_path := ""  # "" = AchievementStore.default_path
## Where the won rival cars are saved (tests use a scratch file).
@export var cars_path := ""  # "" = CarCollection.default_path
## Where the rival memory (Nemesis Welcome) is saved ("" = RivalMemory.default_path).
@export var memory_path := ""
## Nemesis Welcome on launch (off for screenshots / tests that need a quiet title).
@export var greetings_enabled := true

var resolver: AssetResolver
var settings: AudioSettings
var title: TitleScreen
var race: Node2D
var _fade: ColorRect
var garage: PlayerGarage
## True while a race scene is being started (guards against a second start).
var _starting := false
## LAN races (M5.1): the connection, kept from the title into the race scene.
var link: NetLink
var lan_port := NetLink.DEFAULT_PORT
## Host: the peer that connected and must say HELLO (matching version) in time.
var _pending_peer := 0
## Client: when connecting started (ms) and to where, for the progress message.
var _connect_started := -1
var _connect_target := ""
const HELLO_TIMEOUT := 8.0
var garage_screen: GarageScreen
## Achievements (M3.5): one persistent store for the installation, the toast.
var achievements: AchievementStore
var toast: AchievementToast
## The music for the whole session (menus and races hand it over, no restarts).
var music: MusicPlayer
## Championship: the won rival cars (saved), the running championship (null
## outside one), its screen, the player's control choice for its rounds, and
## the last reward (rival id, -1 none) for tests.
var cars: CarCollection
var champ: Championship
var champ_screen: ChampionshipScreen
var _champ_choice := 0
var last_reward := -1
## Racing for Keeps: the won car lost in the last championship (0 none), for tests.
var last_lost := 0
## Race variety: every new race scene gets its own AI seed from this
## generator, so players do not see the same rival decisions every session.
## `-- --seed=N` (or setting it before _ready) makes a whole session
## reproducible; tests and probes that build race scenes directly keep the
## race scene's fixed default seed.
var race_rng := RandomNumberGenerator.new()
## The rival memory and this launch's greeting (null: none this time).
var memory: RivalMemory
var welcome: NemesisWelcome = null
var session_seed := -1
## Career (2026-11-22): its progress (user://career.cfg), its own garage
## (user://career_garage.cfg; the standalone Garage Race career is separate),
## the hub, the ending and the credits. _career_mode: the championship being
## raced is the career's. _career_outcome: what the last career round decided
## ({outcome, reward, reward_car}) until its standings have been shown.
@export var career_path := ""  # "" = Career.default_path
@export var career_garage_path := ""  # "" = CAREER_GARAGE_PATH
const CAREER_GARAGE_PATH := "user://career_garage.cfg"
var career: Career
var career_garage: PlayerGarage
var career_screen: CareerScreen
var victory: VictoryScreen
var credits: CreditsScreen
var _career_mode := false
var _career_outcome := {}
## Career milestones (cards between screens) and the rival who reacted last
## (nobody reacts twice in a row).
var milestones: MilestoneScreen
var _last_reaction_rival := -1
var _career_garage_open := false
## VoxelRacing: the animated track loading screen ("The Little Race").
var loading: LoadingRace


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	settings = AudioSettings.new()
	settings.load_settings()
	settings.apply()
	AssetResolver.templates_only = settings.original_artwork  # Artwork Mode (graphics; read at start)
	ControlBindings.load_saved()  # the player's remapped controls (CONTROLS screen)
	resolver = AssetResolver.new()
	achievements = AchievementStore.new(achievements_path)
	achievements.load_store()
	toast = AchievementToast.new()
	toast.name = "AchievementToast"
	add_child(toast)
	toast.setup(resolver)
	achievements.unlocked.connect(toast.show_unlock)
	title = TitleScreen.new()
	title.name = "Title"
	music = MusicPlayer.new()
	music.name = "Music"
	add_child(music)
	music.resolver = resolver
	title.music = music
	title.achievements = achievements
	cars = CarCollection.new(cars_path)
	title.cars = cars
	title.championship = ChampionshipSchedule.for_run(cars.championships_run)
	add_child(title)
	title.setup(resolver, settings)
	memory = RivalMemory.new(memory_path)
	memory.load_from_disk()
	if cars.forfeited_on_load > 0:  # the game was closed during a championship for keeps
		title.show_notice(lost_text(cars.forfeited_on_load, true))
		_remember_car_back(cars.forfeited_on_load)
	if greetings_enabled:
		_greet()
	title.start_requested.connect(start_race)
	title.two_player_requested.connect(func(devices: Array[int]) -> void: start_race(0, false, devices))
	title.lan_host_requested.connect(func() -> void: host_lan())
	title.lan_join_requested.connect(func(address: String) -> void: join_lan(address))
	title.lan_cancel_requested.connect(close_lan)
	title.quit_requested.connect(quit_game)
	title.championship_requested.connect(start_championship)
	title.mode_requested.connect(func(mode: String, choice: int) -> void:
		if mode == "battle":
			start_battle(choice)
		else:
			start_race(choice, false, [], null, -1, "", false, {}, mode))
	champ_screen = ChampionshipScreen.new()
	champ_screen.name = "ChampionshipScreen"
	add_child(champ_screen)
	champ_screen.setup(resolver)
	champ_screen.continue_requested.connect(_next_round)
	champ_screen.abandon_requested.connect(abandon_championship)
	champ_screen.done.connect(abandon_championship)
	# achievement toasts wait while the standings are up (they overlapped them)
	champ_screen.visibility_changed.connect(func() -> void: toast.set_held(champ_screen.visible))
	if session_seed < 0:
		session_seed = GameSeed.from_args(OS.get_cmdline_user_args())
	race_rng.seed = session_seed
	garage = PlayerGarage.load_or_new(load("res://src/garage/default_garage_rules.tres"))  # saved career
	garage_screen = GarageScreen.new()
	garage_screen.name = "Garage"
	add_child(garage_screen)
	garage_screen.setup(garage, resolver)
	title.garage = garage
	garage_screen.race_requested.connect(func() -> void: _close_garage(true))
	garage_screen.closed.connect(func() -> void: _close_garage(false))
	_setup_career()
	loading = LoadingRace.new()
	loading.name = "LoadingRace"
	add_child(loading)
	if VoxelStage.available() and VoxelIconStudio.icons.is_empty():
		var studio := VoxelIconStudio.new()
		studio.name = "IconStudio"
		add_child(studio)
		studio.done.connect(studio.queue_free)
		studio.render_all(resolver)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = VrStyle.INK
	_fade.size = Vector2(1280, 720)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	await _fade_to(0.0)


## choice: 0 Fire to Accelerate, 1 Fire to Brake, 2 Spectate rivals.
## with_garage: a garage race (money and the player's own weapons).
## devices: two-player split-screen with these controllers (no garage or
## achievements in two-player races).
## net: a LAN race (NetRace host or client); net_track: the host's track (client).
## net_night: the host's time of day (client). round: a championship round
## (Championship.next_round(); empty = not a championship race).
func start_race(choice: int, with_garage: bool = false, devices: Array[int] = [], net: NetRace = null, net_track: int = -1,
		net_layout: String = "", net_night: bool = false, round: Dictionary = {}, mode: String = "race") -> void:
	if race != null or _starting:
		return  # a race is already running or starting: never create a second one
	_starting = true
	PlayerControls.set_race_context(true)  # Fire never presses a button from here on
	await _fade_to(1.0)
	title.hide_title()
	# The Little Race: the loading screen runs while the voxel world is built
	var client_flag := net != null and net.is_client()
	var lid: String = String(round.layout) if not round.is_empty() else (net_layout if client_flag else title.layout_id)
	var variant: int = int(round.variant) if not round.is_empty() else (net_track if client_flag else title.track_variant)
	var is_night: bool = bool(round.night) if not round.is_empty() else (net_night if client_flag else title.night)
	loading.begin(DevLayouts.display_name(lid).to_upper(), "%s  -  %s%s" % [TrackTheme.load_variant(variant).display_name.to_upper(),
		"NIGHT" if is_night else "DAY", "  -  SPECTATING" if choice == 2 else ""])
	await _fade_to(0.0)
	await get_tree().process_frame
	race = MAIN_SCENE.instantiate()
	race.allow_exit = true
	race.base_seed = race_rng.randi()
	race.shuffle_first_grid = true  # race variety: the rivals' first grid varies too
	race.music = music
	race.dynamic_vehicle_lights = settings.vehicle_lights
	race.headlight_color = settings.headlight_color
	var two := devices.size() == 2 or net != null
	if net != null:
		race.human_count = 2
		race.net = net
	elif two:
		race.human_count = 2
		race.player_devices = devices
	elif with_garage and choice != 2:
		race.garage = career_garage if _career_mode else garage
		garage_screen.set_garage(race.garage)
	if not two and mode == "race":  # (Knockout is not counted for achievements)
		race.achievements = achievements
		if choice != 2:  # the player's own races (not spectating) are remembered by the rivals
			race.rival_memory = memory
	race.race_mode = mode
	race.watch_enabled = true  # finished early: watch the rest live (single-player only)
	var client := net != null and net.is_client()
	race.track_variant = net_track if client else title.track_variant
	race.night = net_night if client else title.night
	# the title's LAYOUT choice (a LAN / online client: the host's layout)
	race.use_command_line_layout = false
	race.layout_override = DevLayouts.load_layout(net_layout if client else title.layout_id)
	if not two:  # won rival cars (single-player and spectating only)
		race.player_car = title.player_car if cars.owns(title.player_car) else CarCollection.OWN_CAR
		if _career_mode:  # the car the career championship was entered with
			race.player_car = career.player_car if cars.owns(career.player_car) else CarCollection.OWN_CAR
		race.displaced = cars.owned.duplicate()
	if not round.is_empty():
		race.track_variant = round.variant
		race.night = round.night
		race.layout_override = DevLayouts.load_layout(round.layout)
		race.championship_round = champ.round_index()
		race.championship_grid = champ.next_grid()
		race.championship_points = champ.points.duplicate()
		race.championship_scoring = champ.schedule.points
		race.championship_label = ("GRAND FINAL  -  ROUND %d OF %d" if round.get("final", false) else "ROUND %d OF %d") % [champ.round_index() + 1, champ.schedule.round_count()]
		if _career_mode:
			race.championship_label = "%s  -  %s" % [champ.schedule.title.to_upper(), race.championship_label]
			race.forfeit_warning = "Leaving before you finish forfeits this %s attempt (the rounds so far are lost)." % champ.schedule.title
			if cars.career_stake > 0:
				race.championship_label += "  -  FOR KEEPS: %s'S CAR" % RivalRoster.short_name(cars.career_stake).to_upper()
				race.forfeit_warning += " %s takes the car back." % RivalRoster.short_name(cars.career_stake)
		elif cars.stake > 0:
			race.championship_label += "  -  FOR KEEPS: %s'S CAR" % RivalRoster.short_name(cars.stake).to_upper()
			race.forfeit_warning = "Leaving forfeits the championship: %s takes the car back." % RivalRoster.short_name(cars.stake)
	add_child(race)
	race.garage_requested.connect(_open_garage)
	race.camera.make_current()
	race.set_menu_choice(choice)
	if net == null or net.is_host():  # a LAN client takes the host's settings
		race.set_weapons_enabled(title.weapons_on)
		race.set_combat_style(title.combat_style)
		if _career_mode:  # career stages are raced armed, in the stage's combat style
			race.set_weapons_enabled(true)
			if champ.schedule.career_style >= 0:
				race.set_combat_style(champ.schedule.career_style)
		race.set_lap_count(title.laps if round.is_empty() else int(round.laps))
		if mode == "knockout":
			race.set_lap_count(race.cars.size() - 1)  # one elimination per lap until one is left
	race.exit_requested.connect(back_to_title)
	if not round.is_empty():
		race.championship_round_done.connect(_on_round_done)
	if _career_mode:
		race.race_began.connect(_on_career_race_began)
		race.race_concluded.connect(_on_career_concluded)
	await _await_world()
	if choice == 2:
		race.start_race()  # spectating starts straight away
	elif with_garage and not _garage_just_seen:
		race.open_garage()  # shop before the first garage race
	_garage_just_seen = false
	_starting = false
	await _fade_to(0.0)


## Lets the loading race run until the race's voxel world is ready, then
## fades from it to the race.
func _await_world() -> void:
	var voxel: VoxelStage = race.get("voxel") if race != null else null
	if voxel != null:
		loading.progress_source = voxel.progress
		if not voxel.ready_3d:
			await voxel.world_ready
	loading.complete()
	if loading.visible:
		await loading.finished
	await _fade_to(1.0)
	loading.end()


func _open_garage() -> void:
	_show_garage_car(race.player_car if race != null else CarCollection.OWN_CAR)
	garage_screen.open()


## The garage's centrepiece: the car being prepared, as it races (CarArt).
func _show_garage_car(car: int) -> void:
	var owned := car > 0 and cars.owns(car)
	garage_screen.set_car(CarArt.icon(resolver, AssetCatalog.ai_car(car) if owned else AssetCatalog.CAR_PLAYER),
		("%s'S CAR" % RivalRoster.short_name(car).to_upper()) if owned else "YOUR OWN CAR")
	music.play("music/music_menu")


func _close_garage(start: bool) -> void:
	garage_screen.close()
	if _champ_garage_open:  # between championship rounds (no race scene)
		_champ_garage_open = false
		garage_screen.set_back_label("grid panel")
		if start and champ != null and not champ.finished() and race == null and not _starting:
			_garage_just_seen = true
			start_race(_champ_choice, true, [], null, -1, "", false, champ.next_round())
		elif champ != null:
			champ_screen.show_standings(champ)
		return
	if _career_garage_open:  # opened from the career hub (no race scene yet)
		_career_garage_open = false
		garage_screen.set_back_label("grid panel")
		if start:
			_enter_career_stage(_career_main_stage())
		else:
			career_screen.open()
		return
	if race != null:
		race.close_garage(start)


func back_to_title() -> void:
	await _fade_to(1.0)
	garage_screen.close()
	champ_screen.close()
	var career_notice := ""
	if _career_mode:
		career_notice = _leave_career_race()
	else:
		_forfeit_championship()
	champ = null  # leaving a championship round abandons the championship
	close_lan()
	if race != null:
		race.queue_free()
		race = null
	title.show_title()
	if _career_mode:
		_career_mode = false
		if not _career_outcome.is_empty():  # the round was decided: its standings first
			_show_career_standings()
			return
		career_screen.open(career_notice)
	await _fade_to(0.0)


# ------------------------------------------------------------ Nemesis Welcome

## Now and then a rival greets the player at the title, about something that
## really happened (RivalMemory, NemesisLines). Its car as the player sees it
## in races: its own colours, or the junker while the player owns its car.
func _greet() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var e := memory.pick_greeting(rng)
	memory.save()
	if e.is_empty():
		return
	show_greeting(e, rng)


func show_greeting(e: Dictionary, rng: RandomNumberGenerator) -> NemesisWelcome:
	var g := NemesisLines.greeting(e, rng)
	var rival: int = g.rival
	var car := CarArt.icon(resolver, AssetCatalog.CAR_JUNKER if cars.displaced(rival) else AssetCatalog.ai_car(rival))
	if welcome != null:
		welcome.queue_free()
	welcome = NemesisWelcome.new()
	welcome.name = "NemesisWelcome"
	add_child(welcome)
	welcome.setup(resolver, g, car)
	welcome.show_greeting()
	return welcome


## A rival took its car back (Racing for Keeps): remembered.
func _remember_car_back(rival: int) -> void:
	memory.add(RivalMemory.TOOK_CAR_BACK, rival, {"mode": "championship"})
	memory.save()


# -------------------------------------------------------------- Battle Royale

## GO RACING! > BATTLE ROYALE: the arena with the title's biome, time and car.
func start_battle(choice: int) -> void:
	if race != null or _starting:
		return
	_starting = true
	PlayerControls.set_race_context(true)
	await _fade_to(1.0)
	title.hide_title()
	loading.begin("BATTLE ROYALE", "THE SCRAPYARD  -  %s  -  %s" % [TrackTheme.load_variant(title.track_variant).display_name.to_upper(),
		"NIGHT" if title.night else "DAY"])
	await _fade_to(0.0)
	await get_tree().process_frame
	var b := BattleRoyale.new()
	b.name = "BattleRoyale"
	b.track_variant = title.track_variant
	b.night = title.night
	b.headlight_color = settings.headlight_color
	b.player_car = title.player_car if cars.owns(title.player_car) else CarCollection.OWN_CAR
	b.displaced = cars.owned.duplicate()
	b.music = music
	b.base_seed = race_rng.randi()
	race = b
	add_child(b)
	if choice == 1:
		b.cars[0].model.control_mode = CarModel.ControlMode.FIRE_TO_BRAKE
	b.exit_requested.connect(back_to_title)
	b.restart_requested.connect(func() -> void: _restart_battle(choice))
	b.set_physics_process(false)  # the fight waits for its voxel world
	await _await_world()
	if is_instance_valid(b):
		b.set_physics_process(true)
	_starting = false
	await _fade_to(0.0)


func _restart_battle(choice: int) -> void:
	if race != null:
		race.queue_free()
		race = null
	start_battle(choice)


# ---------------------------------------------------------------- Championship

## Starts a championship (six rounds, or the three-round version) with the title's next schedule.
func start_championship(choice: int) -> void:
	if race != null or _starting or champ != null:
		return
	champ = Championship.new(title.championship.with_length(title.championship_rounds))
	_champ_choice = choice
	last_reward = -1
	last_lost = 0
	cars.put_at_stake(title.player_car)  # Racing for Keeps (the own car is never at stake)
	cars.count_championship()
	title.championship = ChampionshipSchedule.for_run(cars.championships_run)  # the one after this
	start_race(choice, true, [], null, -1, "", false, champ.next_round())


## A round's result (Enter on the results): record it and show the standings.
func _on_round_done(order: Array, dnf: Array) -> void:
	if _career_mode:  # (recorded when the race concluded)
		_show_career_standings()
		return
	if champ == null or race == null:
		return
	var before: Dictionary = champ.points.duplicate()
	var history: Array = champ.results.duplicate(true)
	champ.record(order, dnf)
	var facts := round_facts(race, order, dnf, before, champ.points, history, champ)
	_set_reaction(facts)
	await _fade_to(1.0)
	var player_car: int = race.player_car
	race.queue_free()
	race = null
	champ_screen.set_icons(car_icons(player_car))
	music.play("music/music_menu")
	var reward := ""
	var reward_car: Texture2D = null
	if champ.finished():
		if champ.champion() == Championship.PLAYER:
			cars.clear_stake()  # the car entered with stays
			last_reward = cars.claim_lowest(champ.standings())
			if last_reward > 0:
				memory.add(RivalMemory.WON_MY_CAR, last_reward, {"mode": "championship"})
				memory.save()
			reward = reward_text(last_reward, cars.all_owned())
			if last_reward > 0:
				reward_car = CarArt.icon(resolver, AssetCatalog.ai_car(last_reward))
		elif cars.stake > 0:
			last_lost = cars.stake
			cars.lose(last_lost)
			_remember_car_back(last_lost)
			reward = lost_text(last_lost)
			reward_car = CarArt.icon(resolver, AssetCatalog.ai_car(last_lost))
		else:
			reward = "Win the championship to take one of your rivals' cars."
		title.refresh_car_choice()
	champ_screen.career = false
	champ_screen.accent = HyperTheme.GOLD
	champ_screen.warning = "FOR KEEPS: abandoning gives %s's car back." % RivalRoster.short_name(cars.stake) \
		if cars.stake > 0 and not champ.finished() else ""
	champ_screen.show_standings(champ, reward, reward_car)
	await _fade_to(0.0)


## The reward message for a won championship (rival -1: nothing left to win).
static func reward_text(rival: int, all_owned: bool) -> String:
	if rival < 1:
		return "CHAMPIONSHIP WON!\nYou already own all nine rival cars - the collection is complete."
	var text := ("CHAMPIONSHIP WON - YOU CLAIMED %s'S CAR!\nThe lowest-placed rival whose car you did not own yet: %s's car is yours, "
		+ "in its original colours. %s races a junker from now on.") % [
		RivalRoster.short_name(rival).to_upper(), RivalRoster.full_name(rival), RivalRoster.short_name(rival)]
	if all_owned:
		text += "\nALL NINE RIVAL CARS COLLECTED!"
	return text


## Racing for Keeps: the result when the car at stake goes back.
static func lost_text(rival: int, forfeit: bool = false) -> String:
	return "%s\n%s RECLAIMS THE CAR!\nWin it back in a later championship." % [
		"CHAMPIONSHIP FORFEITED" if forfeit else "CHAMPIONSHIP LOST", RivalRoster.short_name(rival).to_upper()]


## Car pictures for the standings, as the cars race (junkers, the player's car).
func car_icons(player_car: int) -> Dictionary:
	var icons := {}
	icons[RaceSession.PLAYER_ID] = CarArt.icon(resolver, AssetCatalog.ai_car(player_car)) \
		if player_car > 0 else CarArt.icon(resolver, AssetCatalog.CAR_PLAYER)
	for id in range(1, 10):
		icons[id] = CarArt.icon(resolver, AssetCatalog.CAR_JUNKER if cars.displaced(id) else AssetCatalog.ai_car(id))
	return icons


func _next_round() -> void:
	if champ_screen.career:
		champ_screen.close()
		_enter_career_stage(career.active_stage)
		return
	if champ == null or champ.finished() or race != null or _starting:
		return
	champ_screen.close()
	_open_championship_garage()


## P003: between championship rounds the player is in the garage (repairs,
## weapons, upgrades, prize money from the round); its RACE button starts the
## next round, Back returns to the standings.
var _champ_garage_open := false
## The next round comes straight from the garage: no second garage on its grid.
var _garage_just_seen := false


func _open_championship_garage() -> void:
	_champ_garage_open = true
	garage_screen.set_garage(garage)
	garage_screen.set_back_label("standings")
	_show_garage_car(title.player_car if cars.owns(title.player_car) else CarCollection.OWN_CAR)
	garage_screen.open()


## Abandon (or, after the final, finish) the championship: back to the menu.
## Abandoning an unfinished championship for keeps forfeits the car at stake
## (the screens ask for confirmation first).
func abandon_championship() -> void:
	if race != null:
		return
	if champ_screen.career:
		_leave_career_standings()
		return
	back_to_title()


## Leaving an unfinished championship: a car at stake goes back to its rival.
func _forfeit_championship() -> void:
	if champ == null or champ.finished():
		return
	if cars.stake > 0:
		last_lost = cars.stake
		cars.lose(last_lost)
		_remember_car_back(last_lost)
		title.refresh_car_choice()
		title.show_notice(lost_text(last_lost, true))
	cars.clear_stake()


# ---------------------------------------------------------------- Career

func _setup_career() -> void:
	career = Career.new(career_path)
	career.load_from_disk()
	career_garage = PlayerGarage.load_or_new(load("res://src/garage/default_garage_rules.tres"),
		career_garage_path if career_garage_path != "" else CAREER_GARAGE_PATH)
	career_screen = CareerScreen.new()
	career_screen.name = "CareerScreen"
	add_child(career_screen)
	career_screen.setup(resolver)
	career_screen.career = career
	career_screen.garage = career_garage
	career_screen.cars = cars
	career_screen.stage_requested.connect(_enter_career_stage)
	career_screen.garage_requested.connect(_open_career_garage)
	career_screen.standings_requested.connect(func() -> void:
		career_screen.close()
		_show_career_standings())
	career_screen.new_career_confirmed.connect(new_career)
	career_screen.car_cycle_requested.connect(func() -> void:
		title._cycle_car(1)
		career_screen.chosen_car = _career_car_choice()
		career_screen.refresh())
	career_screen.back_requested.connect(func() -> void:
		career_screen.close()
		title.focus_main())
	milestones = MilestoneScreen.new()
	milestones.name = "Milestones"
	add_child(milestones)
	milestones.setup(resolver)
	victory = VictoryScreen.new()
	victory.name = "Victory"
	add_child(victory)
	victory.setup(resolver)
	victory.done.connect(_after_victory)
	credits = CreditsScreen.new()
	credits.name = "Credits"
	add_child(credits)
	credits.setup(resolver)
	credits.closed.connect(title.focus_main)
	title.career_requested.connect(func() -> void: open_career())
	title.credits_requested.connect(credits.open)
	if career.forfeited_on_load >= 0:  # the game closed during a career race
		var text := "CAREER: THE GAME CLOSED DURING A RACE\nThe %s attempt is forfeited." % Career.stage_title(career.forfeited_on_load)
		if cars.career_stake > 0:
			var lost := cars.career_stake
			cars.lose(lost)
			_remember_car_back(lost)
			text += " %s takes the car back." % RivalRoster.short_name(lost)
		title.show_notice(text)
	elif cars.career_stake > 0 and not career.in_championship():
		cars.clear_career_stake()  # (nothing running any more: nothing at stake)


## The car a new career stage would be entered with: the CAR choice, if owned.
func _career_car_choice() -> int:
	return title.player_car if cars.owns(title.player_car) else CarCollection.OWN_CAR


func _career_main_stage() -> int:
	return career.active_stage if career.in_championship() else career.current_stage()


## CAREER on the main menu: the hub (notice: a line in red).
func open_career(notice: String = "") -> void:
	if race != null or _starting:
		return
	career_screen.chosen_car = _career_car_choice()
	if achievements != null:
		career_screen.achievements_unlocked = achievements.unlocked_count() if achievements.has_method("unlocked_count") else 0
		career_screen.achievements_total = AchievementCatalog.ids().size()
	career_screen.open(notice)


## Enters a career stage: continues its running championship, or starts a
## new attempt (Racing for Keeps with a won car). The garage opens first.
func _enter_career_stage(stage: int) -> void:
	if race != null or _starting:
		return
	if career.in_championship():
		if career.active_stage != stage:
			return
	var cards: Array = []
	if not career.in_championship():
		var car := _career_car_choice()
		if not career.start_stage(stage, car):
			return
		cars.put_career_stake(car)
		cards.append(_stage_intro(stage))
	elif career.champ.next_round().get("final", false):
		cards.append(_final_intro())
	_career_outcome = {}
	career_screen.close()
	if not cards.is_empty():
		milestones.show_queue(cards)
		if milestones.showing():
			await milestones.finished
		if race != null or _starting:
			return
	champ_screen.career = false
	_career_mode = true
	champ = career.champ
	start_race(title.control_choice, true, [], null, -1, "", false, champ.next_round())


func _open_career_garage() -> void:
	career_screen.close()
	_career_garage_open = true
	garage_screen.set_garage(career_garage)
	garage_screen.set_back_label("career")
	_show_garage_car(career.player_car if career.in_championship() else _career_car_choice())
	garage_screen.open()


func _on_career_race_began() -> void:
	career.begin_race()


## A career race concluded (every car in, or the player left after finishing):
## the round is recorded and, when it decides the championship, the rewards
## are applied - exactly once, before any screen.
func _on_career_concluded(order: Array) -> void:
	if race == null or not career.in_championship() or not _career_mode:
		return
	var dnf: Array = []
	for r in race.session.racers:
		if r.dnf and order.has(r.id):
			dnf.append(r.id)
	var before: Dictionary = career.champ.points.duplicate()
	var history: Array = career.champ.results.duplicate(true)
	var wins_before := career.race_wins
	var stage_schedule: ChampionshipSchedule = career.champ.schedule
	var out := career.record_round(order, dnf)
	if not out.recorded:
		return
	var facts := round_facts(race, order, dnf, before, career.champ.points, history, career.champ)
	if race.garage != null and race._garage_settled:
		career.add_prize(race.garage.last_prize)
	var reward := ""
	var reward_car: Texture2D = null
	if out.finished:
		var stage_name := Career.stage_title(out.stage).to_upper()
		if out.won:
			career_garage.add_money(out.bonus)
			cars.clear_career_stake()
			last_reward = cars.claim_lowest(career.champ.standings())
			if last_reward > 0:
				memory.add(RivalMemory.WON_MY_CAR, last_reward, {"mode": "championship"})
				memory.save()
				reward_car = CarArt.icon(resolver, AssetCatalog.ai_car(last_reward))
			reward = "%s WON!  Title bonus $%d.\n%s" % [stage_name, out.bonus, reward_text(last_reward, cars.all_owned())]
			if out.completed_now:
				reward += "\nYOU ARE THE HYPERCARS CHAMPION!"
			elif out.stage < Career.FINAL_STAGE and not career.completed:
				reward += "\nNEXT: THE %s IS OPEN." % Career.stage_title(out.stage + 1).to_upper()
		else:
			reward = "%s WINS THE %s.\nEnter it again from the career screen: your garage, money and cars are kept." % [
				RivalRoster.full_name(out.champion).to_upper(), stage_name]
			if cars.career_stake > 0:
				last_lost = cars.career_stake
				cars.lose(last_lost)
				_remember_car_back(last_lost)
				reward_car = CarArt.icon(resolver, AssetCatalog.ai_car(last_lost))
				reward += "\n%s RECLAIMS THE CAR!" % RivalRoster.short_name(last_lost).to_upper()
		title.refresh_car_choice()
	var cards := _round_milestones(out, order, dnf, wins_before, stage_schedule)
	_career_outcome = {"outcome": out, "reward": reward, "reward_car": reward_car, "facts": facts, "milestones": cards}


## The facts of a championship round for RivalReactions (from the race scene
## before it is freed): order, retirements, finish times, the combat feed,
## points before / after, earlier rounds, and the decision.
func round_facts(r: Node, order: Array, dnf: Array, before: Dictionary, after: Dictionary, history: Array,
		c: Championship) -> Dictionary:
	var times := {}
	for st in r.session.racers:
		if st.is_finished() and not st.dnf and st.finish_time >= 0.0:
			times[st.id] = st.finish_time
	return {"order": order.duplicate(), "dnf": dnf.duplicate(), "times": times,
		"feed": (r.stats.feed as Array).duplicate(true) if r.stats != null else [],
		"before": before.duplicate(), "after": after.duplicate(), "history": history,
		"final": c.finished(), "champion": c.champion(), "me": RaceSession.PLAYER_ID}


## The standings' rival reaction for a round's facts (at most one; nobody
## twice in a row; most rounds none).
func _set_reaction(facts: Dictionary) -> void:
	var r := RivalReactions.pick(facts, _last_reaction_rival)
	if r.is_empty():
		champ_screen.set_reaction({})
		return
	_last_reaction_rival = r.rival
	champ_screen.set_reaction(r, CarArt.icon(resolver, AssetCatalog.CAR_JUNKER if cars.displaced(r.rival)
		else AssetCatalog.ai_car(r.rival)))


func _player_car_icon() -> Texture2D:
	var car := career.player_car if cars.owns(career.player_car) else CarCollection.OWN_CAR
	return CarArt.icon(resolver, AssetCatalog.ai_car(car) if car > 0 else AssetCatalog.CAR_PLAYER)


## The card that opens a career stage.
func _stage_intro(stage: int) -> Dictionary:
	var s := Career.schedule(stage)
	var title := ("STAGE %d OF 3" % (stage + 1)) if stage < Career.FINAL_STAGE else "THE FINAL STAGE"
	var subtitle := "%s  -  %s" % [s.title.to_upper(), s.career_tagline.to_upper()]
	if stage == 0 and career.attempts[0] <= 1 and not career.completed:
		title = "YOUR CAREER BEGINS"
	return {"title": title, "subtitle": subtitle, "detail": s.blurb, "car": _player_car_icon(), "accent": s.career_accent}


## The card before the Grand Final.
func _final_intro() -> Dictionary:
	var r: Dictionary = career.champ.next_round()
	var s: ChampionshipSchedule = career.champ.schedule
	return {"title": "THE GRAND FINAL", "subtitle": ChampionshipScreen.round_text(r).replace("\n", "  -  "),
		"detail": MAIN_SCRIPT.championship_line(career.champ.points, RaceSession.PLAYER_ID) + ".\nEverything is decided tonight.",
		"car": _player_car_icon(), "accent": s.career_accent}


## Milestone cards after a career round (before its standings), from what
## the round decided.
func _round_milestones(out: Dictionary, order: Array, dnf: Array, wins_before: int, s: ChampionshipSchedule) -> Array:
	var cards: Array = []
	var won_round: bool = not order.is_empty() and order[0] == RaceSession.PLAYER_ID and not dnf.has(RaceSession.PLAYER_ID)
	if won_round and wins_before == 0 and career.race_wins == 1:
		cards.append({"title": "FIRST CAREER VICTORY", "subtitle": s.title.to_upper(),
			"detail": "The rivals know your name now.", "car": _player_car_icon(), "accent": s.career_accent})
	if not out.get("finished", false):
		return cards
	if out.won and not out.completed_now:
		var next := ""
		if out.stage < Career.FINAL_STAGE:
			next = "PROMOTED TO THE %s" % Career.stage_title(out.stage + 1).to_upper()
		cards.append({"title": "%s CHAMPION" % s.title.to_upper(), "subtitle": next,
			"detail": "Title bonus $%d." % out.bonus, "car": _player_car_icon(), "accent": s.career_accent})
	if out.won and last_reward > 0:
		cards.append({"title": "YOU CLAIMED %s'S CAR" % RivalRoster.short_name(last_reward).to_upper(),
			"subtitle": RivalRoster.full_name(last_reward).to_upper(),
			"detail": "Yours, in its original colours. %s races the junker from now on." % RivalRoster.short_name(last_reward),
			"car": CarArt.icon(resolver, AssetCatalog.ai_car(last_reward)), "accent": HyperTheme.GOLD})
	if not out.won:
		var champion: int = out.champion
		cards.append({"title": "%s WINS THE %s" % [RivalRoster.short_name(champion).to_upper(), s.title.to_upper()],
			"subtitle": RivalRoster.full_name(champion).to_upper(),
			"detail": "The stage stays open: enter it again when you are ready.",
			"car": CarArt.icon(resolver, AssetCatalog.CAR_JUNKER if cars.displaced(champion) else AssetCatalog.ai_car(champion)),
			"accent": Color("ff8a6a")})
	return cards


## Leaving a career race scene (the race menu, or Back on the grid panel):
## a race the player has finished is recorded; one still running forfeits the
## attempt. Returns a notice for the career screen ("" none).
func _leave_career_race() -> String:
	if race != null and race.session.state == RaceSession.State.FINISHED:
		race._conclude_race()  # (records the round: _on_career_concluded)
	if not career.in_race:
		return ""  # nothing was running (the grid panel or the results): progress is saved
	var stage := career.forfeit()
	var text := "You left the race: the %s attempt is forfeited. Enter the stage again when you are ready." % Career.stage_title(stage)
	if cars.career_stake > 0:
		last_lost = cars.career_stake
		cars.lose(last_lost)
		_remember_car_back(last_lost)
		title.refresh_car_choice()
		text += " %s took the car back." % RivalRoster.short_name(last_lost)
	return text


## The career championship's standings: after a round (with what it decided)
## or from the career screen between rounds.
func _show_career_standings() -> void:
	await _fade_to(1.0)
	if race != null:
		race.queue_free()
		race = null
		# The title scene was hidden when the race began: restore it behind the
		# career screens (as back_to_title does), so that leaving the hub, its
		# garage or the standings never reveals an empty world without a camera.
		title.show_title()
		get_viewport().gui_release_focus()  # (the cards / standings above take the input)
	_career_mode = false
	if career.champ == null:
		career_screen.open()
		await _fade_to(0.0)
		return
	var cards: Array = _career_outcome.get("milestones", [])
	if not cards.is_empty():
		_career_outcome["milestones"] = []  # (shown once)
		music.play("music/music_menu")
		milestones.show_queue(cards)
		await _fade_to(0.0)
		if milestones.showing():
			await milestones.finished
		await _fade_to(1.0)
	var car := career.player_car if cars.owns(career.player_car) else CarCollection.OWN_CAR
	champ_screen.set_icons(car_icons(car))
	champ_screen.career = true
	champ_screen.accent = career.champ.schedule.career_accent
	if _career_outcome.has("facts"):
		_set_reaction(_career_outcome.facts)
	else:
		champ_screen.set_reaction({})
	champ_screen.warning = ""
	var stage := career.active_stage if career.in_championship() else int(_career_outcome.get("outcome", {}).get("stage", Career.FINAL_STAGE))
	champ_screen.career_stage_text = "CAREER STAGE %d OF 3" % (stage + 1)
	if cars.career_stake > 0:
		champ_screen.career_stage_text += "  -  FOR KEEPS: %s'S CAR" % RivalRoster.short_name(cars.career_stake).to_upper()
	music.play("music/music_menu")
	champ_screen.show_standings(career.champ, _career_outcome.get("reward", ""), _career_outcome.get("reward_car", null))
	await _fade_to(0.0)


## SAVE & EXIT between rounds, or CONTINUE after a decided championship.
func _leave_career_standings() -> void:
	champ_screen.close()
	champ_screen.career = false
	var out: Dictionary = _career_outcome.get("outcome", {})
	_career_outcome = {}
	champ = null
	var decided := career.champ
	if decided != null and decided.finished():
		career.close_championship()
		if out.get("completed_now", false):
			var car := career.player_car if cars.owns(career.player_car) else CarCollection.OWN_CAR
			victory.show_victory(decided, car_icons(car), career)
			return
	open_career()


## After the ending: the Hall of Fame.
func _after_victory() -> void:
	open_career()
	career_screen.show_fame()


## NEW CAREER (confirmed on the career screen): the career's progress, records
## and garage start over. A car at stake in a running career championship goes
## back to its rival (as any forfeit: no escape from Racing for Keeps).
## Achievements, won cars, the Garage Race career and lifetime titles stay.
func new_career() -> void:
	var notice := "A new career begins: the Rookie Cup awaits."
	if career.in_championship() and cars.career_stake > 0:
		last_lost = cars.career_stake
		cars.lose(last_lost)
		_remember_car_back(last_lost)
		title.refresh_car_choice()
		notice += " (The championship running for keeps was forfeited: %s took the car back.)" % RivalRoster.short_name(last_lost)
	cars.clear_career_stake()
	career.reset()
	career_garage.reset()
	open_career(notice)


# ---------------------------------------------------------------- LAN (M5.1)

func _lan_link() -> NetLink:
	if link == null:
		link = NetLink.new()
		link.name = "NetLink"
		add_child(link)
		link.peer_joined.connect(_on_lan_peer_joined)
		link.connected.connect(func() -> void: title.lan_panel.show_status("Connected. Getting the race ready..."))
		link.connection_failed.connect(func() -> void:
			_connect_started = -1
			title.lan_panel.set_busy(false)
			title.lan_panel.show_status("Could not connect to %s. Check the address, that the host is waiting, and (over the internet) the host's port forwarding and firewall - see docs/NETWORK_PLAY.md." % _connect_target, true))
		link.server_closed.connect(func() -> void:
			if race == null:
				title.lan_panel.set_busy(false)
				title.lan_panel.show_status("The host closed the game.", true))
		link.message.connect(_on_lan_message)
		link.peer_left.connect(func(id: int) -> void:
			if race == null and id == _pending_peer:
				_pending_peer = 0
				title.lan_panel.show_status("The other player left before the race. Still waiting for a player..."))
	return link


## Hosts a LAN race and waits for the other player (title status shows the address).
func host_lan() -> Error:
	if (link != null and link.is_open()) or race != null or _starting:
		return ERR_ALREADY_IN_USE  # already hosting / joining / racing: repeated presses change nothing
	var err := _lan_link().host(lan_port)
	if err != OK:
		title.lan_panel.show_status("Could not host on port %d (error %d). Is another game already hosting on this computer?" % [lan_port, err], true)
		return err
	title.lan_panel.set_busy(true)
	title.lan_panel.show_status("Hosting on UDP port %d. Local network address: %s. Over the internet, give your friend your public IP address (port forwarding needed - see docs/NETWORK_PLAY.md). Waiting for the other player..." % [lan_port, ", ".join(local_addresses())])
	return OK


## Joins the race hosted at `address`: an IPv4 address on this computer, the
## local network or the internet, optionally with ":port" (default 24680).
func join_lan(address: String) -> Error:
	if (link != null and link.is_open()) or race != null or _starting:
		return ERR_ALREADY_IN_USE
	var a := NetLink.parse_address(address, lan_port)
	if not a.ok:
		title.lan_panel.show_status(a.error, true)
		return ERR_INVALID_PARAMETER
	var err := _lan_link().join(a.ip, a.port)
	if err != OK:
		title.lan_panel.show_status("Could not start connecting (error %d)." % err, true)
		return err
	title.lan_panel.set_busy(true)
	_connect_started = Time.get_ticks_msec()
	_connect_target = "%s:%d" % [a.ip, a.port]
	title.lan_panel.show_status("Connecting to %s..." % _connect_target)
	return OK


## Connection progress on the title while a join is pending.
func _process(_delta: float) -> void:
	if _connect_started >= 0 and link != null and link.is_open() and race == null:
		var s := (Time.get_ticks_msec() - _connect_started) / 1000
		if link.peers().is_empty():
			title.lan_panel.show_status("Connecting to %s... %d s (Cancel to stop)" % [_connect_target, s])
	elif _connect_started >= 0 and race != null:
		_connect_started = -1


func close_lan() -> void:
	_pending_peer = 0
	_connect_started = -1
	if link != null:
		link.close()


## This computer's IPv4 LAN addresses (shown to the host).
static func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.is_valid_ip_address() and not ":" in a and not a.begins_with("127."):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


## Host: a computer connected. It gets WELCOME (version + the host's track)
## and must answer HELLO with the same version within HELLO_TIMEOUT seconds;
## only then does the session start. Anyone joining a race in progress (or a
## second visitor while one is being greeted) is refused.
func _on_lan_peer_joined(peer_id: int) -> void:
	if race != null or _starting or _pending_peer != 0:
		_refuse(peer_id, "busy")
		return
	_pending_peer = peer_id
	link.send([NetRace.Msg.WELCOME, NetRace.PROTOCOL, NetRace.build_id(), {"track_variant": title.track_variant,
		"layout": title.layout_id, "night": title.night}], true, peer_id)
	title.lan_panel.show_status("Player connected - checking versions...")
	get_tree().create_timer(HELLO_TIMEOUT, true, false, true).timeout.connect(_hello_timeout.bind(peer_id))


func _hello_timeout(peer_id: int) -> void:
	if _pending_peer == peer_id and race == null and link != null:
		_pending_peer = 0
		link.disconnect_peer(peer_id)
		title.lan_panel.show_status("The other computer did not answer. Still waiting for a player...")


## Tells a peer why it cannot join, then disconnects it shortly after (so the
## message arrives first).
func _refuse(peer_id: int, reason: String) -> void:
	link.send([NetRace.Msg.REJECT, reason], true, peer_id)
	get_tree().create_timer(0.5, true, false, true).timeout.connect(link.disconnect_peer.bind(peer_id))


func _on_lan_message(from: int, msg: Array) -> void:
	if typeof(msg[0]) != TYPE_INT:
		return
	if link.is_host:
		if msg[0] != NetRace.Msg.HELLO or from != _pending_peer or race != null:
			return
		if not NetRace.valid(msg, [TYPE_INT, TYPE_STRING]) or msg[1] != NetRace.PROTOCOL or msg[2] != NetRace.build_id():
			_pending_peer = 0
			_refuse(from, "version")
			title.lan_panel.show_status("A player with a different version of HyperCars tried to join. Still waiting...")
			return
		_pending_peer = 0
		start_race(0, false, [], NetRace.new(link, NetRace.Role.HOST))
		return
	if from != 1:
		return
	match msg[0]:
		NetRace.Msg.WELCOME:
			if not NetRace.valid(msg, [TYPE_INT, TYPE_STRING, TYPE_DICTIONARY]) or msg[1] != NetRace.PROTOCOL \
					or msg[2] != NetRace.build_id():
				close_lan()
				title.lan_panel.set_busy(false)
				title.lan_panel.show_status("The host runs a different version of HyperCars (both computers need the same build).", true)
				return
			if race == null and not _starting:
				link.send([NetRace.Msg.HELLO, NetRace.PROTOCOL, NetRace.build_id()], true)
				var track: int = clampi(int(msg[3].get("track_variant", 1)), 1, TrackTheme.VARIANT_COUNT)
				var layout := str(msg[3].get("layout", DevLayouts.CLASSIC))
				if not DevLayouts.NAMES.has(layout):
					layout = DevLayouts.CLASSIC  # unknown: never guess a circuit
				start_race(0, false, [], NetRace.new(link, NetRace.Role.CLIENT), track, layout,
					msg[3].get("night", false) == true)
		NetRace.Msg.REJECT:
			var why: String = str(msg[1]) if msg.size() > 1 else ""
			close_lan()
			title.lan_panel.set_busy(false)
			title.lan_panel.show_status("The host runs a different version of HyperCars." if why == "version"
				else "The host is already racing. Try again when their race is over.", true)


func quit_game() -> void:
	await _fade_to(1.0)
	_shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


## Stops audio a few frames before quitting so no stream playback outlives the
## scene (Godot otherwise reports it at exit).
func _shutdown() -> void:
	title.stop_audio()
	if race != null:
		race.queue_free()
		race = null
	for i in 3:
		await get_tree().process_frame
	get_tree().quit()


func _fade_to(alpha: float) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.25)
	await tw.finished
	_fade.visible = alpha > 0.0
