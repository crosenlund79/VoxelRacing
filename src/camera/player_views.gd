class_name PlayerViews
extends CanvasLayer
## M4 split-screen: one view per human driver, side by side (two 640x720
## halves of the 16:9 screen), each with its own camera following its own car.
## Every view renders the same race world (shared World2D), so the race itself
## runs once. Each player's HUD sits on its own canvas layer over its half at
## native resolution. Presentation only: it reads the race, never changes it.
##
## A PlayerView is {racer_id, container, viewport, camera, hud}; a future online
## client would simply show a single view of its own car.

const BASE := Vector2(1280, 720)
const DIVIDER := 4.0
## Camera zoom per view: a little wider than single-player to compensate for the narrower view.
const VIEW_ZOOM := Vector2(0.85, 0.85)
## Bottom of each view's info panel (top-left of the view), plus a margin:
## shared centre panels start below it.
const INFO_BOTTOM := 216.0

var views: Array = []


## racer_ids: the humans, left to right. world: the race's World2D.
func setup(racer_ids: Array[int], cars: Array[Car], world: World2D, resolver: AssetResolver) -> void:
	layer = 1
	var bg := ColorRect.new()
	bg.color = Color("1c1614")
	bg.size = BASE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var width := (BASE.x - DIVIDER * (racer_ids.size() - 1)) / racer_ids.size()
	for k in racer_ids.size():
		var id := racer_ids[k]
		var container := SubViewportContainer.new()
		container.position = Vector2((width + DIVIDER) * k, 0)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(container)
		var vp := SubViewport.new()
		vp.world_2d = world
		vp.size_2d_override = Vector2i(int(width), int(BASE.y))
		vp.size_2d_override_stretch = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(vp)
		var cam := FollowCamera.new()
		cam.target = cars[id]
		cam.zoom = VIEW_ZOOM
		vp.add_child(cam)
		cam.make_current()
		var hud := Hud.new()
		hud.name = "Hud%d" % (k + 1)
		hud.layer = 3
		hud.offset = container.position
		add_child(hud)
		hud.setup(resolver)
		hud.configure_player_view(width, "PLAYER %d" % (k + 1), k, k > 0 and k == racer_ids.size() - 1)
		views.append({"racer_id": id, "container": container, "viewport": vp, "camera": cam, "hud": hud,
			"base_size": Vector2(width, BASE.y)})
	_fit()
	get_viewport().size_changed.connect(_fit)


## Renders each view at the window's real pixel density (crisp on a
## television) while its world coordinates stay those of a 640x720 half.
func _fit() -> void:
	var scale := maxf(1.0, get_viewport().get_final_transform().get_scale().x)
	for v in views:
		var c: SubViewportContainer = v.container
		var vp: SubViewport = v.viewport
		var px := Vector2i((v.base_size * scale).round())
		vp.size = px
		c.size = Vector2(px)
		c.scale = Vector2.ONE / scale


func view_for(racer_id: int) -> Dictionary:
	for v in views:
		if v.racer_id == racer_id:
			return v
	return {}
