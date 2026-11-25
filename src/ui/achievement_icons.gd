extends RefCounted
## Voxel achievement icons, drawn here (no image files): one little
## pixel-art pictogram per achievement (12 x 12 "voxels"), each voxel a 3 px
## block with a lit top edge and a dark extruded side, an ink outline, on a
## chunky badge tile. Unlocked: full colour on a gold-rimmed night tile with a
## lit face. Locked: the same shape as a dark ink silhouette on a dim tile with a
## small padlock; a still-secret achievement shows a "?" instead of its
## picture. Textures are cached. Loaded with preload (no class_name).

## The badge is SIZE x SIZE pixels (shown 1:1, crisp).
const SIZE := 56
const CELL := 3
const GRID := 12

## Pictogram palette (one character per voxel; "." is empty, "C" a chequer).
const COLORS := {
	"K": Color("1a1d38"), "k": Color("2b3058"), "W": Color("fff4de"), "w": Color("d2cabf"),
	"g": Color("aab1d0"), "d": Color("5f6690"), "R": Color("e8432e"), "r": Color("a62a1f"),
	"Y": Color("f7b731"), "y": Color("c98a1c"), "O": Color("f27e2e"), "T": Color("2ec4b6"),
	"t": Color("1d8f86"), "G": Color("7bc950"), "S": Color("59c3f2"), "P": Color("f45b9b"),
	"B": Color("8e5434"), "b": Color("d49a62"), "N": Color("343b6e"),
}

const ICONS := {
	"first_flag": [  # a chequered flag
		"Y...........",
		"gCCCCC......",
		"gCCCCCCCC...",
		"gCCCCCCCCCCC",
		"gCCCCCCCCCCC",
		"gCCCCCCCCCCC",
		"gCCCCCCCCCCC",
		"g...CCCCCCCC",
		"g.......CCC.",
		"g...........",
		"g...........",
		"gg..........",
	],
	"back_row_hero": [  # up from the back row of the grid
		".....GG.....",
		"....GGGG....",
		"...GGGGGG...",
		"..GGGGGGGG..",
		".GGGGGGGGGG.",
		"....GGGG....",
		"....GGGG....",
		"....GGGG....",
		"....GGGG....",
		"W.W.YGGY.W.W",
		"WWW.YYYY.WWW",
	],
	"both_hands": [  # a steering wheel, red grips both sides
		"...gggggg...",
		"..gg....gg..",
		".g........g.",
		"RR........RR",
		"RR........RR",
		"RRwwwYYwwwRR",
		"RRwwwYYwwwRR",
		"RR...ww...RR",
		".g...ww...g.",
		"..gg.ww.gg..",
		"...gggggg...",
	],
	"not_a_scratch": [  # a spotless car with a sparkle
		"..........W.",
		".........WWW",
		"..........W.",
		"...RRRRR....",
		"..RSSRSSR...",
		".RRSSRSSRR..",
		"RRRRRRRRRRRR",
		"rRRRRRRRRRRY",
		"RRRRRRRRRRRR",
		".kgk....kgk.",
		"..k......k..",
	],
	"photo_finish": [  # a camera
		".YY..dddd...",
		"gggggggggggg",
		"ggggkkkkggRg",
		"gggkSSSSkggg",
		"ggkSWSSSSkgg",
		"ggkSSSSSSkgg",
		"ggkSSSSSSkgg",
		"gggkSSSSkggg",
		"ggggkkkkgggg",
		"dddddddddddd",
	],
	"upside_down_grid": [  # the order turned around
		"..YY....RR..",
		".YYYY...RR..",
		"YYYYYY..RR..",
		"..YY....RR..",
		"..YY....RR..",
		"..YY....RR..",
		"..YY....RR..",
		"..YY....RR..",
		"..YY....RR..",
		"..YY..RRRRRR",
		"..YY...RRRR.",
		"..YY....RR..",
	],
	"opening_salvo": [  # a front missile in flight
		"...rr.......",
		"...rrr......",
		"YOOwwwRwwRR.",
		"OYYwwwRwwRRR",
		"YOOwwwRwwRR.",
		"...rrr......",
		"...rr.......",
	],
	"rear_view_diplomacy": [  # a mine
		".....gg.....",
		".g..dddd..g.",
		"..gddddddg..",
		"..ddRRdddd..",
		"ggddRRddddgg",
		"ggddddddddgg",
		"..dddddddd..",
		"..gddddddg..",
		".g..dddd..g.",
		".....gg.....",
	],
	"two_for_one": [  # one blast, two
		"...R....R...",
		"R..RR..RR..R",
		".RROOOOOORR.",
		"..ROkkkkOR..",
		".RRYYYYkYRR.",
		"RROYkkkkYORR",
		".RRYkYYYYRR.",
		"..ROkkkkOR..",
		".RROOOOOORR.",
		"R..RR..RR..R",
		"...R....R...",
	],
	"pacifist": [  # the peace sign
		"....TTTT....",
		"..TT.TT.TT..",
		".T...TT...T.",
		".T...TT...T.",
		"T....TT....T",
		"T....TT....T",
		"T...TTTT...T",
		"T..TTTTTT..T",
		".TTT.TT.TTT.",
		".TT..TT..TT.",
		"..TT.TT.TT..",
		"....TTTT....",
	],
	"phoenix": [  # rising from the flames
		".....R......",
		".....RR.....",
		"....RRR..R..",
		"..R.RORR.R..",
		"..RRROORRR..",
		".RRROOORRRR.",
		".RROOYOOORR.",
		"RROOYYYOORRR",
		"RROYYWYYOORR",
		"RROYYWWYYORR",
		".RROYYYYORR.",
		"..RRRRRRRR..",
	],
	"own_goal": [  # a mine in your own net
		"WWWWWWWWWWWW",
		"Wd.d.d.d.d.W",
		"W.d.d.d.d.dW",
		"Wd.d.d.d.d.W",
		"W.d.d.d.d.dW",
		"Wd.d.d.d.d.W",
		"W.d.RRRR.d.W",
		"Wd.RRYRRRd.W",
		"W.dRRRRRR.dW",
		"Wd.RRRRRRd.W",
		"W.d.RRRR.d.W",
		"W..........W",
	],
	"click_click": [  # the fire button, pressed and pressed
		"..W..WW..W..",
		"...W.WW.W...",
		"............",
		"....RRRR....",
		"...RRRRRR...",
		"...rRRRRr...",
		"...rrrrrr...",
		"..gggggggg..",
		".gggggggggg.",
		".dddddddddd.",
	],
	"marathon": [  # the lap counter reads 50
		"gggggggggggg",
		"gYYYYkkYYYYg",
		"gYkkkkkYkkYg",
		"gYYYkkkYkkYg",
		"gkkkYkkYkkYg",
		"gkkkYkkYkkYg",
		"gYYYYkkYYYYg",
		"gggggggggggg",
		".dd......dd.",
	],
	"all_distances": [  # a measuring stick to the finish flag
		".......gCCCC",
		".......gCCCC",
		".......gCCCC",
		".......g....",
		"YkYkYkYkYkYk",
		"YkYYYkYYYkYY",
		"YYYYYYYYYYYY",
		"yyyyyyyyyyyy",
	],
	"iron_will": [  # a steel shield
		".dddddddddd.",
		"dgggggSSSSSd",
		"dgWgggSSSSSd",
		"dgWgggSSSSSd",
		"dggggYYSSSSd",
		"dSSSSYYggggd",
		".dSSSSggggd.",
		".dSSSSggggd.",
		"..dSSSgggd..",
		"...dSSggd...",
		"....dSgd....",
		".....dd.....",
	],
	"always_bridesmaid": [  # the silver medal, again
		".SS......SS.",
		"..SS....SS..",
		"...SS..SS...",
		"....SSSS....",
		"....gggg....",
		"..gggggggg..",
		"..ggkkkkgg..",
		".ggggggkggg.",
		".gggkkkkggg.",
		"..ggkggggg..",
		"..ggkkkkgg..",
		"....gggg....",
	],
	"so_close_mad_dog": [  # you first, Rocco second
		"........Y...",
		".......YYY..",
		"........Y...",
		"......YYYYYY",
		"......YYYkYY",
		"......YYkkYY",
		"wwwww.YYYkYY",
		"wkkkw.YYYkYY",
		"wwwkw.YYYkYY",
		"wkkkw.YYkkkY",
		"wkwww.YYYYYY",
		"wkkkw.YYYYYY",
	],
	"dog_has_its_day": [  # the Mad Dog wears the crown
		"...Y.YY.Y...",
		"...YYYYYY...",
		"BB.bbbbbb.BB",
		"BBbbbbbbbbBB",
		"BBbkbbbbkbBB",
		".BbbbbbbbbB.",
		"..bbbkkbbb..",
		"..bbwkkwbb..",
		"...bbRRbb...",
		"....bRRb....",
	],
	"the_wall_holds": [  # a brick wall
		"RRRR.RRRR.RR",
		"RRRR.RRRR.RR",
		"............",
		"RR.RRRR.RRRR",
		"RR.RRRR.RRRR",
		"............",
		"RRRR.RRRR.RR",
		"RRRR.RRRR.RR",
		"............",
		"RR.RRRR.RRRR",
		"RR.RRRR.RRRR",
	],
	"ghost_line": [  # a ghost
		"...WWWWWW...",
		"..WWWWWWWW..",
		".WWWWWWWWWW.",
		".WWkkWWkkWW.",
		".WWkkWWkkWW.",
		".WWWWWWWWWW.",
		".WWWWWWWWWW.",
		".WWWWWWWWWW.",
		".WWWWWWWWWW.",
		".WW.WWWW.WW.",
		".W...WW...W.",
	],
	"like_clockwork": [  # a clock
		"....RRRR....",
		"..RRWWWWRR..",
		".RWWWkWWWWR.",
		".RWWWkWWWWR.",
		"RWWWWkWWWWWR",
		"RWWWWkWWWWWR",
		"RWWWWkkkkWWR",
		"RWWWWWWWWWWR",
		".RWWWWWWWWR.",
		".RWWWWWWWWR.",
		"..RRWWWWRR..",
		"....RRRR....",
	],
	"wildcard_played": [  # the joker card
		"..WWWWWWWW..",
		"..WPWWWWWW..",
		"..WWWWWWWW..",
		"..WWWPPWWW..",
		"..WWWPPWWW..",
		"..WPPPPPPW..",
		"..WWPPPPWW..",
		"..WWPWWPWW..",
		"..WWWWWWWW..",
		"..WWWWWWPW..",
		"..WWWWWWWW..",
	],
	"the_hunt": [  # the crosshair
		".....RR.....",
		"...RRRRRR...",
		"..R..RR..R..",
		".R...RR...R.",
		".R........R.",
		"RRRR.RR.RRRR",
		"RRRR.RR.RRRR",
		".R........R.",
		".R...RR...R.",
		"..R..RR..R..",
		"...RRRRRR...",
		".....RR.....",
	],
	"sparrow_under_fire": [  # a flustered little bird
		"Y.Y.........",
		"Y.Y.........",
		"Y.Y...BBBB..",
		".....BBBkBB.",
		"Y.Y..BBBBBYY",
		"....BBBBBB..",
		"B..BBbbbbB..",
		"BBBBbbbbbB..",
		"..BBBbbbB...",
		"....BBBB....",
		".....Y.Y....",
	],
	"showtime": [  # a star
		".....PP.....",
		".....PP.....",
		"....PPPP....",
		"PPPPPPPPPPPP",
		".PPPPPPPPPP.",
		"..PPPPPPPP..",
		"...PPPPPP...",
		"...PPPPPP...",
		"..PPP..PPP..",
		"..PP....PP..",
		".PP......PP.",
	],
	"armchair_expert": [  # an armchair
		"...TTTTTT...",
		"..TTTTTTTT..",
		"..TTTTTTTT..",
		"..TTTTTTTT..",
		"tt.TTTTTT.tt",
		"tttSSSSSSttt",
		"tttSSSSSSttt",
		"tttttttttttt",
		"tttttttttttt",
		".B........B.",
	],
	"lead_carousel": [  # round and round
		"...TTTTT....",
		"..TTTTTTTT..",
		".TT.....TT..",
		".TT.....TT..",
		"......TTTTTT",
		"..TT...TTTT.",
		".TTTT...TT..",
		"TTTTTT......",
		"..TT.....TT.",
		"..TT.....TT.",
		"..TTTTTTTT..",
		"....TTTTT...",
	],
	"eternal_contender": [  # an hourglass
		"BBBBBBBBBBBB",
		".S........S.",
		".SYYYYYYYYS.",
		"..SYYYYYYS..",
		"...SYYYYS...",
		"....SYYS....",
		"....SYYS....",
		"...S.YY.S...",
		"..S..YY..S..",
		".S..YYYY..S.",
		".SYYYYYYYYS.",
		"BBBBBBBBBBBB",
	],
	"curse_is_broken": [  # luck turns: a golden horseshoe
		".YYY....YYY.",
		".YYY....YYY.",
		"YYyY....YyYY",
		"YYY......YYY",
		"YYyY....YyYY",
		"YYY......YYY",
		"YYyY....YyYY",
		"YYYY....YYYY",
		".YYYY..YYYY.",
		"..YYYYYYYY..",
		"...YYYYYY...",
	],
}

## A still-secret achievement.
const SECRET := [
	"...WWWWWW...",
	"..WWWWWWWW..",
	"..WWW..WWW..",
	"......WWW...",
	".....WWW....",
	".....WW.....",
	".....WW.....",
	"............",
	".....WW.....",
	".....WW.....",
]

## A small padlock (1 px per pixel) for locked badges.
const LOCK := [
	"...KKKKK...",
	"..KgggggK..",
	".KgKKKKKgK.",
	".KgK...KgK.",
	".KgK...KgK.",
	"KKKKKKKKKKK",
	"KWWWWWWWWWK",
	"KWWWKKKWWWK",
	"KwwwwKwwwwK",
	"KwwwwKwwwwK",
	"KwwwwwwwwwK",
	"KKKKKKKKKKK",
]

const INK := Color("1a1d38")
const GOLD := Color("f7b731")
## Locked silhouettes run between these two inks.
const LOCKED_DARK := Color("2a3062")
const LOCKED_LIGHT := Color("4a5494")

static var _cache := {}


## The badge for an achievement: unlocked (full colour, gold rim) or locked
## (dark silhouette with a padlock); `secret` shows "?" while locked.
static func icon(id: String, unlocked: bool, secret: bool = false) -> Texture2D:
	var key := "%s|%s|%s" % [id, unlocked, secret and not unlocked]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(image(id, unlocked, secret))
	_cache[key] = tex
	return tex


static func image(id: String, unlocked: bool, secret: bool = false) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_tile(img, unlocked)
	var pattern: Array = SECRET if (secret and not unlocked) else ICONS.get(id, SECRET)
	var art := _pictogram(pattern, unlocked)
	img.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i.ZERO)
	if not unlocked:
		_stamp(img, LOCK, Vector2i(SIZE - 16, SIZE - 16))
	return img


## The badge tile: ink outline with clipped corners, a bevelled rim (gold when
## unlocked), an ink inner line and a night face lit from above.
static func _tile(img: Image, unlocked: bool) -> void:
	var t := SIZE - 2  # the tile; 2 px of block shadow below right
	img.fill_rect(Rect2i(2, 2, t, t), Color(0.04, 0.03, 0.1, 0.55))
	img.fill_rect(Rect2i(0, 0, t, t), INK)
	var rim := GOLD if unlocked else Color("2c3260")
	img.fill_rect(Rect2i(2, 2, t - 4, t - 4), rim)
	img.fill_rect(Rect2i(2, 2, t - 4, 2), rim.lightened(0.4))
	img.fill_rect(Rect2i(2, 4, 2, t - 8), rim.lightened(0.2))
	img.fill_rect(Rect2i(2, t - 4, t - 4, 2), rim.darkened(0.35))
	img.fill_rect(Rect2i(t - 4, 4, 2, t - 8), rim.darkened(0.2))
	img.fill_rect(Rect2i(4, 4, t - 8, t - 8), INK)
	var top := Color("434b86") if unlocked else Color("22274a")
	var bottom := Color("262b52") if unlocked else Color("1c2040")
	for y in range(5, t - 5):
		var c := top.lerp(bottom, float(y - 5) / (t - 10))
		img.fill_rect(Rect2i(5, y, t - 10, 1), c)
	for p in [Vector2i(0, 0), Vector2i(t - 1, 0), Vector2i(0, t - 1), Vector2i(t - 1, t - 1)]:
		img.set_pixelv(p, Color(0, 0, 0, 0))


## The pictogram as voxels: each a CELL px block with a dark extruded side
## (2 px down), a lit top / left edge where it is exposed, all in an ink
## outline. Locked: one dim silhouette colour.
static func _pictogram(pattern: Array, unlocked: bool) -> Image:
	var art := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	art.fill(Color(0, 0, 0, 0))
	var cells := {}
	var lo := Vector2i(GRID, GRID)
	var hi := Vector2i(-1, -1)
	for y in pattern.size():
		var row: String = pattern[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			var c: Color
			if ch == "C":
				c = COLORS.W if (x + y) % 2 == 0 else COLORS.k
			else:
				c = COLORS.get(ch, COLORS.W)
			if not unlocked:  # a two-tone ink relief: light parts stay a touch lighter
				c = LOCKED_DARK.lerp(LOCKED_LIGHT, clampf((c.get_luminance() - 0.12) / 0.7, 0.0, 1.0))
			cells[Vector2i(x, y)] = c
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if cells.is_empty():
		return art
	var w := (hi.x - lo.x + 1) * CELL
	var h := (hi.y - lo.y + 1) * CELL + 2
	var face := SIZE - 2 - 10  # the tile's face, inside rim and inner line
	var origin := Vector2i(5 + (face - w) / 2 - lo.x * CELL, 5 + (face - h) / 2 - lo.y * CELL)
	var depth := 0.5 if unlocked else 0.35
	for v in cells:  # extruded sides first...
		var p: Vector2i = origin + v * CELL
		art.fill_rect(Rect2i(p.x, p.y + 2, CELL, CELL), (cells[v] as Color).darkened(depth))
	for v in cells:  # ...then the faces, lit where exposed
		var p: Vector2i = origin + v * CELL
		var c: Color = cells[v]
		art.fill_rect(Rect2i(p, Vector2i(CELL, CELL)), c)
		var lift := 0.32 if unlocked else 0.12
		if not cells.has(v + Vector2i.UP):
			art.fill_rect(Rect2i(p, Vector2i(CELL, 1)), c.lightened(lift))
		if not cells.has(v + Vector2i.LEFT):
			art.fill_rect(Rect2i(p.x, p.y + 1, 1, CELL - 1), c.lightened(lift * 0.5))
	# the ink outline around everything
	var edge: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if art.get_pixel(x, y).a > 0.0:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + n
				if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE and art.get_pixelv(q).a > 0.0:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		art.set_pixelv(p, INK)
	return art


static func _stamp(img: Image, pattern: Array, at: Vector2i) -> void:
	for y in pattern.size():
		var row: String = pattern[y]
		for x in row.length():
			if row[x] != ".":
				img.set_pixelv(at + Vector2i(x, y), COLORS.get(row[x], INK))
