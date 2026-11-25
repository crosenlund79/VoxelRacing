class_name DebrisField
extends RefCounted
## VoxelRacing (P003): wreckage on the road costs grip. Wrecks and bodywork
## knocked off cars leave debris on a coarse grid; a car on a littered cell
## slides more (CarModel.grip_scale), fairly for everyone, and its tyres sweep
## the cell, pushing some of the debris along, so a wreck site clears over the
## following laps. Deterministic (sim data only); the voxel pieces you see are
## the presentation of the same events. Tune with the constants below.

const CELL := 40.0
## Grip lost per unit of debris under the car, and the most it can take.
const STRENGTH := 0.6
const MAX_LOSS := 0.5
## A wreck's debris and spread (px); bodywork per share of condition lost.
const WRECK_AMOUNT := 6.0
const WRECK_RADIUS := 85.0
const DAMAGE_AMOUNT := 3.0
const DAMAGE_RADIUS := 40.0
## Share of a cell's debris a car at 300 px/s sweeps away per second (half of
## it lands one cell further on).
const SWEEP := 1.1
const CELL_MAX := 2.5

var cells := {}


func clear() -> void:
	cells.clear()


func _key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func deposit(p: Vector2, amount: float, radius: float) -> void:
	if amount <= 0.0:
		return
	var reach := int(ceil(radius / CELL))
	var c0 := _key(p)
	var spots: Array = []
	var total := 0.0
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var k := c0 + Vector2i(dx, dy)
			var d := ((Vector2(k) + Vector2(0.5, 0.5)) * CELL).distance_to(p)
			if d > radius + CELL * 0.5:
				continue
			var w := 1.0 - clampf(d / (radius + CELL), 0.0, 1.0)
			spots.append([k, w])
			total += w
	if total <= 0.0:
		return
	for s in spots:
		cells[s[0]] = minf(CELL_MAX, float(cells.get(s[0], 0.0)) + amount * float(s[1]) / total)


func density_at(p: Vector2) -> float:
	return float(cells.get(_key(p), 0.0))


## Grip multiplier for a car at p (1.0 on a clean road).
func grip_scale(p: Vector2) -> float:
	return 1.0 - minf(MAX_LOSS, density_at(p) * STRENGTH)


## A car rolling over p at vel scatters some of the cell's debris.
func sweep(p: Vector2, vel: Vector2, dt: float) -> void:
	var k := _key(p)
	if not cells.has(k):
		return
	var speed := vel.length()
	if speed < 20.0:
		return
	var amount: float = cells[k]
	var moved := amount * clampf(SWEEP * dt * speed / 300.0, 0.0, 1.0)
	amount -= moved
	if amount < 0.02:
		cells.erase(k)
	else:
		cells[k] = amount
	var k2 := _key(p + vel.normalized() * CELL)
	if k2 != k and moved > 0.01:
		cells[k2] = minf(CELL_MAX, float(cells.get(k2, 0.0)) + moved * 0.5)


func total() -> float:
	var t := 0.0
	for k in cells:
		t += float(cells[k])
	return t
