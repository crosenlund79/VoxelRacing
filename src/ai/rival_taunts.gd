class_name RivalTaunts
extends RefCounted
## What each rival says (on screen, no audio) after destroying the player's
## car - written for their personalities (src/ai/personalities/). Original
## HyperCars text; three lines each, shown in turn so none repeats too soon.

const LINES := {
	1: ["Elementary. You braked a metre too late.", "A textbook lesson. Do take notes.", "Precision beats horsepower. Every time."],
	2: ["OUTTA MY ROAD!", "Ha! Scrap metal!", "Rocco wants the whole road. ALL of it."],
	3: ["Too slow - the sky's all mine!", "Light as a feather, sharp as a beak.", "Tweet tweet. Bye bye."],
	4: ["Nobody gets past the Wall.", "You hit a wall. It was me.", "Stay behind me. It's safer."],
	5: ["You never saw me coming.", "Boo.", "Gone before the smoke clears."],
	6: ["Did everyone get that on camera?", "Smile for the highlight reel!", "Another one for the fans!"],
	7: ["Right on schedule.", "Calculated. Executed.", "Tick. Tock. Boom."],
	8: ["Didn't plan that. Loved it anyway!", "Surprise!", "Oops - sorry! Not sorry."],
	9: ["Marked. Tracked. Taken.", "I've been hunting you for laps.", "There is no escape from the Hunter."],
}


static func line(rival: int, index: int) -> String:
	var lines: Array = LINES.get(rival, ["Got you!"])
	return lines[posmod(index, lines.size())]


static func count(rival: int) -> int:
	return (LINES.get(rival, ["Got you!"]) as Array).size()
