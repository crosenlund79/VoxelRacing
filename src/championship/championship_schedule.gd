class_name ChampionshipSchedule
extends Resource
## One championship: its rounds (circuit, environment, time of day, laps) and the
## points per finishing position. Configurable as resources
## (src/championship/*.tres); the game rotates through the schedules listed in
## SCHEDULES, so later championships race different combinations.

const SCHEDULES: Array[String] = [
	"res://src/championship/hypercars_cup.tres",
	"res://src/championship/night_series.tres",
]

@export var title := "HyperCars Cup"
## Per round: DevLayouts id, environment (theme variant 1..5), night, laps.
## The last round is the final.
@export var layouts: PackedStringArray = PackedStringArray()
@export var variants: PackedInt32Array = PackedInt32Array()
@export var nights: Array[bool] = []
@export var laps: PackedInt32Array = PackedInt32Array()
## Points for 1st, 2nd, ...; positions beyond the list and DNFs score nothing.
@export var points: PackedInt32Array = PackedInt32Array([25, 18, 15, 12, 10, 8, 6, 4, 2, 1])
## The rounds of the short (three-round) version, in order; it ends with the final.
@export var short_rounds: PackedInt32Array = PackedInt32Array()
## The last round is billed as the GRAND FINAL (false: just the last round).
@export var has_final := true
## Career stages (src/career/): the combat style the stage is raced with
## (WeaponRules.Style; -1 = the player's setup choice), the money paid once
## for winning it, and a one-line description for the career screen.
@export var career_style := -1
@export var career_bonus := 0
@export_multiline var blurb := ""
## Presentation identity (2026-11-23): a short tagline and an accent colour
## for the stage's cards, standings and milestones.
@export var career_tagline := ""
@export var career_accent := Color("e2b23c")

## Championship lengths offered on the setup screen.
const LENGTHS: Array[int] = [6, 3]


func round_count() -> int:
	return layouts.size()


func get_round(i: int) -> Dictionary:
	return {"layout": layouts[i], "variant": variants[i], "night": nights[i], "laps": laps[i],
		"final": has_final and i == round_count() - 1 and round_count() > 1}


## This schedule with only the short version's rounds (itself when it has no
## short version or is already that short).
func shortened() -> ChampionshipSchedule:
	if short_rounds.is_empty() or short_rounds.size() >= round_count():
		return self
	var s := ChampionshipSchedule.new()
	s.title = title
	s.points = points
	s.has_final = has_final
	for i in short_rounds:
		s.layouts.append(layouts[i])
		s.variants.append(variants[i])
		s.nights.append(nights[i])
		s.laps.append(laps[i])
	return s


## The schedule at a chosen length (6 = the whole schedule, 3 = the short one).
func with_length(rounds: int) -> ChampionshipSchedule:
	return shortened() if rounds < round_count() else self


func points_for(position: int) -> int:
	return points[position - 1] if position >= 1 and position <= points.size() else 0


## "Round 1: Kestrel Ridge - Green Valley, day, 3 laps" lines.
func describe() -> String:
	var lines := PackedStringArray([title.to_upper()])
	for i in round_count():
		var r: Dictionary = get_round(i)
		lines.append("%s %d:  %s  -  %s, %s, %d laps" % ["FINAL" if r.final else "Round", i + 1, DevLayouts.display_name(r.layout),
			TrackTheme.load_variant(r.variant).display_name, "night" if r.night else "day", r.laps])
	return "\n".join(lines)


## The schedule for the n-th championship (0-based), cycling through SCHEDULES.
static func for_run(n: int) -> ChampionshipSchedule:
	return load(SCHEDULES[posmod(n, SCHEDULES.size())])
