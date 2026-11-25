class_name ZoneView
extends Node2D
## The Battle Royale safe zone on the ground: a pulsing red ring at the
## zone's edge once it starts closing, the outside slightly reddened.
## Presentation only.

var arena: Node  # BattleRoyale (zone_radius, session)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if arena == null or arena.session == null or arena.session.elapsed < BattleRoyale.ZONE_START - 10.0:
		return
	var r: float = arena.zone_radius
	var pulse := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 300.0))
	if arena.session.elapsed < BattleRoyale.ZONE_START:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 128, Color(1.0, 0.8, 0.3, 0.5 * pulse), 6.0)  # warning: about to close
		return
	var outside := 2600.0
	var steps := 96
	for k in steps:  # a soft red band just outside the edge
		var a0 := TAU * k / steps
		var a1 := TAU * (k + 1) / steps
		draw_colored_polygon(PackedVector2Array([Vector2.from_angle(a0) * r, Vector2.from_angle(a1) * r,
			Vector2.from_angle(a1) * outside, Vector2.from_angle(a0) * outside]), Color(0.75, 0.1, 0.05, 0.16))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 160, Color(0.95, 0.2, 0.1, 0.85 * pulse), 10.0)
