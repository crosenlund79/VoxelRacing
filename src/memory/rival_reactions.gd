class_name RivalReactions
extends RefCounted
## Result-driven rival reactions (2026-11-23): after a championship round, at
## most one rival says one short line about something that really happened in
## that round or in the standings - never invented, never about nothing.
## Most rounds produce no reaction at all (the facts below are deliberately
## notable). Shown on the championship standings with the rival's car (no
## portraits, no audio). Pure logic: the game hands in the facts.
##
## The facts (`f`): order (racer ids, classification), dnf (ids), times (id ->
## finish time, finishers only), feed (CombatStats feed of the round), before /
## after (championship points before / after the round), history (earlier
## rounds' orders), final (the championship was decided this round),
## champion (its winner, -1 none), me (the player's id).
##
## Voices as approved (RivalRoster, NemesisLines): Victor precise and polite,
## Rocco loud and arrogant, Ellie quick and cheeky, Hank stubborn and solid,
## Maya quiet, Dante a showman, Greta exact and disciplined, Finn chaotic,
## Nina a patient hunter.

const TITLE_WON := "title_won"          # the rival won the championship, the player was runner-up
const TITLE_LOST := "title_lost"        # the player won it, the rival was runner-up
const TOOK_LEAD := "took_lead"          # the rival took the championship lead from the player
const LOST_LEAD := "lost_lead"          # the player took the lead from the rival
const BEAT_CLOSE := "beat_close"        # the rival won the round, the player second, < CLOSE s
const LOST_CLOSE := "lost_close"        # the player won, the rival second, < CLOSE s
const DESTROYED_YOU := "destroyed_you"  # the rival destroyed the player 2+ times this round
const YOU_DESTROYED := "you_destroyed"  # the player destroyed the rival 2+ times this round
const ALWAYS_BEHIND := "always_behind"  # the rival finished behind the player in every round (3+)
const COMEBACK := "comeback"            # the rival won after a 7th-or-worse round
const SLUMP := "slump"                  # the last round's winner (a rival) fell to 8th or worse

## In priority order: the most significant fact speaks.
const KINDS := [TITLE_WON, TITLE_LOST, TOOK_LEAD, LOST_LEAD, BEAT_CLOSE, LOST_CLOSE, DESTROYED_YOU,
	YOU_DESTROYED, COMEBACK, SLUMP, ALWAYS_BEHIND]
const CLOSE := 0.5

const LINES := {
	TITLE_WON: {
		1: "A well-earned title. Mine, I mean. You were... a worthy footnote.",
		2: "CHAMPION! ROCCO! Say it louder!",
		3: "Title's mine. You were close enough to see it fly away.",
		4: "You pushed. The Wall held. Champion.",
		5: "The title is mine. You never really saw me take it.",
		6: "Champion! Thank you for being such a dramatic rival.",
		7: "Champion, exactly as scheduled. You ran a fine second.",
		8: "Wait, I WON? I won! Did you see that?",
		9: "I tracked that title all season. Thank you for the chase.",
	},
	TITLE_LOST: {
		1: "Second in the championship. I shall study every lap.",
		2: "Second?! This championship was rigged. REMATCH.",
		3: "Fine, champion. Enjoy it while it lasts.",
		4: "You got around the Wall. Once. For a whole season.",
		5: "Champion. I'll remember this one.",
		6: "Second is just a cliffhanger. Stay tuned.",
		7: "Second. My calculations were off by one place.",
		8: "Runner-up! Honestly, I'm amazed I got this far.",
		9: "Enjoy the trophy. The hunt starts again tomorrow.",
	},
	TOOK_LEAD: {
		1: "The championship lead. As the numbers predicted.",
		2: "MY lead now! Get used to the view of my bumper!",
		3: "Top of the table. Catch me if you can.",
		4: "I lead. Try getting past me now.",
		5: "I lead now. Quietly.",
		6: "Championship leader! The fans demanded it.",
		7: "First in the standings. Right on schedule.",
		8: "I'm leading? How did that happen? Love it.",
		9: "I've passed you in the standings. Now I'm the one ahead.",
	},
	LOST_LEAD: {
		1: "You lead the championship. A temporary arrangement.",
		2: "You stole MY lead! I want it back. NOW.",
		3: "You took the top spot. Don't get comfortable.",
		4: "Lead's yours for now. The Wall doesn't move that easily.",
		5: "You lead. I'll be right behind you. Always.",
		6: "Losing the lead? Every story needs a plot twist.",
		7: "The lead changed hands. My schedule accounts for that.",
		8: "Lost the lead? Eh, it was fun while it lasted.",
		9: "You took the lead. Now you're the one being hunted.",
	},
	BEAT_CLOSE: {
		1: "{gap} seconds. Close, but precision decides.",
		2: "Ha! {gap} seconds and you STILL lost!",
		3: "{gap} seconds. Did you enjoy my tail-lights?",
		4: "{gap} seconds behind me. That's where you belong.",
		5: "{gap} seconds. You never quite caught me.",
		6: "A {gap}-second photo finish. The crowd went wild!",
		7: "{gap} seconds. Precisely enough.",
		8: "{gap} seconds?! I nearly forgot to finish!",
		9: "{gap} seconds. I let you get close. Then I didn't.",
	},
	LOST_CLOSE: {
		1: "{gap} seconds. I shall correct that.",
		2: "{gap} seconds! I want a rematch!",
		3: "{gap} seconds. I was faster everywhere else.",
		4: "{gap} seconds. You squeezed past. Once.",
		5: "{gap} seconds. Next time you won't see me coming.",
		6: "{gap} seconds - you stole my finale!",
		7: "{gap} seconds. Recalculating.",
		8: "{gap} seconds? Wild! Do it again, I dare you.",
		9: "{gap} seconds. I'm still right behind you.",
	},
	DESTROYED_YOU: {
		1: "{n} times. Shall I draw you a diagram?",
		2: "{n} times! Rocco wins the whole road!",
		3: "{n} times. Too slow to dodge, too slow to catch.",
		4: "{n} times you hit the Wall. Learning yet?",
		5: "{n} times. You never saw any of them coming.",
		6: "{n} explosions for the highlight reel!",
		7: "{n} hits. Each exactly on time.",
		8: "{n} times? Was that all me? Brilliant.",
		9: "{n} times. You were marked from the start.",
	},
	YOU_DESTROYED: {
		1: "{n} times. A crude method, but I note its effect.",
		2: "{n} times?! You're on my list. The BIG list.",
		3: "{n} times. Okay, now it's personal.",
		4: "{n} times. The Wall gets back up. Every time.",
		5: "{n} times. I'll remember every one.",
		6: "{n} times - and on camera! The indignity!",
		7: "{n} times. That was not in my schedule.",
		8: "{n} times? Ha! I mean... ow.",
		9: "{n} times. Now the hunt is personal.",
	},
	COMEBACK: {
		1: "A poor round, then a win. Analysis pays.",
		2: "Told you! Nobody keeps Rocco down!",
		3: "Bounced right back. Light as a feather.",
		4: "Knocked down. Got back up. Won.",
		5: "Nobody saw that coming. Especially you.",
		6: "The comeback! Roll the credits!",
		7: "Last round was an anomaly. This was the plan.",
		8: "From the back to the top! No idea how!",
		9: "Patience. Then the strike.",
	},
	SLUMP: {
		1: "A disappointing result. I will review the telemetry.",
		2: "That round? Didn't happen. Forget it.",
		3: "Bad day. Happens to the best birds.",
		4: "One bad round. The Wall still stands.",
		5: "I'd rather nobody saw that.",
		6: "Even stars have off nights. Don't film this.",
		7: "That was off schedule. It will not repeat.",
		8: "Well THAT went sideways. Literally.",
		9: "A missed hunt. The next one won't be.",
	},
	ALWAYS_BEHIND: {
		1: "Behind you {n} rounds in a row. A pattern I intend to break.",
		2: "{n} rounds behind you?! That ends NOW.",
		3: "{n} rounds staring at your bumper. Enough.",
		4: "{n} rounds behind. The Wall is coming for you.",
		5: "{n} rounds behind you. You'd never know I was there.",
		6: "{n} rounds as your supporting act. Time for top billing.",
		7: "{n} rounds behind. Every one logged.",
		8: "{n} rounds behind you? I hadn't noticed! ...Okay, I noticed.",
		9: "{n} rounds behind you. Patience is the hunter's weapon.",
	},
}


## One reaction for a round's facts, or {} (most rounds). avoid_rival: the
## rival who spoke last time (nobody speaks twice in a row).
## Returns {rival, kind, text}.
static func pick(f: Dictionary, avoid_rival: int = -1) -> Dictionary:
	for c in candidates(f):
		if c.rival != avoid_rival:
			return c
	return {}


## Every fact-based reaction this round, most significant first.
static func candidates(f: Dictionary) -> Array:
	var me: int = f.get("me", RaceSession.PLAYER_ID)
	var order: Array = f.get("order", [])
	var dnf: Array = f.get("dnf", [])
	var times: Dictionary = f.get("times", {})
	var out: Array = []
	if order.is_empty():
		return out
	var before: Dictionary = f.get("before", {})
	var after: Dictionary = f.get("after", {})
	# the championship decided
	if f.get("final", false):
		var champion: int = f.get("champion", -1)
		var table := _table(after)
		if champion > 0 and table.size() > 1 and table[1] == me:
			out.append(_make(TITLE_WON, champion, {}))
		elif champion == me and table.size() > 1 and table[1] != me:
			out.append(_make(TITLE_LOST, table[1], {}))
	# the lead changing hands (between the player and a rival)
	var lead_before := _leader(before)
	var lead_after := _leader(after)
	if lead_before >= 0 and lead_after >= 0 and lead_before != lead_after and not f.get("final", false):
		if lead_after != me and lead_before == me:
			out.append(_make(TOOK_LEAD, lead_after, {}))
		elif lead_after == me and lead_before != me:
			out.append(_make(LOST_LEAD, lead_before, {}))
	# a close first and second
	if order.size() >= 2 and times.has(order[0]) and times.has(order[1]) and not dnf.has(order[1]):
		var gap: float = float(times[order[1]]) - float(times[order[0]])
		if gap >= 0.0 and gap < CLOSE:
			if order[1] == me:
				out.append(_make(BEAT_CLOSE, order[0], {"gap": "%.2f" % gap}))
			elif order[0] == me:
				out.append(_make(LOST_CLOSE, order[1], {"gap": "%.2f" % gap}))
	# destructions between the player and one rival
	var hits := {}
	var taken := {}
	for e in f.get("feed", []):
		var a: int = int(e.get("attacker", -1))
		var v: int = int(e.get("victim", -1))
		var weapon_kill: bool = not e.get("tombstone", false) or int(e.get("weapon", -1)) >= 0
		if not weapon_kill or a < 0 or v < 0 or a == v:
			continue
		if v == me and a != me:
			hits[a] = int(hits.get(a, 0)) + 1
		elif a == me:
			taken[v] = int(taken.get(v, 0)) + 1
	var top_hit := _most(hits)
	if top_hit > 0 and int(hits[top_hit]) >= 2:
		out.append(_make(DESTROYED_YOU, top_hit, {"n": str(hits[top_hit])}))
	var top_taken := _most(taken)
	if top_taken > 0 and int(taken[top_taken]) >= 2:
		out.append(_make(YOU_DESTROYED, top_taken, {"n": str(taken[top_taken])}))
	# surprises against the previous round
	var history: Array = f.get("history", [])
	if not history.is_empty():
		var last: Array = history[-1]
		var winner: int = order[0]
		if winner != me and not dnf.has(winner) and last.find(winner) >= 6:
			out.append(_make(COMEBACK, winner, {}))
		var previous_winner: int = last[0] if not last.is_empty() else -1
		if previous_winner > 0 and previous_winner != me and (order.find(previous_winner) >= 7 or dnf.has(previous_winner)):
			out.append(_make(SLUMP, previous_winner, {}))
	# a rival behind the player in every round so far (3+), the best-placed one
	var rounds: Array = history.duplicate()
	rounds.append(order)
	if rounds.size() >= 3 and not dnf.has(me):
		var best := -1
		for id in _table(after):
			if id == me:
				continue
			var always := true
			for r in rounds:
				if (r as Array).find(id) < (r as Array).find(me):
					always = false
					break
			if always:
				best = id
				break
		if best > 0:
			out.append(_make(ALWAYS_BEHIND, best, {"n": str(rounds.size())}))
	return out


static func _make(kind: String, rival: int, facts: Dictionary) -> Dictionary:
	var text: String = LINES[kind].get(rival, "")
	for k in facts:
		text = text.replace("{%s}" % k, str(facts[k]))
	return {"rival": rival, "kind": kind, "text": text}


## Racer ids by points (highest first, ties by id).
static func _table(points: Dictionary) -> Array:
	var ids: Array = points.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return points[a] > points[b] or (points[a] == points[b] and a < b))
	return ids


## The sole leader on points (-1: no points yet, or a shared lead).
static func _leader(points: Dictionary) -> int:
	var t := _table(points)
	if t.size() < 2 or int(points[t[0]]) <= 0 or points[t[0]] == points[t[1]]:
		return -1
	return t[0]


static func _most(counts: Dictionary) -> int:
	var best := -1
	for id in counts:
		if best < 0 or int(counts[id]) > int(counts[best]) or (int(counts[id]) == int(counts[best]) and int(id) < best):
			best = int(id)
	return best
