class_name CreditsScreen
extends CanvasLayer
## CREDITS (main menu): who and what made VoxelRacing, from the project's own
## records - no invented names. The live voxel logo on top, the creator, then
## one card per part of the game, and a parade of the game's own voxel cars
## driving along a chequered strip. Confirm or Back (or the BACK button)
## closes it.

signal closed

const CREATOR_CAPTION := "CREATED, DESIGNED AND DIRECTED BY"
const CREATOR := "THE VOXELRACING CREATOR"

## The credits, in three columns of cards: [heading, accent, lines]; a line is
## [text, dim]. Keep it true: placeholder artwork is credited as the templates
## it is; the user's own drawings and recordings as theirs.
const COLUMNS := [
	[
		["BUILT ON HYPERCARS", VrStyle.RED, [
			["Built on HyperCars, the creator's top-down combat racing game: its cars, rivals, circuits, rules, music and voices live on underneath every voxel.", false],
		]],
		["MUSIC & VOICES", VrStyle.TEAL, [
			["\"HyperCars - Theme\"", false],
			["\"HyperCars - Racing Theme\"", false],
			["\"HyperCars - Battle Royale\"", false],
			["Music supplied by the creator.", true],
			["Announcer and rival voice recordings supplied by the creator.", true],
		]],
	],
	[
		["VOXEL WORLD & INTERFACE", VrStyle.SKY, [
			["Voxel world, cars, damage, debris, logo and interface: generated in the engine from the HyperCars artwork during AI-assisted development (Claude, by Anthropic), directed by the creator.", false],
			["Voxel mesher adapted from the creator's SirensWentQuiet.", true],
		]],
		["FONT", VrStyle.GREEN, [
			["Pixel Operator by Jayvee Enaguas", false],
			["CC0 1.0 (assets/fonts/pixel_operator/LICENSE.txt)", true],
		]],
	],
	[
		["ENGINE & TOOLS", VrStyle.YELLOW, [
			["Engine: Godot Engine 4.7", false],
			["MIT License (godotengine.org)", true],
			["Tests: GUT - Godot Unit Test", false],
			["MIT License (development only)", true],
		]],
		["INSPIRATION & DISCLAIMER", VrStyle.PINK, [
			["Mechanically inspired by Super Cars II (Gremlin Graphics, 1991, Amiga).", false],
			["VoxelRacing is an independent fan project with its own artwork, names and characters; it is not affiliated with or endorsed by the original game's makers.", true],
		]],
	],
]

const MARGIN := 48.0
const COLUMN_WIDTH := 384.0
const GAP := 16.0
## The car parade: icon size on screen, spacing and speed.
const CAR_SIZE := Vector2(120, 68)
const CAR_SPACING := 330.0
const CAR_SPEED := 70.0
const STRIP_Y := 640.0

var _root: Control
var _hint: Label
var _back: Button
var _logo: VoxelLogo
var _parade: Control
var _cars: Array[TextureRect] = []
var _time := 0.0


func setup(resolver: AssetResolver) -> void:
	layer = 20
	var root := Control.new()
	_root = root
	root.theme = HyperTheme.build(resolver)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := TextureRect.new()
	bg.texture = VrStyle.backdrop()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var tag := PanelContainer.new()  # the page's name tag, top left
	tag.add_theme_stylebox_override("panel", VrStyle.chip(VrStyle.RED))
	tag.position = Vector2(MARGIN, 28)
	var tag_text := HyperTheme.label("CREDITS", 24, HyperTheme.CREAM, 700)
	tag.add_child(tag_text)
	root.add_child(tag)
	# the creator, under the (live) logo
	var caption := HBoxContainer.new()
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.add_theme_constant_override("separation", 14)
	caption.position = Vector2(0, 168)
	caption.size = Vector2(1280, 24)
	root.add_child(caption)
	caption.add_child(_checker_rule())
	caption.add_child(HyperTheme.label(CREATOR_CAPTION, 16, VrStyle.YELLOW, 700))
	caption.add_child(_checker_rule())
	var creator := HyperTheme.label(CREATOR, 32, HyperTheme.CREAM, 700)
	creator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	creator.position = Vector2(0, 190)
	creator.size = Vector2(1280, 40)
	root.add_child(creator)
	# the cards
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(GAP))
	cols.position = Vector2(MARGIN, 244)
	root.add_child(cols)
	for column in COLUMNS:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", int(GAP) - 4)
		v.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		cols.add_child(v)
		for section in column:
			v.add_child(_card(section[0], section[1], section[2]))
	# the parade strip along the bottom
	var strip := TextureRect.new()
	strip.texture = VrStyle.checker(148, 2, 4)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.position = Vector2(0, STRIP_Y)
	strip.size = Vector2(1280, 12)
	root.add_child(strip)
	var stripe := ColorRect.new()
	stripe.color = VrStyle.RED
	stripe.position = Vector2(0, STRIP_Y + 12)
	stripe.size = Vector2(1280, 4)
	root.add_child(stripe)
	_parade = Control.new()
	_parade.position = Vector2(0, STRIP_Y - CAR_SIZE.y + 14)
	_parade.size = Vector2(1280, CAR_SIZE.y)
	_parade.clip_contents = true
	_parade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_parade)
	_hint = HyperTheme.label("", 16, HyperTheme.CREAM_DIM, 600)
	_hint.position = Vector2(MARGIN, 674)
	root.add_child(_hint)
	_back = Button.new()
	_back.text = "BACK"
	_back.custom_minimum_size = Vector2(160, 0)
	_back.add_theme_font_size_override("font_size", 24)
	_back.pressed.connect(_close)
	root.add_child(_back)
	_back.reset_size()
	_back.position = Vector2(1280 - MARGIN - _back.size.x, 720 - _back.size.y - 10)
	visible = false
	set_process(false)


## A card: an accent chip heading, then its lines (dim ones are the fine print).
func _card(heading: String, accent: Color, lines: Array) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := VrStyle.block(VrStyle.NIGHT, 6)
	sb.modulate_color = Color(1, 1, 1, 0.94)
	sb.content_margin_left = 16
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", VrStyle.chip(accent))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var title := HyperTheme.label(heading, 16, VrStyle.INK, 700)
	title.add_theme_constant_override("outline_size", 0)
	chip.add_child(title)
	v.add_child(chip)
	var space := Control.new()
	space.custom_minimum_size = Vector2(0, 4)
	v.add_child(space)
	for line in lines:
		var l := HyperTheme.label(line[0], 16, HyperTheme.CREAM_DIM if line[1] else HyperTheme.CREAM, 500)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(COLUMN_WIDTH - 36, 0)
		v.add_child(l)
	return card


func _checker_rule() -> TextureRect:
	var r := TextureRect.new()
	r.texture = VrStyle.checker(16, 2, 4)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.custom_minimum_size = Vector2(64, 8)
	return r


func open() -> void:
	_hint.text = PlayerControls.fmt("{confirm} / {back}: back")
	visible = true
	if _logo == null:  # live only while the credits show
		_logo = VoxelLogo.new()
		_logo.size = Vector2(400, 168)
		_logo.position = Vector2((1280 - 400) * 0.5, 2)
		_root.add_child(_logo)
	_build_parade()
	_time = 0.0
	set_process(true)
	_process(0.0)
	_back.grab_focus()


func close() -> void:
	visible = false
	set_process(false)
	if _logo != null:
		_logo.queue_free()
		_logo = null


## The cars rendered at startup (VoxelIconStudio), in a line.
func _build_parade() -> void:
	for c in _cars:
		c.queue_free()
	_cars.clear()
	for logical in VoxelIconStudio.CARS:
		if not VoxelIconStudio.icons.has(logical):
			continue
		var t := TextureRect.new()
		t.texture = VoxelIconStudio.icons[logical]
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = CAR_SIZE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_parade.add_child(t)
		_cars.append(t)


func _process(delta: float) -> void:
	_time += delta
	var loop := maxf(_cars.size() * CAR_SPACING, 1280.0 + CAR_SIZE.x * 2.0)
	for i in _cars.size():
		var x := fposmod(_time * CAR_SPEED + i * CAR_SPACING, loop) - CAR_SIZE.x
		var bob := 1.0 if fmod(_time * 6.0 + i, 2.0) < 1.0 else 0.0  # a little engine judder
		_cars[i].position = Vector2(round(x), bob)


func _close() -> void:
	close()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(PlayerControls.CONFIRM) or event.is_action_pressed(PlayerControls.BACK):
		get_viewport().set_input_as_handled()
		_close()
