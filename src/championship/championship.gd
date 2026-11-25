class_name Championship
extends RefCounted
## A running championship: the player (racer 0) and the nine
## rivals score schedule points by finishing position after every round; a
## DNF scores nothing. Standings: points, then wins, then the countback of
## best results, then the last round's result. Pure logic (no scene).

const PLAYER := RaceSession.PLAYER_ID

var schedule: ChampionshipSchedule
var points := {}
## Per round: the finishing order (racer ids) and the retired ids.
var results: Array = []
var _dnfs: Array = []


func _init(p_schedule: ChampionshipSchedule) -> void:
	schedule = p_schedule
	for id in range(0, 10):
		points[id] = 0


func round_index() -> int:
	return results.size()


func finished() -> bool:
	return results.size() >= schedule.round_count()


func next_round() -> Dictionary:
	return schedule.get_round(results.size()) if not finished() else {}


## Records a finished round: order = racer ids in classification order (DNFs
## included, classified last), dnf = the retired ones (no points).
func record(order: Array, dnf: Array) -> void:
	if finished():
		return
	results.append(order.duplicate())
	_dnfs.append(dnf.duplicate())
	for k in order.size():
		var id: int = order[k]
		if not dnf.has(id):
			points[id] = points.get(id, 0) + schedule.points_for(k + 1)


## Finishing position of a racer in a round (1-based; 0 = DNF or absent).
func position_in(round_i: int, id: int) -> int:
	if _dnfs[round_i].has(id):
		return 0
	var k: int = results[round_i].find(id)
	return k + 1 if k >= 0 else 0


func wins(id: int) -> int:
	var n := 0
	for i in results.size():
		if position_in(i, id) == 1:
			n += 1
	return n


## Racer ids in championship order.
func standings() -> Array[int]:
	var ids: Array[int] = []
	for id in points:
		ids.append(id)
	ids.sort_custom(_ahead)
	return ids


func _ahead(a: int, b: int) -> bool:
	if points[a] != points[b]:
		return points[a] > points[b]
	# countback: more 1st places, then 2nd places, ...
	for pos in range(1, 11):
		var na := 0
		var nb := 0
		for i in results.size():
			if position_in(i, a) == pos:
				na += 1
			if position_in(i, b) == pos:
				nb += 1
		if na != nb:
			return na > nb
	if not results.is_empty():  # still level: the last round decides
		var la := position_in(results.size() - 1, a)
		var lb := position_in(results.size() - 1, b)
		if la != lb:
			return la != 0 and (lb == 0 or la < lb)
	return a < b


func champion() -> int:
	return standings()[0] if finished() else -1


## The grid for the next round from the last round's result, reversed (the
## winner starts last), as in normal races. The first round: the rivals in id
## order, the player last.
func next_grid() -> Array[int]:
	var grid: Array[int] = []
	if results.is_empty():
		for id in range(1, 10):
			grid.append(id)
		grid.append(PLAYER)
		return grid
	for id in results[-1]:
		grid.append(id)
	grid.reverse()
	return grid


## The rounds raced so far, for saving: [orders, retirements] (career).
func saved_rounds() -> Array:
	return [results.duplicate(true), _dnfs.duplicate(true)]


## Rebuilds a saved championship by recording its rounds again (points,
## standings and grids follow). False (and nothing restored) when the data
## does not fit this schedule: a broken or foreign save.
func restore(orders: Variant, dnfs: Variant) -> bool:
	if not (orders is Array and dnfs is Array) or orders.size() != dnfs.size() or orders.size() > schedule.round_count():
		return false
	for k in orders.size():
		var o = orders[k]
		var d = dnfs[k]
		if not (o is Array and d is Array) or o.size() != 10:
			return false
		var seen := {}
		for id in o:
			if typeof(id) != TYPE_INT and typeof(id) != TYPE_FLOAT:
				return false
			if int(id) < 0 or int(id) > 9 or seen.has(int(id)):
				return false
			seen[int(id)] = true
		for id in d:
			if not seen.has(int(id)):
				return false
	for k in orders.size():
		var order: Array = []
		for id in orders[k]:
			order.append(int(id))
		var dnf: Array = []
		for id in dnfs[k]:
			dnf.append(int(id))
		record(order, dnf)
	return true

