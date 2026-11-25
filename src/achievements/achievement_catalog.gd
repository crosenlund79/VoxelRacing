class_name AchievementCatalog
extends RefCounted
## The 30 HyperCars achievements (M3.5 Stage 4): name, description and whether
## it is hidden until unlocked. The unlock rules live in AchievementTracker.
## Achievements are a HyperCars addition, not a Super Cars II feature.

const ENTRIES := [
	{"id": "first_flag", "name": "First Flag", "desc": "Win a race.", "hidden": false},
	{"id": "back_row_hero", "name": "Back Row Hero", "desc": "Win a race from the last grid slot.", "hidden": false},
	{"id": "both_hands", "name": "Both Hands on the Wheel", "desc": "Win in Fire to Accelerate and in Fire to Brake.", "hidden": false},
	{"id": "not_a_scratch", "name": "Not a Scratch", "desc": "Finish in the top three without touching a barrier or another car.", "hidden": false},
	{"id": "photo_finish", "name": "Photo Finish", "desc": "Finish within 0.10 s of the car just ahead of or behind you.", "hidden": false},
	{"id": "upside_down_grid", "name": "Upside-Down Grid", "desc": "Win two races in a row (the second from the back of the reversed grid).", "hidden": false},
	{"id": "opening_salvo", "name": "Opening Salvo", "desc": "Destroy a car with a front missile.", "hidden": false},
	{"id": "rear_view_diplomacy", "name": "Rear-View Diplomacy", "desc": "Destroy a car with one of your mines.", "hidden": false},
	{"id": "two_for_one", "name": "Two for One", "desc": "Destroy two cars with a single mine.", "hidden": true},
	{"id": "pacifist", "name": "Pacifist", "desc": "Win a race with weapons on without firing a shot.", "hidden": false},
	{"id": "phoenix", "name": "Phoenix", "desc": "Win a race after being destroyed at least twice in it.", "hidden": false},
	{"id": "own_goal", "name": "Own Goal", "desc": "\"Destroying anything close\" - including you. Be destroyed by your own mine.", "hidden": true},
	{"id": "click_click", "name": "Click. Click. Click.", "desc": "Press fire on an empty weapon five times in one race.", "hidden": true},
	{"id": "marathon", "name": "Marathon", "desc": "Finish a 50-lap race.", "hidden": false},
	{"id": "all_distances", "name": "All Distances", "desc": "Finish in the top three at 3, 7, 20 and 50 laps.", "hidden": false},
	{"id": "iron_will", "name": "Iron Will", "desc": "Finish a race of 20 laps or more with weapons on without being destroyed.", "hidden": false},
	{"id": "always_bridesmaid", "name": "Always the Bridesmaid", "desc": "See Rocco finish second in three races in a row.", "hidden": false},
	{"id": "so_close_mad_dog", "name": "So Close, Mad Dog", "desc": "Win a race with Rocco second.", "hidden": false},
	{"id": "dog_has_its_day", "name": "The Dog Has Its Day", "desc": "See Rocco win a race.", "hidden": true},
	{"id": "the_wall_holds", "name": "The Wall Holds", "desc": "See Hank defend his line 20 times in one race and finish on the podium.", "hidden": false},
	{"id": "ghost_line", "name": "Ghost Line", "desc": "See Maya win without touching another car.", "hidden": false},
	{"id": "like_clockwork", "name": "Like Clockwork", "desc": "See Greta lap within 0.15 s of herself every flying lap of a 7+ lap race without guns.", "hidden": false},
	{"id": "wildcard_played", "name": "Wildcard Played", "desc": "See Finn win from the last grid slot.", "hidden": true},
	{"id": "the_hunt", "name": "The Hunt", "desc": "See Nina win after gaining at least five places from her grid slot.", "hidden": false},
	{"id": "sparrow_under_fire", "name": "Sparrow Under Fire", "desc": "See Ellie win a race in which she got flustered at least three times.", "hidden": false},
	{"id": "showtime", "name": "Showtime", "desc": "See Dante destroy three cars in one race.", "hidden": false},
	{"id": "armchair_expert", "name": "Armchair Expert", "desc": "Watch ten complete spectator races.", "hidden": false},
	{"id": "lead_carousel", "name": "Lead Carousel", "desc": "See the lead change hands twelve times in one race.", "hidden": true},
	{"id": "eternal_contender", "name": "The Eternal Contender", "desc": "See a rival reach 25 podium finishes without a win in between.", "hidden": false},
	{"id": "curse_is_broken", "name": "The Curse Is Broken", "desc": "See a rival win after at least 50 races in a row without a win.", "hidden": false},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for e in ENTRIES:
		out.append(e.id)
	return out


static func entry(id: String) -> Dictionary:
	for e in ENTRIES:
		if e.id == id:
			return e
	return {}
