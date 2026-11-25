class_name AudioSettings
extends RefCounted
## Volume and mute preferences for the Master, Music, Engine, Effects and Voice buses,
## plus the DYNAMIC VEHICLE LIGHTS choice, saved to a small config file
## (user://settings.cfg by default).
## Presentation only: nothing here touches the simulation.

const BUSES: Array[String] = ["Master", "Music", "Engine", "Effects", "Voice"]
const DEFAULT_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := {"Master": 0.8, "Music": 0.6, "Engine": 0.7, "Effects": 0.8, "Voice": 0.9}

var path: String
## Linear volume 0..1 per bus.
var volume: Dictionary = {}
var muted: Dictionary = {}
## Night vehicle lights: real 2D lights (true) or the cheap glow sprites.
var vehicle_lights := true
## The player's headlight colour at night (LightingPilot.HEADLIGHT_PALETTE index; 0 = standard).
var headlight_color := 0
## Artwork Mode: false = Custom (the user's drawings where present, else the
## templates); true = Original templates (Claude's template_ graphics only).
## Applies at the next game start.
var original_artwork := false


## Where a store without an explicit path saves (tests point this at a
## throw-away file so they never touch the player's own).
static var default_path := DEFAULT_PATH


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else default_path
	for bus in BUSES:
		volume[bus] = DEFAULT_VOLUME[bus]
		muted[bus] = false


## Creates the Music, Engine, Effects and Voice buses (routed to Master) if missing.
static func ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for bus in BUSES:
		volume[bus] = clampf(float(cfg.get_value("audio", bus.to_lower() + "_volume", volume[bus])), 0.0, 1.0)
		muted[bus] = bool(cfg.get_value("audio", bus.to_lower() + "_muted", muted[bus]))
	vehicle_lights = bool(cfg.get_value("video", "dynamic_vehicle_lights", vehicle_lights))
	headlight_color = clampi(int(cfg.get_value("video", "headlight_colour", 0)), 0, LightingPilot.HEADLIGHT_PALETTE.size() - 1)
	original_artwork = String(cfg.get_value("video", "artwork_mode", "custom")) == "original"


func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep any other sections
	for bus in BUSES:
		cfg.set_value("audio", bus.to_lower() + "_volume", volume[bus])
		cfg.set_value("audio", bus.to_lower() + "_muted", muted[bus])
	cfg.set_value("video", "dynamic_vehicle_lights", vehicle_lights)
	cfg.set_value("video", "headlight_colour", headlight_color)
	cfg.set_value("video", "artwork_mode", "original" if original_artwork else "custom")
	return cfg.save(path)


func set_volume(bus: String, linear: float) -> void:
	volume[bus] = clampf(linear, 0.0, 1.0)
	apply()


func set_muted(bus: String, on: bool) -> void:
	muted[bus] = on
	apply()


## Pushes the preferences to the AudioServer.
func apply() -> void:
	ensure_buses()
	for bus in BUSES:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume[bus], 0.0001)))
		AudioServer.set_bus_mute(index, muted[bus] or volume[bus] <= 0.0)
