class_name VoiceCatalog
extends RefCounted
## Registry of every voice recording: which speaker says it, for which race
## event, and where it comes from. Gameplay never parses file names: each line
## has a stable logical name (packaged as res://assets/audio/<logical>.mp3,
## replaceable by custom/audio/<logical>.ogg / .wav / .mp3) and the user's
## original inbox file is recorded for reference only.
##
## To add a recording: copy it to assets/audio/voice/<name>.mp3 (keep the
## original in assets/audio/_inbox/) and add one entry below. Several lines for
## the same speaker and event are variants: the Voice Director picks among them
## by weight, avoiding the one just played. Optional keys: "weight" (default
## 1.0; small = rare), "min_count" (only once this interaction has happened at
## least that many times in the race: escalating lines).

enum Event { PLAYER_DESTROYED, PLAYER_HIT_WALL, RIVAL_OVERTOOK_PLAYER, WEAPONS_HOT, PIT_VIOLATION }

## Race announcements: always said when nothing is playing (no random
## silence, and the short gap after a line does not hold them back).
const ANNOUNCEMENTS: Array[Event] = [Event.WEAPONS_HOT]

## Speaker ids: the announcer, or a rival's racer id (RivalRoster, 1..9).
const ANNOUNCER := -1
const VICTOR := 1
const ROCCO := 2
const NINA := 9

const LINES: Array[Dictionary] = [
	{"id": "announcer_smoked_you", "logical": "voice/announcer_smoked_you", "speaker": ANNOUNCER,
		"event": Event.PLAYER_DESTROYED, "source": "Announcer - Smoked you (on player killed).mp3"},
	{"id": "announcer_bumper_cars", "logical": "voice/announcer_bumper_cars", "speaker": ANNOUNCER,
		"event": Event.PLAYER_HIT_WALL, "source": "Announcer - U playing bumper cars (sometimes when player hits the walls).mp3"},
	{"id": "rocco_laughing", "logical": "voice/rocco_laughing", "speaker": ROCCO,
		"event": Event.RIVAL_OVERTOOK_PLAYER, "source": "Rocco - Laughing (if overtaken by Rocco).mp3"},
	{"id": "nina_thank_you", "logical": "voice/nina_thank_you", "speaker": NINA,
		"event": Event.RIVAL_OVERTOOK_PLAYER, "source": "the Hunter - Thank you (if overtaken by The Hunter).mp3"},
	{"id": "victor_clean", "logical": "voice/victor_clean", "speaker": VICTOR,
		"event": Event.RIVAL_OVERTOOK_PLAYER, "source": "The Professor - Clean (if overtaken by The Professor).mp3"},
	{"id": "announcer_weapons_hot", "logical": "voice/announcer_weapons_hot", "speaker": ANNOUNCER,
		"event": Event.WEAPONS_HOT, "source": "Announcer - Weapons Hot (When all drivers have passed the starting line - and weapons are unlocked).mp3"},
	{"id": "announcer_pit_violation", "logical": "voice/announcer_pit_violation", "speaker": ANNOUNCER,
		"event": Event.PIT_VIOLATION, "source": "Announcer - Pit lane violation (When a car speeds in the pit lane).mp3"},
]


## Lines a speaker has for an event (empty when none).
static func lines_for(event: Event, speaker: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in LINES:
		if line.event == event and line.speaker == speaker:
			out.append(line)
	return out


static func line(id: String) -> Dictionary:
	for l in LINES:
		if l.id == id:
			return l
	return {}


static func is_rival(speaker: int) -> bool:
	return speaker >= 1 and speaker <= 9
