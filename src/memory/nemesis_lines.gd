class_name NemesisLines
extends RefCounted
## The words of a Nemesis Welcome: a short opener (reusable, said by anyone),
## the rival's reaction in brackets (a laugh, a scoff), and one written taunt
## per rival and kind of event, filled in with the remembered facts only
## (weapon, lap, circuit, gap). Personalities as approved (RivalRoster):
## Victor precise and polite, Rocco loud, Ellie quick and cheeky, Hank solid
## and smug, Maya quiet, Dante a showman, Greta exact, Finn chaotic, Nina a
## patient hunter. Short, natural, not overexplained.

const OPENERS_SMUG := ["Hey... look who's here!", "Well, well, well.", "Oh, hello again."]
const OPENERS_SORE := ["Oh. It's you.", "You again.", "Look who finally showed up."]

## Reaction per rival (1..9): [smug, sore].
const REACTIONS := {
	1: ["(a quiet chuckle)", "(adjusts the gloves)"],
	2: ["(roars with laughter)", "(snorts)"],
	3: ["(giggles)", "(scoffs)"],
	4: ["(a deep, satisfied laugh)", "(grunts)"],
	5: ["(a soft, unsettling laugh)", "(silence)"],
	6: ["(laughs for the cameras)", "(sighs dramatically)"],
	7: ["(a single dry chuckle)", "(taps a watch)"],
	8: ["(cackles)", "(shrugs)"],
	9: ["(a slow smile)", "(narrows the eyes)"],
}

## Taunts: kind -> rival -> template. {that} / {my}: the weapon ("those rear
## rockets" / "my rear rockets"); {lap}, {circuit}, {gap}.
const TAUNTS := {
	RivalMemory.TOOK_YOU_OUT: {
		1: "{My} on lap {lap}. Nothing personal - merely physics.",
		2: "Lap {lap}, {my}, and BOOM! Still makes me laugh.",
		3: "Blink and you miss it. You missed {my}.",
		4: "Still remember {that}?",
		5: "You never saw {that} coming. Nobody does.",
		6: "{Circuit}, lap {lap}, {my}. The crowd loved it.",
		7: "Lap {lap}. {My}. Exactly on schedule.",
		8: "Did I mean to do that with {my}? Does it matter?",
		9: "I waited {lap} laps for that moment. Thank you for your patience.",
	},
	RivalMemory.YOU_TOOK_ME_OUT: {
		1: "Lap {lap} at {circuit}. I have reviewed it. Twice.",
		2: "Lucky shot. That's all it was. Lucky.",
		3: "Fine. You got me once. Once.",
		4: "Nobody goes through the Wall. Don't get used to it.",
		5: "I remember {that}. I remember everything.",
		6: "{That} ruined my best angle.",
		7: "Lap {lap}. My schedule never recovered.",
		8: "{That}? Wild. I respect it. I'm still getting you back.",
		9: "You hunted me with {that}. Now I'm hunting you.",
	},
	RivalMemory.BEAT_YOU_CLOSE: {
		1: "{gap} seconds at {circuit}. A very satisfying margin.",
		2: "Second at {circuit}! Ha! So close, so slow!",
		3: "{gap} seconds. You could almost see my tail-lights.",
		4: "You were right behind me at {circuit}. That's where you stayed.",
		5: "{gap} seconds. You never saw me.",
		6: "Did you enjoy the view of my victory at {circuit}?",
		7: "{gap} seconds ahead at {circuit}. Precisely enough.",
		8: "{Circuit}! Photo finish! I didn't even know where the line was!",
		9: "{gap} seconds. Thank you for chasing so politely.",
	},
	RivalMemory.YOU_BEAT_ME_CLOSE: {
		1: "{gap} seconds at {circuit}. I intend to correct that.",
		2: "{gap} seconds! I want a rematch. Now.",
		3: "{gap} seconds. I was faster. Everyone saw it.",
		4: "You squeezed past at {circuit}. The Wall remembers.",
		5: "{gap} seconds. Next time you won't see me at all.",
		6: "The cameras were on me at {circuit}. You just crossed the line first.",
		7: "{gap} seconds. I have recalculated. It will not happen again.",
		8: "{Circuit}, {gap} seconds. Do it again, I dare you.",
		9: "{gap} seconds. Enjoy it. I'm counting.",
	},
	RivalMemory.WON_MY_CAR: {
		1: "I trust you are taking care of my car.",
		2: "Give me my car back! ...Please.",
		3: "That's my car you're driving. Scratch it and see.",
		4: "Nice car. Mine, actually.",
		5: "Enjoy my car. I'll come for it quietly.",
		6: "You look good in my car. Not as good as me.",
		7: "My car's service interval is in three races. Do not be late.",
		8: "You won my car? Ha! Take good care of it. Or don't.",
		9: "You have something of mine. I'll be collecting it.",
	},
	RivalMemory.TOOK_CAR_BACK: {
		1: "My car is back where it belongs. Thank you for warming it.",
		2: "Got my car back! Ha! Didn't even need to wash it.",
		3: "Missed me? My car didn't miss you.",
		4: "Told you. Nothing gets past the Wall. Not even my own car.",
		5: "I said I'd come for it.",
		6: "My car and I are reunited. The fans wept.",
		7: "Ownership restored on schedule.",
		8: "My car's back! Want to bet it again?",
		9: "Collected. Thank you.",
	},
}

## Weapon wording: [that ..., my ...].
const WEAPONS := {
	WeaponRules.Weapon.FRONT_MISSILE: ["those missiles", "my missiles"],
	WeaponRules.Weapon.REAR_MISSILE: ["those rear rockets", "my rear rockets"],
	WeaponRules.Weapon.HOMING_MISSILE: ["that homing missile", "my homing missile"],
	WeaponRules.Weapon.SUPER_MISSILE: ["that super missile", "my super missile"],
	WeaponRules.Weapon.MINE: ["those mines", "my mines"],
}
const COLLISION_WORDS := ["that little shove", "my bumper"]

## Voice clips already recorded that fit a smug greeting (VoiceCatalog logical
## names), per rival; everyone else greets in writing only.
const SMUG_CLIPS := {2: "voice/rocco_laughing", 9: "voice/nina_thank_you", 1: "voice/victor_clean"}


## The greeting for a remembered event: {rival, title, opener, reaction,
## taunt, smug, clip ("" = text only)}. rng picks the opener.
static func greeting(e: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rival: int = e.rival
	var smug := RivalMemory.is_smug(e.kind)
	var openers: Array = OPENERS_SMUG if smug else OPENERS_SORE
	return {"rival": rival,
		"title": "%s - %s" % [RivalRoster.short_name(rival).to_upper(), RivalRoster.nickname(rival).to_upper()],
		"opener": openers[rng.randi() % openers.size()],
		"reaction": REACTIONS[rival][0 if smug else 1],
		"taunt": taunt(e), "smug": smug,
		"clip": SMUG_CLIPS.get(rival, "") if smug else ""}


## The written taunt with the event's facts filled in.
static func taunt(e: Dictionary) -> String:
	var words: Array = WEAPONS.get(int(e.get("weapon", 0)), COLLISION_WORDS)
	var text: String = TAUNTS[e.kind][int(e.rival)]
	var circuit: String = e.get("circuit", "")
	if circuit.is_empty():
		circuit = "that race"
	var fill := {"that": words[0], "my": words[1], "lap": str(int(e.get("lap", 0))), "circuit": circuit,
		"gap": "%.1f" % float(e.get("gap", 0.0))}
	for key in fill:
		text = text.replace("{%s}" % key.capitalize(), String(fill[key]).substr(0, 1).to_upper() + String(fill[key]).substr(1))
		text = text.replace("{%s}" % key, fill[key])
	return text
