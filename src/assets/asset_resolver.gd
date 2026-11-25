class_name AssetResolver
extends RefCounted
## Single entry point for replaceable graphics and audio (contract: assets/README.md).
##
## A logical name such as "cars/body_player" resolves to:
##   1. user override  <override_root>/graphics/cars/body_player.png
##   2. the user's packaged artwork  res://assets/graphics/cars/body_player.png
##      (the user's own drawing added to the project under the plain name:
##      it replaces Claude's template in the packaged game)
##   3. packaged fallback  res://assets/graphics/cars/template_body_player.png
## Artwork Mode "Original templates" (templates_only) skips 1 and 2 for graphics.
## Legacy names (the flattened cars "cars/car_*", AssetCatalog.is_legacy) have
## no template: they exist only as the user's own drawings, else resolve to null.
## Audio works the same way under <override_root>/audio/ (OGG Vorbis or WAV,
## both loadable at runtime in Godot 4.7) with fallbacks in res://assets/audio/.
## Missing or invalid overrides fall back with a warning. Results are cached for
## the session; override changes take effect after a game restart.

const GRAPHICS_DIR := "graphics"
const FALLBACK_ROOT := "res://assets/graphics"
## Supported override formats for graphics.
const GRAPHICS_EXTENSIONS: Array[String] = ["png"]
const AUDIO_DIR := "audio"
const AUDIO_FALLBACK_ROOT := "res://assets/audio"
## Supported override formats for audio, in lookup order.
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]

var override_root: String
## Tests only: the override folder every resolver created without an explicit
## root uses ("" = the normal custom/ folder). Lets a test give a whole race
## scene scratch artwork without touching the player's custom/ folder.
static var test_root := ""
## Artwork Mode (Settings): true = Claude's template_ graphics only, ignoring
## custom/ overrides and the user's packaged drawings. Read when a texture is
## first resolved (set at game start: a change applies after a restart).
static var templates_only := false
var _cache: Dictionary = {}
var _overridden: Dictionary = {}
var _audio_cache: Dictionary = {}


func _init(p_override_root: String = "") -> void:
	if p_override_root.is_empty() and not test_root.is_empty():
		override_root = test_root
	elif p_override_root.is_empty():
		override_root = compute_override_root(
			OS.has_feature("editor"),
			OS.get_executable_path(),
			ProjectSettings.globalize_path("res://custom"))
	else:
		override_root = p_override_root


## Editor/development: the project's custom/ folder. Exported game: custom/ next to the executable.
static func compute_override_root(is_editor: bool, executable_path: String, project_custom_dir: String) -> String:
	if is_editor:
		return project_custom_dir
	return executable_path.get_base_dir().path_join("custom")


func get_texture(logical_name: String) -> Texture2D:
	if _cache.has(logical_name):
		return _cache[logical_name]
	var texture := _load_override(logical_name)
	if texture == null:
		texture = _load_fallback(logical_name)
	else:
		_overridden[logical_name] = true
	_cache[logical_name] = texture
	return texture


## True when a valid user override supplies this graphic (resolves it if needed).
## True when the user supplies this sound (custom/audio/..., any supported format).
func has_audio_override(logical_name: String) -> bool:
	for extension in AUDIO_EXTENSIONS:
		if FileAccess.file_exists(audio_override_path(logical_name, extension)):
			return true
	return false


func has_override(logical_name: String) -> bool:
	get_texture(logical_name)
	return _overridden.has(logical_name)


## The user's own artwork supplies this graphic: a custom/ override or the
## user's packaged drawing (layer 2), as opposed to Claude's template.
func has_user_art(logical_name: String) -> bool:
	return has_override(logical_name) or not packaged_art_path(logical_name).is_empty()


## The user's packaged drawing for a logical name (layer 2), "" if none.
static func packaged_art_path(logical_name: String) -> String:
	if templates_only:
		return ""
	var path := FALLBACK_ROOT.path_join(logical_name + ".png")
	return path if ResourceLoader.exists(path) else ""


func override_path(logical_name: String, extension: String = "png") -> String:
	return override_root.path_join(GRAPHICS_DIR).path_join(logical_name + "." + extension)


static func fallback_path(logical_name: String) -> String:
	var dir := logical_name.get_base_dir()
	var file := "template_" + logical_name.get_file() + ".png"
	return FALLBACK_ROOT.path_join(dir).path_join(file) if not dir.is_empty() else FALLBACK_ROOT.path_join(file)


func _load_override(logical_name: String) -> Texture2D:
	if templates_only:
		return null
	for extension in GRAPHICS_EXTENSIONS:
		var path := override_path(logical_name, extension)
		if not FileAccess.file_exists(path):
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		var image := Image.new()
		var err := ERR_FILE_CORRUPT
		if bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
			err = image.load_png_from_buffer(bytes)
		if err != OK or image.is_empty():
			push_warning("AssetResolver: invalid override '%s' (error %d); using template." % [path, err])
			continue
		return ImageTexture.create_from_image(image)
	return null


func _load_fallback(logical_name: String) -> Texture2D:
	var packaged := packaged_art_path(logical_name)
	if not packaged.is_empty():
		return load(packaged) as Texture2D
	if AssetCatalog.is_legacy(logical_name):
		return null  # (a legacy flattened car: only ever the user's own drawing)
	var path := fallback_path(logical_name)
	if not ResourceLoader.exists(path):
		push_error("AssetResolver: missing template asset '%s'." % path)
		return null
	return load(path) as Texture2D


## Audio stream for a logical name such as "vehicles/engine_loop". When loop is
## true the stream is set to loop over its whole length (override or template).
func get_audio(logical_name: String, loop: bool = false) -> AudioStream:
	if not _audio_cache.has(logical_name):
		var stream := _load_audio_override(logical_name)
		if stream == null:
			stream = _load_audio_fallback(logical_name)
		_audio_cache[logical_name] = stream
	var result: AudioStream = _audio_cache[logical_name]
	if loop and result != null:
		set_looping(result)
	return result


## Voice recordings (VoiceCatalog): the user's override in custom/audio/voice/
## (OGG, WAV or MP3), else the packaged recording res://assets/audio/voice/<name>.mp3.
## Null (never an error) when neither exists, so a missing line is just skipped.
const VOICE_FALLBACK_ROOT := "res://assets/audio"
const VOICE_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]


func get_voice(logical_name: String) -> AudioStream:
	if _audio_cache.has(logical_name):
		return _audio_cache[logical_name]
	var stream: AudioStream = null
	for extension in VOICE_EXTENSIONS:
		var path := audio_override_path(logical_name, extension)
		if FileAccess.file_exists(path):
			stream = _stream_from_bytes(FileAccess.get_file_as_bytes(path), extension)
			if stream != null:
				break
			push_warning("AssetResolver: invalid voice override '%s'; using the packaged recording." % path)
	if stream == null:
		for extension in VOICE_EXTENSIONS:
			var packaged := VOICE_FALLBACK_ROOT.path_join(logical_name + "." + extension)
			if ResourceLoader.exists(packaged):
				stream = load(packaged) as AudioStream
				break
	_audio_cache[logical_name] = stream
	return stream


func audio_override_path(logical_name: String, extension: String) -> String:
	return override_root.path_join(AUDIO_DIR).path_join(logical_name + "." + extension)


## Packaged template for an audio name, whichever supported format it uses ("" if none).
static func audio_fallback_path(logical_name: String) -> String:
	var dir := logical_name.get_base_dir()
	for extension in AUDIO_EXTENSIONS:
		var file := "template_" + logical_name.get_file() + "." + extension
		var path := AUDIO_FALLBACK_ROOT.path_join(dir).path_join(file) if not dir.is_empty() else AUDIO_FALLBACK_ROOT.path_join(file)
		if ResourceLoader.exists(path):
			return path
	return ""


static func set_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))


func _load_audio_override(logical_name: String) -> AudioStream:
	for extension in AUDIO_EXTENSIONS:
		var path := audio_override_path(logical_name, extension)
		if not FileAccess.file_exists(path):
			continue
		var stream := _stream_from_bytes(FileAccess.get_file_as_bytes(path), extension)
		if stream == null:
			push_warning("AssetResolver: invalid audio override '%s'; using template." % path)
			continue
		return stream
	return null


## A runtime-loaded stream from file bytes (null when they are not that format or empty).
static func _stream_from_bytes(bytes: PackedByteArray, extension: String) -> AudioStream:
	var stream: AudioStream = null
	if extension == "ogg" and bytes.size() > 4 and bytes.slice(0, 4).get_string_from_ascii() == "OggS":
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	elif extension == "wav" and bytes.size() > 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and bytes.slice(8, 12).get_string_from_ascii() == "WAVE":
		stream = AudioStreamWAV.load_from_buffer(bytes)
	elif extension == "mp3" and bytes.size() > 4 and (bytes.slice(0, 3).get_string_from_ascii() == "ID3" \
			or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0)):
		stream = AudioStreamMP3.load_from_buffer(bytes)
	if stream == null or stream.get_length() <= 0.0:
		return null
	return stream


func _load_audio_fallback(logical_name: String) -> AudioStream:
	var path := audio_fallback_path(logical_name)
	if path.is_empty():
		push_error("AssetResolver: missing template audio for '%s'." % logical_name)
		return null
	return load(path) as AudioStream
