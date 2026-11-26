extends RefCounted
## Interface juice for VoxelRacing's 2D screens: quick, small feedback that
## makes the voxel-block interface feel physical. Preload it (no class_name):
##
##   const UiJuice := preload("res://src/ui/ui_juice.gd")
##   UiJuice.button(b)                  # focus / hover pop, pressed squash, pulsing focus edge
##   UiJuice.tree(panel)                # the same for every button under a node
##   UiJuice.reveal_rows(rows)          # rows slide and fade in one after another
##   UiJuice.pulse_highlight(row, col)  # a gently breathing highlight behind a row
##   UiJuice.bounce(c) / UiJuice.pop_in(c) / UiJuice.shimmer(c)
##
## Presentation only: no sounds (each screen keeps its own move / select
## sounds) and no layout changes: only scale, modulate and drawing, and rows
## that slide always land exactly where their container put them.

const META := &"ui_juice"
const TWEEN_META := &"ui_juice_tween"
## Focus / hover pop: how much a button grows for a moment. Wide buttons grow
## less (at most POP_PIXELS in all), so the pop stays a few pixels either side.
const POP_SCALE := 1.045
const POP_PIXELS := 16.0
const POP_TIME := 0.17
## Pressed: a quick squash, then a springy release.
const SQUASH := Vector2(1.03, 0.9)

static var _shimmer_shader: Shader


## Juices one button (once; calling again does nothing).
static func button(b: BaseButton) -> BaseButton:
	if b == null or b.has_meta(META):
		return b
	b.set_meta(META, true)
	b.pivot_offset_ratio = Vector2(0.5, 0.5)
	var edge := FocusEdge.new()
	b.add_child(edge, false, Node.INTERNAL_MODE_BACK)
	b.focus_entered.connect(func() -> void:
		edge.start()
		pop(b))
	b.focus_exited.connect(edge.stop)
	b.mouse_entered.connect(func() -> void:
		if not b.has_focus() and not b.disabled:
			pop(b))
	b.button_down.connect(func() -> void: _scale_to(b, SQUASH, 0.05, Tween.TRANS_QUAD))
	b.button_up.connect(func() -> void: _scale_to(b, Vector2.ONE, 0.24, Tween.TRANS_BACK))
	b.visibility_changed.connect(func() -> void:
		if not b.is_visible_in_tree():  # a menu closed mid-press: rest at full size
			_kill(b)
			b.scale = Vector2.ONE
			edge.stop())
	return b


## Juices every button under `root` (not root's own internal children).
static func tree(root: Node) -> void:
	if root == null:
		return
	for c in root.get_children():
		if c is BaseButton:
			button(c)
		tree(c)


## A quick pop: grows a little and springs back to its size.
static func pop(c: Control, amount: float = POP_SCALE) -> void:
	if c == null or not c.is_inside_tree() or not c.is_visible_in_tree():
		return
	var s := minf(amount, 1.0 + POP_PIXELS / maxf(c.size.x, 1.0))
	var tw := _fresh_tween(c)
	tw.tween_property(c, "scale", Vector2(s, s), POP_TIME * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, POP_TIME * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A celebratory bounce (e.g. the winner's star): up to `peak` and down again
## with a little bounce, after `delay`.
static func bounce(c: Control, delay: float = 0.0, peak: float = 1.4, time: float = 0.42) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	var tw := _fresh_tween(c)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(c, "scale", Vector2(peak, peak), time * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, time * 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Pops something into view: from a small scale to full size with an overshoot.
static func pop_in(c: Control, delay: float = 0.0, from: float = 0.2, time: float = 0.42) -> void:
	if c == null:
		return
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	if not c.is_inside_tree():
		c.scale = Vector2.ONE
		return
	c.scale = Vector2(from, from)
	var tw := _fresh_tween(c)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(c, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rows (children of containers, e.g. a VBox of table rows) slide in from the
## left and fade in one after another, `step` s apart (capped after
## `max_steps` rows so long lists stay quick). The tween is bound to `host`
## (default: the first row's parent), so it ends with it.
static func reveal_rows(rows: Array, step: float = 0.04, slide: float = 26.0, delay: float = 0.0,
		host: Node = null, max_steps: int = 14) -> Tween:
	var items: Array[Control] = []
	for r in rows:
		if r is Control and is_instance_valid(r) and not (r as Node).is_queued_for_deletion():
			items.append(r)
	if items.is_empty():
		return null
	if host == null:
		host = items[0].get_parent()
	if host == null or not host.is_inside_tree():
		return null
	var tw := host.create_tween().set_parallel(true)
	for i in items.size():
		var r := items[i]
		r.modulate.a = 0.0
		var at := delay + step * mini(i, max_steps)
		tw.tween_property(r, "modulate:a", 1.0, 0.16).set_delay(at)
		if slide != 0.0:
			var slide_to := func(x: float) -> void:
				if is_instance_valid(r):
					r.position.x = x  # (container rows sit at x = 0: this ends there)
			tw.tween_method(slide_to, -slide, 0.0, 0.24).set_delay(at).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


## A highlight drawn behind `c` (fill and a 2 px rim in `color`) that breathes
## gently, for as long as `c` lives.
static func pulse_highlight(c: Control, color: Color, period: float = 1.8) -> void:
	if c == null:
		return
	var glow := {"k": 0.5}
	c.draw.connect(func() -> void:
		var k: float = glow.k
		var r := Rect2(Vector2(-6, -1), c.size + Vector2(12, 2))
		c.draw_rect(r, Color(color, 0.1 + 0.14 * k))
		var e := Color(color, 0.5 + 0.45 * k)
		c.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), e)
		c.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), e)
		c.draw_rect(Rect2(r.position.x, r.position.y + 2, 2, r.size.y - 4), e)
		c.draw_rect(Rect2(r.end.x - 2, r.position.y + 2, 2, r.size.y - 4), e))
	c.queue_redraw()
	if not c.is_inside_tree():
		return
	var set_k := func(v: float) -> void:
		glow.k = v
		c.queue_redraw()
	var tw := c.create_tween().set_loops()
	tw.tween_method(set_k, 0.0, 1.0, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(set_k, 1.0, 0.0, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A glint of light that sweeps once across `c` (left to right, slightly
## slanted) after `delay`, then removes itself.
static func shimmer(c: Control, delay: float = 0.0, time: float = 0.7, color: Color = VrStyle.YELLOW) -> void:
	if c == null or not c.is_inside_tree():
		return
	if _shimmer_shader == null:
		_shimmer_shader = Shader.new()
		_shimmer_shader.code = """
shader_type canvas_item;
render_mode blend_add;
uniform float t = -0.3;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.45, 1.0);
void fragment() {
	float x = UV.x + (0.5 - UV.y) * 0.08;
	float band = 1.0 - smoothstep(0.0, 0.07, abs(x - t));
	COLOR = vec4(tint.rgb, band * 0.6);
}
"""
	var glint := ColorRect.new()
	glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _shimmer_shader
	mat.set_shader_parameter("t", -0.3)
	mat.set_shader_parameter("tint", color.lightened(0.35))
	glint.material = mat
	c.add_child(glint)
	if not (c is Container):  # (a container lays the glint over its whole rect itself)
		glint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := glint.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mat, "shader_parameter/t", 1.3, time).from(-0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(glint.queue_free)


static func _scale_to(c: Control, target: Vector2, time: float, trans: Tween.TransitionType) -> void:
	if not c.is_inside_tree() or not c.is_visible_in_tree():
		_kill(c)
		c.scale = Vector2.ONE
		return
	var tw := _fresh_tween(c)
	tw.tween_property(c, "scale", target, time).set_trans(trans).set_ease(Tween.EASE_OUT)


static func _kill(c: Control) -> void:
	if not c.has_meta(TWEEN_META):
		return
	var old: Variant = c.get_meta(TWEEN_META)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()


## One scale tween per control: a new one replaces the running one.
static func _fresh_tween(c: Control) -> Tween:
	_kill(c)
	var tw := c.create_tween()
	c.set_meta(TWEEN_META, tw)
	return tw


## The pulsing rim around a focused button: a 2 px cream edge just outside
## its voxel block (corners notched, like the blocks), breathing while focused.
class FocusEdge extends Control:
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = false
		set_process(false)

	func start() -> void:
		_t = 0.0
		visible = true
		set_process(true)
		_process(0.0)
		queue_redraw()

	func stop() -> void:
		visible = false
		set_process(false)

	func _process(delta: float) -> void:
		_t += delta
		modulate.a = 0.3 + 0.6 * (0.5 - 0.5 * cos(_t * TAU * 0.9))

	func _draw() -> void:
		var owner_button := get_parent() as Control
		# voxel blocks carry a 4 px block shadow at the right and bottom
		var sh := 4.0 if owner_button != null and owner_button.get_theme_stylebox(&"normal") is StyleBoxTexture else 0.0
		var r := Rect2(-4, -4, size.x - sh + 8, size.y - sh + 8)
		var c := VrStyle.PAPER
		draw_rect(Rect2(r.position.x + 2, r.position.y, r.size.x - 4, 2), c)
		draw_rect(Rect2(r.position.x + 2, r.end.y - 2, r.size.x - 4, 2), c)
		draw_rect(Rect2(r.position.x, r.position.y + 2, 2, r.size.y - 4), c)
		draw_rect(Rect2(r.end.x - 2, r.position.y + 2, 2, r.size.y - 4), c)
