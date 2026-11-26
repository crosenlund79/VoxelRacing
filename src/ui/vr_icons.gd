extends RefCounted
## VoxelRacing's interface icons (Prototype 005, "icons first"), drawn here
## with no image files: each icon is a little pictogram on a 10 x 10 grid of
## "voxels", every voxel a small block with a lit top edge and a darker
## extruded side, an ink outline around the silhouette and a subtle drop
## shadow, in the same style as the achievement badges (achievement_icons.gd)
## but with no badge tile: the background is transparent, so the icons sit on
## any button face. Overlays (a strike bar, a red X, a reticle...) are drawn
## as separate layers with their own ink outline, so they stay readable on
## top of the picture underneath.
##
## Use: const VrIcons := preload("res://src/ui/vr_icons.gd")
##      button.icon = VrIcons.tex("settings", 24)
##      VrIcons.tex("weapons_off", 32, "dim")    # "normal" | "dim" | "disabled"
## The texture is exactly size x size; the voxel cell is a whole number of
## pixels picked from the size (18 -> 1 px, 24 -> 2, 32 -> 3, 48 -> 4,
## 64 -> 6), so show it 1:1 (or scaled with nearest filtering) to keep it
## crisp. Textures are made on first use and cached.

const GRID := 10

## One character per voxel ("." is empty, "C" a chequer of paper and ink).
const COLORS := {
	"K": Color("1a1d38"), "k": Color("2b3058"), "N": Color("343b6e"), "W": Color("fff4de"),
	"w": Color("d2cabf"), "g": Color("aab1d0"), "d": Color("5f6690"), "L": Color("e6e9f5"),
	"R": Color("e8432e"), "r": Color("a62a1f"), "Y": Color("f7b731"), "y": Color("c98a1c"),
	"O": Color("f27e2e"), "T": Color("2ec4b6"), "t": Color("1d8f86"), "G": Color("7bc950"),
	"n": Color("4f9a35"), "S": Color("59c3f2"), "s": Color("2f86b8"), "P": Color("f45b9b"),
	"p": Color("b8326f"), "B": Color("8e5434"), "b": Color("d49a62"), "c": Color("d98c4a"),
	"j": Color("9c5a2c"),
}

const INK := Color("1a1d38")
const SHADOW := Color(0.04, 0.03, 0.1, 0.5)
## Disabled icons are a grey relief between these two, at this opacity.
const GREY_DARK := Color("4b5174")
const GREY_LIGHT := Color("b9bdd0")
const DISABLED_ALPHA := 0.45

## Shared pieces used by several icons (not listed by names()).
const PARTS := {
	"missile": [  # side view, flying right
		".rr.......",
		".rrr......",
		"OWWWWRWWR.",
		"YWWWWRWWRR",
		"OWWWWRWWR.",
		".rrr......",
		".rr.......",
	],
	"strike": [  # the red "not" bar
		"RR........",
		".RR.......",
		"..RR......",
		"...RR.....",
		"....RR....",
		".....RR...",
		"......RR..",
		".......RR.",
		"........RR",
	],
	"x": [
		"RR..RR",
		".RRRR.",
		"..RR..",
		".RRRR.",
		"RR..RR",
	],
	"car": [  # side view, facing right
		"rrr...SS..",
		".r..RSSSR.",
		"RRRRRRRRRR",
		"RRRRRRRRRY",
		".kgk..kgk.",
		".kkk..kkk.",
	],
	"speaker": [
		"....g.....",
		"...gg.....",
		"..ggg.....",
		"ddggg.....",
		"ddggg.....",
		"ddggg.....",
		"ddggg.....",
		"..ggg.....",
		"...gg.....",
		"....g.....",
	],
	"cup": [
		"YYYYYYYYYY",
		"Y.YWYYYY.Y",
		"Y.YWYYYY.Y",
		"YYYYYYYYYY",
		"..YYYYYY..",
		"...YYYY...",
		"....yy....",
		"...yyyy...",
		"..BBBBBB..",
		"..BBBBBB..",
	],
	"arrow_right": [
		"....R..",
		"....RR.",
		"RRRRRRR",
		"RRRRRRR",
		"....RR.",
		"....R..",
	],
	"gear": [
		"....gg....",
		".gg.gg.gg.",
		".gggggggg.",
		"..gggggg..",
		"gggg..gggg",
		"gggg..gggg",
		"..gggggg..",
		".gggggggg.",
		".gg.gg.gg.",
		"....gg....",
	],
	"gamepad": [
		"..........",
		"..........",
		".gggggggg.",
		"ggkggggRgg",
		"gkkkggSgYg",
		"ggkggggGgg",
		"gggggggggg",
		"gggg..gggg",
		".gg....gg.",
	],
	"helmet": [  # a racing helmet, from the front
		".RRRR.",
		"RRWWRR",
		"RRRRRR",
		"RSSSSR",
		"RSSSSR",
		"RRRRRR",
		".r..r.",
	],
	"loop": [  # a clockwise looping arrow
		".....W....",
		".....WW...",
		"..WWWWWW..",
		".WWW.WW...",
		".WW..W....",
		".W......W.",
		".W......W.",
		".WW....WW.",
		".WWW..WWW.",
		"..WWWWWW..",
	],
	"bubble": [
		".WWWWWWWW.",
		"WWWWWWWWWW",
		"WWWWWWWWWW",
		"WWWWWWWWWW",
		"WWWWWWWWWW",
		"WWWWWWWWWW",
		".WWWWWWWW.",
		"..WWW.....",
		"..WW......",
		"..W.......",
	],
}

## The icons, grouped by where they are used. A value is either a list of
## rows (one layer) or {"layers": [...]} where each layer is a list of rows or
## {"icon"/"part"/"rows": ..., "dx", "dy", "flip_x", "flip_y", "map": {from: to}}.
const ICONS := {
	# ---- race settings
	"time_day": [
		"....YY....",
		".Y......Y.",
		"...OOOO...",
		"..OYYYYO..",
		"Y.OYYYYO.Y",
		"Y.OYYYYO.Y",
		"..OYYYYO..",
		"...OOOO...",
		".Y......Y.",
		"....YY....",
	],
	"time_night": [
		"..WWW.....",
		".WWW....Y.",
		"WWW....YYY",
		"WWW.....Y.",
		"WWW.......",
		"WWWW......",
		"WWWWW....W",
		".WWWWWWWWW",
		"..WWWWWWW.",
		"....WWW...",
	],
	"laps": [  # loop arrows (the lap count is printed beside it)
		"......T...",
		".TTTTTTT..",
		"TTTTTTTT..",
		"TT....T...",
		"TT........",
		"........TT",
		"...T....TT",
		"..TTTTTTTT",
		"..TTTTTTT.",
		"...T......",
	],
	"weapons_on": {"layers": [{"part": "missile", "dy": 1}]},
	"weapons_off": {"layers": [{"part": "missile", "dy": 1}, {"part": "strike"}]},
	"accel_fire": {"layers": [
		[
			"..........",
			".GGG......",
			"GGGGG.....",
			"GnnnG.....",
			"GGGGG.....",
			"GnnnG.....",
			"GGGGG.....",
			"GnnnG.....",
			".GGG......",
			"..d.......",
		],
		[
			".......W..",
			"......WWW.",
			".....WWWWW",
			"......WWW.",
			"......WWW.",
			"......WWW.",
		],
	]},
	"accel_brake": {"layers": [
		[
			"..........",
			"..........",
			"..........",
			"..........",
			"RRRRRR....",
			"RrrrrR....",
			"RRRRRR....",
			"RrrrrR....",
			"RRRRRR....",
			"..dd......",
		],
		[
			"......WWW.",
			"......WWW.",
			"......WWW.",
			".....WWWWW",
			"......WWW.",
			".......W..",
		],
	]},
	"rounds": [  # a calendar page (the count is printed beside it)
		"..g....g..",
		".RgRRRRgR.",
		".RRRRRRRR.",
		".WWWWWWWW.",
		".WdWdWdWW.",
		".WWWWWWWW.",
		".WdWdWdWW.",
		".WWWWWWWW.",
		".WdWdWWWW.",
		".wwwwwwww.",
	],
	"car": {"layers": [{"part": "car", "dy": 2}]},
	"circuit": [  # a corner of track with red-and-white kerbs and the start line
		".......RWR",
		".....WRddd",
		"....Rddddd",
		"...Wdddddd",
		"..RddddRWR",
		".WddddW...",
		".RdddR....",
		"WdddW.....",
		"RdddR.....",
		"CCCCC.....",
	],
	"environment": [
		"...GGGG...",
		"..GGGGGG..",
		"..GGGGnG..",
		"..GGGnnG..",
		"...GGGG...",
		"....BB....",
		"..nnBBnn..",
		".nnnnnnnn.",
		"nnnnnnnnnn",
		"nnnnnnnnnn",
	],
	"new_garage": [
		"..........",
		"..YYYYYY..",
		".YY....YY.",
		".......YY.",
		".YY...YYYY",
		"YYYY...YY.",
		".YY.......",
		".YY....YY.",
		"..YYYYYY..",
		"..........",
	],
	# ---- modes / menu
	"quick_race": [
		"Y.........",
		"gCCCC.....",
		"gCCCCCCCC.",
		"gCCCCCCCCC",
		"gCCCCCCCCC",
		"gCCCCCCCCC",
		"g...CCCCCC",
		"g.......C.",
		"g.........",
		"gg........",
	],
	"championship": {"layers": [{"part": "cup", "map": {"B": "R"}}]},
	"career": [  # steps up to a star
		".......Y..",
		"......YYY.",
		".....YYYYY",
		"......YYY.",
		"......Y.Y.",
		"......TTTT",
		"......TTTT",
		"...TTTTTTT",
		"...TTTTTTT",
		"TTTTTTTTTT",
	],
	"knockout": {"layers": [
		{"part": "car", "dy": 4, "map": {"R": "S", "r": "s", "S": "W", "Y": "W"}},
		{"part": "x", "dx": 4},
	]},
	"battle": [  # an explosion
		"...R....R.",
		"R..RR..RR.",
		".RROOOORR.",
		"..ROYYYOR.",
		".ROYYWYYOR",
		"RROYWWYORR",
		".ROYYYYOR.",
		"..ROOOOR..",
		".RR.RR.RR.",
		"R...R...R.",
	],
	"spectate": [
		"..........",
		"..........",
		"...WWWW...",
		".WWWSSWWW.",
		"WWWSKKSWWW",
		"WWWSKKSWWW",
		".WWWSSWWW.",
		"...WWWW...",
	],
	"multiplayer": {"layers": [
		{"part": "helmet", "map": {"R": "T", "r": "t"}},
		{"part": "helmet", "dx": 4, "dy": 3},
	]},
	"split_screen": [
		"dddddddddd",
		"dSSSSGGGGd",
		"dSSSSGGGGd",
		"dSRRSGYYGd",
		"dSSSSGGGGd",
		"dSSSSGGGGd",
		"dddddddddd",
		"....dd....",
		"..dddddd..",
	],
	"lan": [
		"...SSSS...",
		"...SSSS...",
		"....dd....",
		"....dd....",
		".dddddddd.",
		".dd....dd.",
		"SSSS..SSSS",
		"SSSS..SSSS",
	],
	"host": [
		"..SSSSSS..",
		".S......S.",
		"S..SSSS..S",
		"..S....S..",
		"....RR....",
		"....dd....",
		"...dddd...",
		"...d..d...",
		"..dd..dd..",
		".dd....dd.",
	],
	"join": {"layers": [
		[
			"....dddddd",
			"....dBBBBd",
			"....dBBBBd",
			"....dBBBBd",
			"....dBBBBd",
			"....dBBYBd",
			"....dBBBBd",
			"....dBBBBd",
			"....dBBBBd",
			"....dBBBBd",
		],
		{"part": "arrow_right", "dy": 2, "map": {"R": "G"}},
	]},
	"settings": {"layers": [{"part": "gear"}]},
	"controls": {"layers": [{"part": "gamepad"}]},
	"keyboard": [
		"..........",
		"..........",
		"dddddddddd",
		"dWdWdWdWdd",
		"ddWdWdWdWd",
		"dWdWWWWdWd",
		"dddddddddd",
	],
	"gamepad": {"layers": [{"part": "gamepad"}]},
	"achievements": [
		".RR....SS.",
		"..RR..SS..",
		"...RRSS...",
		"...YYYY...",
		"..YYYYYY..",
		".YYYyyYYY.",
		".YYyYYyYY.",
		".YYYyyYYY.",
		"..YYYYYY..",
		"...YYYY...",
	],
	"credits": [
		"kWWkkWWkkW",
		"WWkkWWkkWW",
		"d.........",
		"kWWkkWWkkW",
		"WWkkWWkkWW",
		"dddddddddd",
		"dWWWWWdddd",
		"dddddddddd",
		"dWWWdWWWdd",
		"dddddddddd",
	],
	"quit": {"layers": [
		[
			"dddddd....",
			"dBkkkd....",
			"dBBkkd....",
			"dBBkkd....",
			"dBBkkd....",
			"dBBkkd....",
			"dBBkkd....",
			"dBBkkd....",
			"dBkkkd....",
			"dddddd....",
		],
		{"part": "arrow_right", "dx": 3, "dy": 2},
	]},
	"back": [
		"....W.....",
		"...WW.....",
		"..WWW.....",
		".WWWWWWWWW",
		".WWWWWWWWW",
		"..WWW.....",
		"...WW.....",
		"....W.....",
	],
	"start": [
		".G........",
		".GGG......",
		".GGGGG....",
		".GGGGGGG..",
		".GGGGGGGGG",
		".GGGGGGGGG",
		".GGGGGGG..",
		".GGGGG....",
		".GGG......",
		".G........",
	],
	"next": [
		".WW.......",
		".WWW......",
		"..WWW.....",
		"...WWW....",
		"...WWW....",
		"..WWW.....",
		".WWW......",
		".WW.......",
	],
	"prev": {"layers": [{"icon": "next", "flip_x": true}]},
	# ---- garage / economy
	"garage": [
		"....RR....",
		"...RRRR...",
		"..RRRRRR..",
		".RRRRRRRR.",
		"RRRRRRRRRR",
		".wwwwwwww.",
		".wddddddw.",
		".wggggggw.",
		".wddddddw.",
		".wggggggw.",
	],
	"repair": [
		"......gg..",
		".....ggg..",
		".....ggggg",
		".....ggggg",
		".....gggg.",
		"....gg....",
		"...gg.....",
		"..gg......",
		".gg.......",
		"gg........",
	],
	"money": [
		"...YYYY...",
		".YYYjYYYY.",
		".YYYjjjYY.",
		"YYYjjYYYYY",
		"YYYYjjYYYY",
		"YYYYjYjYYY",
		"YYYjjjYYYY",
		".YYYjYYYY.",
		".YYYYYYYY.",
		"...YYYY...",
	],
	"upgrade": {"layers": [
		{"part": "gear", "dy": 0},
		[
			".......G..",
			"......GGG.",
			".....GGGGG",
			"......GGG.",
			"......GGG.",
			"......GGG.",
		],
	]},
	"armour": [
		".gggggggg.",
		"gTTTTttttg",
		"gTTTTttttg",
		"gTTTTttttg",
		"gTTTTttttg",
		".gTTTtttg.",
		".gTTTtttg.",
		"..gTTttg..",
		"...gTtg...",
		"....gg....",
	],
	"missile": {"layers": [{"part": "missile"}]},
	"homing": {"layers": [
		{"rows": [
			".rr.....",
			"OWWWRWR.",
			"YWWWRWRR",
			"OWWWRWR.",
			".rr.....",
		], "dy": 5},
		[
			".....RRRR.",
			"....R....R",
			"....R.RR.R",
			"....R.RR.R",
			"....R....R",
			".....RRRR.",
		],
	]},
	"super_missile": [
		".rr.......",
		".rrr......",
		"OYYYRYYR..",
		"YYYYRYYRRR",
		"YYYYRYYRRR",
		"OYYYRYYR..",
		".rrr......",
		".rr.......",
	],
	"mine": [
		"....gg....",
		".g..dd..g.",
		"..gddddg..",
		"..ddddRd..",
		"ggddddddgg",
		"ggddddddgg",
		"..dddddd..",
		"..gddddg..",
		".g..dd..g.",
		"....gg....",
	],
	"ammo": [
		".RR.RR.RR.",
		".YY.YY.YY.",
		".YY.YY.YY.",
		"nnnnnnnnnn",
		"nGGGGGGGGn",
		"nGGYYYYGGn",
		"nGGGGGGGGn",
		"nnnnnnnnnn",
	],
	"sell": [
		"..........",
		"...YYYYYYY",
		"..YYYYYYYY",
		".YYKYYYYYY",
		"YYYYYYYYYY",
		".YYYYYYYYY",
		"..YYYYYYYY",
		"...YYYYYYY",
	],
	# ---- race / replay / photo
	"replay": {"layers": [
		[
			"dWddWddWdd",
			"dddddddddd",
			"dSSSSSSSSd",
			"dSSSSSSSSd",
			"dSSSSSSSSd",
			"dSSSSSSSSd",
			"dSSSSSSSSd",
			"dddddddddd",
			"dWddWddWdd",
		],
		{"rows": [
			"..Y..Y",
			".YY.YY",
			"YYYYYY",
			".YY.YY",
			"..Y..Y",
		], "dx": 2, "dy": 2},
	]},
	"photo": [
		".YY..ddd..",
		"gggggggggg",
		"gggkkkkgRg",
		"ggkSSSSkgg",
		"ggkSWSSkgg",
		"ggkSSSSkgg",
		"gggkkkkggg",
		"dddddddddd",
	],
	"skip": [
		"W....W....",
		"WW...WW...",
		"WWW..WWW..",
		"WWWW.WWWW.",
		"WWWWWWWWWW",
		"WWWW.WWWW.",
		"WWW..WWW..",
		"WW...WW...",
		"W....W....",
	],
	"pause": [
		".WWW..WWW.",
		".WWW..WWW.",
		".WWW..WWW.",
		".WWW..WWW.",
		".WWW..WWW.",
		".WWW..WWW.",
		".WWW..WWW.",
		".WWW..WWW.",
	],
	"restart": {"layers": [{"part": "loop"}]},
	"menu": [
		"WWWWWWWWWW",
		"WWWWWWWWWW",
		"..........",
		"WWWWWWWWWW",
		"WWWWWWWWWW",
		"..........",
		"WWWWWWWWWW",
		"WWWWWWWWWW",
	],
	"stopwatch": [
		"....dd....",
		"....gg..g.",
		"..gggggggg",
		".gWWWWWWg.",
		"gWWWWRWWWg",
		"gWWWWRWWWg",
		"gWWWWKWWWg",
		"gWWWWWWWWg",
		".gWWWWWWg.",
		"..gggggg..",
	],
	"position": [
		"..........",
		"..........",
		"...YYYY...",
		"...YYKY...",
		"...YKKY...",
		"gggYYKY...",
		"gggYYKYccc",
		"gggYYYYccc",
		"gggYYYYccc",
		"gggYYYYccc",
	],
	"kills": [
		"..WWWWWW..",
		".WWWWWWWW.",
		"WWWWWWWWWW",
		"WWKKWWKKWW",
		"WWKKWWKKWW",
		"WWWWWWWWWW",
		".WWWKKWWW.",
		"..WWWWWW..",
		"..W.WW.W..",
		"..WWWWWW..",
	],
	"deaths": [  # a tombstone
		"...gggg...",
		"..gggggg..",
		"..ggdggg..",
		"..gddddg..",
		"..ggdggg..",
		"..ggdggg..",
		"..gggggg..",
		"..gggggg..",
		".nnnnnnnn.",
		"nnnnnnnnnn",
	],
	"points": [
		"....YY....",
		"....YY....",
		"...YYYY...",
		"YYYYYYYYYY",
		".YYYYYYYY.",
		"..YYYYYY..",
		"..YYYYYY..",
		".YYY..YYY.",
		".YY....YY.",
	],
	"standings": [
		"YY.WWWWWWW",
		"YY.WWWWWWW",
		"..........",
		"gg.WWWWWW.",
		"gg.WWWWWW.",
		"..........",
		"cc.WWWWW..",
		"cc.WWWWW..",
	],
	"trophy_gold": {"layers": [{"part": "cup"}]},
	"trophy_silver": {"layers": [{"part": "cup", "map": {"Y": "g", "y": "d", "W": "L"}}]},
	"trophy_bronze": {"layers": [{"part": "cup", "map": {"Y": "c", "y": "j", "W": "b"}}]},
	"camera": [
		"..........",
		"..........",
		"ggggggg..d",
		"gRgggggddd",
		"gggggggddd",
		"gggggggddd",
		"ggggggg..d",
	],
	"lights": [
		"..WWW..YYY",
		".WWWW.....",
		"WWWWW..YYY",
		"WWWWW.....",
		"WWWWW..YYY",
		".WWWW.....",
		"..WWW..YYY",
	],
	# ---- settings
	"music": [
		"...PPPPPPP",
		"...PPPPPPP",
		"...P.....P",
		"...P.....P",
		"...P.....P",
		"...P.....P",
		".PPP...PPP",
		"PPPP..PPPP",
		"PPPP..PPPP",
		".PP....PP.",
	],
	"effects": {"layers": [
		{"part": "speaker"},
		[
			"..........",
			"........S.",
			"......S..S",
			".......S.S",
			".......S.S",
			".......S.S",
			".......S.S",
			"......S..S",
			"........S.",
			"..........",
		],
	]},
	"engine": [  # a rev counter with its red line
		"...dddd...",
		".ddWWWWdd.",
		".dWWWWWRd.",
		"dWWWWWKRRd",
		"dWWWWKWWWd",
		"dWWWKWWWWd",
		"dddddddddd",
	],
	"voice": {"layers": [{"part": "bubble", "map": {"W": "T"}}, {"rows": [
		"WW.WW.WW",
		"WW.WW.WW",
	], "dx": 1, "dy": 2}]},
	"master": [  # one big loudspeaker
		"......gg..",
		".....gLg..",
		"....ggLg..",
		"dddgggLg..",
		"dddgggLg..",
		"dddgggLg..",
		"dddgggLg..",
		"....ggLg..",
		".....gLg..",
		"......gg..",
	],
	"mute": {"layers": [
		{"part": "speaker"},
		{"rows": [
			"R..R",
			".RR.",
			".RR.",
			"R..R",
		], "dx": 6, "dy": 3},
	]},
	"tooltip": {"layers": [{"part": "bubble"}, {"rows": [
		"ss",
		"..",
		"ss",
		"ss",
		"ss",
	], "dx": 4, "dy": 1}]},
	"info": [
		"...SSSS...",
		"..SSWWSS..",
		".SSSWWSSS.",
		"SSSSSSSSSS",
		"SSSSWWSSSS",
		"SSSSWWSSSS",
		"SSSSWWSSSS",
		".SSSWWSSS.",
		"..SSSSSS..",
		"...SSSS...",
	],
	"artwork": [
		"........BB",
		".......BBB",
		"......BBB.",
		".....BBB..",
		"....gg....",
		"..PPgg....",
		".PPPP.....",
		"PPPPP.....",
		"PPPP......",
		".PP.......",
	],
	"lock": [
		"...gggg...",
		"..gg..gg..",
		"..g....g..",
		"..g....g..",
		".YYYYYYYY.",
		".YYYYYYYY.",
		".YYYKKYYY.",
		".YYYKKYYY.",
		".YYYYYYYY.",
		".YYYYYYYY.",
	],
	"check": [
		"........GG",
		".......GGG",
		"......GGG.",
		"GG...GGG..",
		"GGG.GGG...",
		".GGGGG....",
		"..GGG.....",
		"...G......",
	],
	"cross": [
		"RR......RR",
		"RRR....RRR",
		".RRR..RRR.",
		"..RRRRRR..",
		"...RRRR...",
		"...RRRR...",
		"..RRRRRR..",
		".RRR..RRR.",
		"RRR....RRR",
		"RR......RR",
	],
	"delay": [
		"BBBBBBBBBB",
		".SSSSSSSS.",
		".SSYYYYSS.",
		"..SYYYYS..",
		"...SYYS...",
		"...SYYS...",
		"..SSYYSS..",
		".SSYYYYSS.",
		".SYYYYYYS.",
		"BBBBBBBBBB",
	],
	"duration": [
		"...TTTT...",
		"..TWWWWT..",
		".TWWKWWWT.",
		"TWWWKWWWWT",
		"TWWWKKKWWT",
		"TWWWWWWWWT",
		"TWWWWWWWWT",
		".TWWWWWWT.",
		"..TWWWWT..",
		"...TTTT...",
	],
}

## Shown (with a warning) for a name that is not in ICONS.
const UNKNOWN := [
	"..PPPPP...",
	".PP...PP..",
	".PP...PP..",
	"......PP..",
	".....PP...",
	"....PP....",
	"....PP....",
	"..........",
	"....PP....",
	"....PP....",
]

static var _cache := {}
static var _layer_cache := {}
static var _warned := {}


## The icon `name` as a size x size texture (cached). `state`: "normal" (full
## colour), "dim" (an unselected option) or "disabled" (greyed, see-through).
## An unknown name gives a "?" icon (and one warning).
static func tex(name: String, size: int = 24, state: String = "normal") -> Texture2D:
	var key := "%s|%d|%s" % [name, size, state]
	var cached: Texture2D = _cache.get(key)
	if cached != null:
		return cached
	var t := ImageTexture.create_from_image(image(name, size, state))
	_cache[key] = t
	return t


static func has(name: String) -> bool:
	return ICONS.has(name)


## Every icon name, grouped as in ICONS (settings, menu, garage, race, sound...).
static func names() -> PackedStringArray:
	return PackedStringArray(ICONS.keys())


## The icon as an Image (not cached), for tools and composition.
static func image(name: String, size: int = 24, state: String = "normal") -> Image:
	if not ICONS.has(name) and not _warned.has(name):
		_warned[name] = true
		push_warning("VrIcons: no icon named \"%s\"; showing \"?\"" % name)
	var layers := _layers(name)
	size = maxi(size, 8)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lo := Vector2i(GRID * 4, GRID * 4)
	var hi := Vector2i(-GRID * 4, -GRID * 4)
	for cells: Dictionary in layers:
		for v: Vector2i in cells:
			lo = Vector2i(mini(lo.x, v.x), mini(lo.y, v.y))
			hi = Vector2i(maxi(hi.x, v.x), maxi(hi.y, v.y))
	if hi.x < lo.x:
		return img
	# a whole number of pixels per voxel; the extruded side (d) hangs below the
	# face when there is room, else it is drawn inside the voxel ("inset")
	var c := maxi(1, (size - 2) / GRID)
	var d := maxi(1, c / 3)
	var w := (hi.x - lo.x + 1) * c + 2
	var h := (hi.y - lo.y + 1) * c + 2
	var raised := c < 2 or h + d <= size
	if raised:
		h += d
	var s := maxi(1, c / 3)
	var tw := w + s if w + s <= size else w
	var th := h + s if h + s <= size else h
	var origin := Vector2i((size - tw) / 2 + 1, (size - th) / 2 + 1) - lo * c
	var alpha := DISABLED_ALPHA if state == "disabled" else 1.0
	var ink := Color(INK, alpha)
	var depth := d if raised else 0
	# the drop shadow of the whole outlined silhouette
	var shade := Color(SHADOW, SHADOW.a * alpha)
	for cells: Dictionary in layers:
		for v: Vector2i in cells:
			var p := origin + v * c + Vector2i(s, s)
			img.fill_rect(Rect2i(p.x - 1, p.y, c + 2, c + depth), shade)
			img.fill_rect(Rect2i(p.x, p.y - 1, c, c + depth + 2), shade)
	for cells: Dictionary in layers:
		# the ink outline (a 4-neighbour ring around the layer)...
		for v: Vector2i in cells:
			var p := origin + v * c
			img.fill_rect(Rect2i(p.x - 1, p.y, c + 2, c + depth), ink)
			img.fill_rect(Rect2i(p.x, p.y - 1, c, c + depth + 2), ink)
		# ...the extruded sides...
		var cols := {}
		for v: Vector2i in cells:
			cols[v] = _color(cells[v], v, state, alpha)
			if raised:
				var p := origin + v * c
				img.fill_rect(Rect2i(p.x, p.y + d, c, c), (cols[v] as Color).darkened(0.5))
		# ...then the faces, lit where exposed
		for v: Vector2i in cells:
			var p := origin + v * c
			var col: Color = cols[v]
			img.fill_rect(Rect2i(p, Vector2i(c, c)), col)
			if c >= 2 and not cells.has(v + Vector2i.UP):
				img.fill_rect(Rect2i(p, Vector2i(c, 1)), col.lightened(0.32))
			if c >= 3 and not cells.has(v + Vector2i.LEFT):
				img.fill_rect(Rect2i(p.x, p.y + 1, 1, c - 1), col.lightened(0.16))
			if not raised and not cells.has(v + Vector2i.DOWN):
				img.fill_rect(Rect2i(p.x, p.y + c - d, c, d), col.darkened(0.5))
	return img


static func _color(ch: String, v: Vector2i, state: String, alpha: float) -> Color:
	var col: Color
	if ch == "C":
		col = COLORS["W"] if (v.x + v.y) % 2 == 0 else COLORS["k"]
	else:
		col = COLORS.get(ch, COLORS["W"])
	if state == "dim":
		var l := col.get_luminance()
		col = col.lerp(Color(l, l, l), 0.5).darkened(0.25)
	elif state == "disabled":
		col = GREY_DARK.lerp(GREY_LIGHT, clampf((col.get_luminance() - 0.1) / 0.75, 0.0, 1.0))
	col.a = alpha
	return col


## The icon's layers, each a Dictionary of Vector2i (grid cell) -> character.
static func _layers(name: String) -> Array:
	if _layer_cache.has(name):
		return _layer_cache[name]
	var def: Variant = ICONS.get(name, UNKNOWN)
	var layers := _resolve(def)
	_layer_cache[name] = layers
	return layers


static func _resolve(def: Variant) -> Array:
	if def is Array:
		return [_grid(def as Array)]
	var out := []
	var d: Dictionary = def
	for spec: Variant in d["layers"]:
		if spec is Array:
			out.append(_grid(spec as Array))
			continue
		var sp: Dictionary = spec
		var parts: Array
		if sp.has("icon"):
			parts = _resolve(ICONS[sp["icon"]])
		elif sp.has("part"):
			parts = _resolve(PARTS[sp["part"]])
		else:
			parts = [_grid(sp["rows"] as Array)]
		for cells: Dictionary in parts:
			out.append(_transform(cells, sp))
	return out


static func _grid(rows: Array) -> Dictionary:
	var cells := {}
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] != ".":
				cells[Vector2i(x, y)] = row[x]
	return cells


static func _transform(cells: Dictionary, sp: Dictionary) -> Dictionary:
	var out := {}
	var map: Dictionary = sp.get("map", {})
	var off := Vector2i(int(sp.get("dx", 0)), int(sp.get("dy", 0)))
	for v: Vector2i in cells:
		var q := v
		if sp.get("flip_x", false):
			q.x = GRID - 1 - q.x
		if sp.get("flip_y", false):
			q.y = GRID - 1 - q.y
		var ch: String = cells[v]
		out[q + off] = map.get(ch, ch)
	return out
