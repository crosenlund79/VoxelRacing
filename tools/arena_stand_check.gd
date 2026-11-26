extends SceneTree
## Developer harness (P005): Battle Royale's Scrapyard with its grandstands
## (the menu / arena version: static voxel spectators). Starts a match from
## the title, waits for the voxel world, then parks the camera over each
## stand and saves screenshots.
## xvfb-run godot --path . -s tools/arena_stand_check.gd -- --out=/tmp/as

var _game: Node
var _f := 0
var _out := "user://as"
var _spots: Array = []
var _k := -1
var _hold := 0
var _ready_at := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_game = load("res://src/main/game.tscn").instantiate()
	_game.greetings_enabled = false
	root.add_child.call_deferred(_game)


func _physics_process(_d: float) -> bool:
	_f += 1
	if _f == 60:
		PlayerControls.set_device(PlayerControls.DEVICE_KEYBOARD)
		_game.title._show_main()
	if _f == 90:
		_game.start_battle(0)
	var b = _game.race if _game != null else null
	if b == null or b.voxel == null or not b.voxel.ready_3d:
		return _f > 20000
	if _ready_at == 0:
		_ready_at = _f
		var props: Node = b.voxel.get_node_or_null("Props")
		for n in props.get_children() if props != null else []:
			var mi := n as MeshInstance3D
			if mi != null and mi.mesh != null and mi.mesh.has_meta("grandstand"):
				var front := mi.transform.basis.z
				_spots.append(Vector2(mi.position.x, mi.position.z) / Vox.PX + Vector2(front.x, front.z) * 80.0)
		print("arena grandstands: ", _spots.size())
		b.camera.set_process(false)  # (the follow camera would pull back to the player)
		b.camera.set_physics_process(false)
	if _f - _ready_at < 120:
		return false
	if _hold <= 0:
		_k += 1
		if _k >= _spots.size():
			return true
		_hold = 40
	b.camera.global_position = _spots[_k]
	_hold -= 1
	if _hold == 1:
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_out, _k])
		print("saved ", _k)
	return _f > 20000
