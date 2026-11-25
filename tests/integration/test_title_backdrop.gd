extends GutTest
## Title backdrop (Stabilization 2026-11-22): the player's parked car is the car
## chosen for racing (its own car, or a won rival car in its original colours),
## drawn by the same CarArt picture as every other screen; a rival whose car
## the player owns parks the junker; changing the CAR choice updates it at once.

const GAME_SCENE := preload("res://src/main/game.tscn")
const CARS := "user://test_run/title_backdrop_cars.cfg"

var game: Node


func before_each() -> void:
	CarCollection.new(CARS).clear()
	game = GAME_SCENE.instantiate()
	game.achievements_path = "user://test_run/title_backdrop_ach.cfg"
	game.cars_path = CARS
	add_child_autofree(game)
	await wait_physics_frames(3)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CARS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_run/title_backdrop_ach.cfg"))


## The backdrop car of a grid slot showing car image `name`.
func _parked(title: Node, name: String) -> Array:
	var tex := CarArt.icon(title.resolver, name)
	return title._backdrop.get_children().filter(func(n: Node) -> bool: return n is Sprite2D and n.texture == tex)


func test_backdrop_shows_the_chosen_car() -> void:
	var title = game.title
	var res: AssetResolver = title.resolver
	title.player_car = 0
	title._update_car_button()
	assert_eq(title._player_sprite.texture, CarArt.icon(res, AssetCatalog.CAR_PLAYER), "own car by default")
	# win Hank's car: the title is refreshed as after a championship reward
	title.cars.owned.append(4)
	title.refresh_car_choice()
	assert_eq(title._player_sprite.texture, CarArt.icon(res, AssetCatalog.CAR_PLAYER), "still the own car until chosen")
	assert_eq(_parked(title, AssetCatalog.CAR_JUNKER).size(), 1, "displaced Hank parks the junker")
	title._cycle_car()
	assert_eq(title.player_car, 4)
	assert_eq(title._player_sprite.texture, CarArt.icon(res, AssetCatalog.ai_car(4)), "the won car, original colours, body + wheels")
	assert_eq(_parked(title, AssetCatalog.ai_car(4)).size(), 1, "exactly one Hank car on the grid: the player's")
	assert_eq(_parked(title, AssetCatalog.CAR_PLAYER).size(), 0, "the own car is not shown twice")
	assert_eq(_parked(title, AssetCatalog.CAR_JUNKER).size(), 1, "Hank still in the junker")
	# rebuilding the backdrop (another environment) keeps the choice
	title._cycle_track()
	assert_eq(title._player_sprite.texture, CarArt.icon(res, AssetCatalog.ai_car(4)), "after a rebuild too")
	title._cycle_track(-1)
	title._cycle_car()
	assert_eq(title.player_car, 0)
	assert_eq(title._player_sprite.texture, CarArt.icon(res, AssetCatalog.CAR_PLAYER), "back to the own car")
	# losing the car (Racing for Keeps) falls back to the own car on the backdrop too
	title._cycle_car()
	title.cars.owned.erase(4)
	title._update_car_button()
	assert_eq(title.player_car, 0)
	assert_eq(title._player_sprite.texture, CarArt.icon(res, AssetCatalog.CAR_PLAYER))
