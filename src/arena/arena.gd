class_name Arena
extends Node2D
## The Scrapyard on screen and in the physics world: the biome's ground
## outside, a worn yard floor, the outer wall and the obstacles (all on the
## barrier collision layer, so cars bounce and take damage as on a circuit),
## a scrap pile of junked cars, tyre posts, grandstands and lamp spots. Built
## from the existing replaceable art (themed grass, tarmac, barrier, tyre
## stacks, grandstand, the junker).

var layout := ArenaLayout.new()
## Lamp spots for night: [position, outward direction].
var lamp_spots: Array = []
## The biome (VoxelTrack reads it like a circuit's).
var theme: TrackTheme


func build(resolver: AssetResolver, p_theme: TrackTheme) -> void:
	theme = p_theme
	var grass := resolver.get_texture(theme.asset(AssetCatalog.GRASS))
	var tarmac := resolver.get_texture(theme.asset(AssetCatalog.TARMAC))
	var wall := resolver.get_texture(theme.asset(AssetCatalog.WALL))
	var outside := _textured(grass, PackedVector2Array([Vector2(-2600, -2000), Vector2(2600, -2000), Vector2(2600, 2000), Vector2(-2600, 2000)]))
	outside.color = theme.ground_tint
	outside.name = "Ground"
	add_child(outside)
	var floor := _textured(tarmac, layout.boundary)
	floor.color = Color(0.96, 0.9, 0.8) * theme.road_tint  # a dusty, worn yard
	floor.name = "Road"
	add_child(floor)
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = Track.WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	var rim := CollisionPolygon2D.new()
	rim.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	var closed := layout.boundary.duplicate()
	closed.append(layout.boundary[0])
	rim.polygon = closed
	body.add_child(rim)
	var rim_wall := _line(layout.boundary, true, 26.0, wall)
	rim_wall.name = "BarrierRim"
	add_child(rim_wall)
	var junker := CarArt.icon(resolver, AssetCatalog.CAR_JUNKER)  # (the same junker the races draw)
	var tyres := resolver.get_texture(AssetCatalog.TYRE_STACK)
	for o in layout.polygons:
		var shape := CollisionPolygon2D.new()
		shape.polygon = o.points
		body.add_child(shape)
		match o.kind:
			"pile":
				var p := Polygon2D.new()
				p.name = "DividerPile"
				p.polygon = o.points
				p.color = Color(0.32, 0.27, 0.23)
				add_child(p)
				add_child(_line(o.points, true, 8.0, null, Color(0.18, 0.15, 0.13)))
				var rng := RandomNumberGenerator.new()
				rng.seed = 7
				for k in 7:  # junked cars piled up, at all angles
					var s := Sprite2D.new()
					s.name = "PropJunker%d" % k  # (unique: the voxel stage takes props by name)
					s.texture = junker
					s.scale = AssetCatalog.scale_for(junker, Vector2(64, 36)) * rng.randf_range(0.85, 1.05)
					s.position = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 95.0)
					s.rotation = rng.randf() * TAU
					s.modulate = Color(0.7, 0.66, 0.62).lerp(Color.WHITE, rng.randf() * 0.4)
					add_child(s)
			"block":
				var p := Polygon2D.new()
				p.name = "DividerBlock"
				p.polygon = o.points
				p.color = Color(0.68, 0.66, 0.62)
				add_child(p)
				add_child(_line(o.points, true, 5.0, null, Color(0.3, 0.28, 0.26)))
				var a: Vector2 = o.points[0]
				var b: Vector2 = o.points[1]
				var d: Vector2 = o.points[3] - o.points[0]
				for k in 5:  # hazard stripes
					var t0 := (k * 2 + 0.5) / 10.0
					var t1 := t0 + 0.08
					var stripe := Polygon2D.new()
					stripe.polygon = PackedVector2Array([a.lerp(b, t0), a.lerp(b, t1), a.lerp(b, t1) + d, a.lerp(b, t0) + d])
					stripe.color = Color(0.88, 0.7, 0.2, 0.85)
					add_child(stripe)
			"barrier":
				var pts: PackedVector2Array = o.points
				var bl := _line(PackedVector2Array([(pts[0] + pts[1]) * 0.5, (pts[2] + pts[3]) * 0.5]), false,
					pts[0].distance_to(pts[1]), wall)
				bl.name = "Barrier"
				add_child(bl)
	for t in layout.posts:
		var c := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = t.radius
		c.shape = circle
		c.position = t.centre
		body.add_child(c)
		var s := Sprite2D.new()
		s.name = "PropTyres%d" % s.get_instance_id()  # (unique: the voxel stage takes props by name)
		s.texture = tyres
		s.scale = AssetCatalog.scale_for(tyres, Vector2(t.radius * 2.2, t.radius * 2.2))
		s.position = t.centre
		add_child(s)
	var stand := resolver.get_texture(AssetCatalog.GRANDSTAND)
	var stand_n := 0
	for at in layout.stands:  # (shared with the setup screen's preview)
		var g := Sprite2D.new()
		g.name = "PropStand%d" % stand_n  # (unique: the voxel stage takes props by name)
		stand_n += 1
		g.texture = stand
		g.scale = AssetCatalog.scale_for(stand, AssetCatalog.SPECS[AssetCatalog.GRANDSTAND].display_size)
		g.position = at
		g.rotation = 0.0 if at.y < 0.0 else PI
		add_child(g)
	for spot in layout.lamps:  # on the wall, lighting the yard
		lamp_spots.append([spot[0], (spot[1] as Vector2).normalized()])


static func _textured(tex: Texture2D, points: PackedVector2Array) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = points
	p.texture = tex
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var uvs := PackedVector2Array()
	for v in points:
		uvs.append(v * (tex.get_width() / 256.0) if tex != null else v)
	p.uv = uvs
	return p


static func _line(points: PackedVector2Array, closed: bool, width: float, tex: Texture2D, color: Color = Color.WHITE) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.closed = closed
	line.width = width
	line.default_color = color
	if tex != null:
		line.texture = tex
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	return line
