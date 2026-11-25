class_name CreditsScreen
extends CanvasLayer
## CREDITS (main menu): who and what made HyperCars, from the project's own
## records - no invented names. Confirm or Back closes it.

signal closed

## The credits text. Keep it true: placeholder artwork is credited as the
## templates it is; the user's own drawings and recordings as theirs.
const TEXT := """HYPERCARS

Created, designed and directed by the HyperCars creator.

Music: "HyperCars - Theme", "HyperCars - Racing Theme" and "HyperCars - Battle Royale",
supplied by the creator. Announcer and rival voice recordings supplied by the creator.

Artwork: the creator's own drawings (championship stars, crash and tombstone icons,
grid boxes, confetti). All other graphics are replaceable template artwork painted for
the project during AI-assisted development (Claude, by Anthropic), waiting for the
creator's drawings. Sound effects and engine sounds are synthesised templates.

Programming: AI-assisted development with Claude Code, directed by the creator.

Font: Fredoka, SIL Open Font License 1.1 (assets/fonts/Fredoka_OFL.txt).
Engine: Godot Engine 4.7, MIT License (godotengine.org).
Tests: GUT - Godot Unit Test, MIT License (development only).

Mechanically inspired by Super Cars II (Gremlin Graphics, 1991, Amiga).
HyperCars is an independent fan project with its own artwork, names and characters;
it is not affiliated with or endorsed by the original game's makers.
"""

var _panel: PanelContainer
var _hint: Label


func setup(resolver: AssetResolver) -> void:
	layer = 20
	var root := Control.new()
	root.theme = HyperTheme.build(resolver)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := TextureRect.new()
	bg.texture = resolver.get_texture(AssetCatalog.GARAGE_BACKDROP)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	_panel = PanelContainer.new()
	_panel.position = Vector2(110, 40)
	_panel.custom_minimum_size = Vector2(1060, 620)
	root.add_child(_panel)
	var text := HyperTheme.label(TEXT, 19, HyperTheme.CREAM, 600)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(1020, 0)
	_panel.add_child(text)
	_hint = HyperTheme.label("", 16, HyperTheme.CREAM, 600)
	_hint.position = Vector2(110, 676)
	root.add_child(_hint)
	visible = false


func open() -> void:
	_hint.text = PlayerControls.fmt("{confirm} / {back}: back")
	visible = true


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(PlayerControls.CONFIRM) or event.is_action_pressed(PlayerControls.BACK):
		get_viewport().set_input_as_handled()
		close()
		closed.emit()
