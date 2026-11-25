extends GutTest
## M2.2 replaceable content: audio overrides and fallbacks (OGG and WAV), every
## catalogued graphic and sound has a working template, looping, font licence.

var _root: String


func before_each() -> void:
	_root = OS.get_user_data_dir().path_join("test_audio_overrides_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root.path_join("audio/vehicles"))
	DirAccess.make_dir_recursive_absolute(_root.path_join("audio/race"))


func after_each() -> void:
	_remove_dir(_root)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


func _write(rel: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(_root.path_join(rel), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## Minimal valid 16-bit mono PCM WAV with `frames` samples of a 440 Hz tone.
func _wav_bytes(frames: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(sin(TAU * 440.0 * i / 22050.0) * 8000.0))
	var b := PackedByteArray()
	b.append_array("RIFF".to_ascii_buffer())
	var n := PackedByteArray(); n.resize(4); n.encode_u32(0, 36 + data.size()); b.append_array(n)
	b.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray(); fmt.resize(20)
	fmt.encode_u32(0, 16); fmt.encode_u16(4, 1); fmt.encode_u16(6, 1); fmt.encode_u32(8, 22050)
	fmt.encode_u32(12, 22050 * 2); fmt.encode_u16(16, 2); fmt.encode_u16(18, 16)
	b.append_array(fmt)
	b.append_array("data".to_ascii_buffer())
	var d := PackedByteArray(); d.resize(4); d.encode_u32(0, data.size()); b.append_array(d)
	b.append_array(data)
	return b


func test_every_catalogued_sound_has_a_playable_template() -> void:
	var r := AssetResolver.new(_root)
	for logical in AssetCatalog.AUDIO:
		var path := AssetResolver.audio_fallback_path(logical)
		assert_false(path.is_empty(), logical)
		assert_true(path.get_file().begins_with("template_"), logical)
		var stream := r.get_audio(logical)
		assert_not_null(stream, logical)
		if stream != null:
			assert_gt(stream.get_length(), 0.04, logical + " is not empty")


func test_templates_are_not_silent() -> void:
	# Decode the WAV templates and check they carry signal.
	for logical in ["vehicles/engine_loop", "vehicles/engine_load", "vehicles/tire_squeal"]:
		var wav: AudioStreamWAV = load(AssetResolver.audio_fallback_path(logical))
		var data := wav.data
		var peak := 0
		for i in range(0, data.size() - 1, 2 * 37):
			peak = maxi(peak, absi(data.decode_s16(i)))
		assert_gt(peak, 8000, logical)


func test_wav_override_takes_precedence_and_loops() -> void:
	_write("audio/vehicles/engine_loop.wav", _wav_bytes(2205))
	var stream := AssetResolver.new(_root).get_audio("vehicles/engine_loop", true)
	assert_true(stream is AudioStreamWAV)
	assert_almost_eq(stream.get_length(), 0.1, 0.01)
	assert_eq((stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD)


func test_ogg_override_takes_precedence() -> void:
	var template := FileAccess.get_file_as_bytes(AssetResolver.audio_fallback_path("race/finish"))
	_write("audio/race/start_go.ogg", template)  # a valid OGG under another name
	var stream := AssetResolver.new(_root).get_audio("race/start_go")
	assert_true(stream is AudioStreamOggVorbis)
	assert_almost_eq(stream.get_length(), (load(AssetResolver.audio_fallback_path("race/finish")) as AudioStream).get_length(), 0.05)


func test_missing_audio_override_uses_template() -> void:
	var stream := AssetResolver.new(_root).get_audio("race/finish")
	assert_eq(stream.resource_path, AssetResolver.audio_fallback_path("race/finish"))


func test_invalid_audio_override_falls_back_with_warning() -> void:
	_write("audio/race/finish.ogg", "definitely not audio".to_utf8_buffer())
	var stream := AssetResolver.new(_root).get_audio("race/finish")
	assert_eq(stream.resource_path, AssetResolver.audio_fallback_path("race/finish"))
	assert_push_warning_count(1)


func test_loop_flag_applies_to_templates() -> void:
	var r := AssetResolver.new(_root)
	for logical in AssetCatalog.AUDIO:
		if AssetCatalog.AUDIO[logical].loop:
			var s := r.get_audio(logical, true)
			if s is AudioStreamOggVorbis:
				assert_true(s.loop, logical)
			elif s is AudioStreamWAV:
				assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, logical)


func test_new_graphics_have_templates_of_declared_size() -> void:
	var r := AssetResolver.new(_root)
	for logical in AssetCatalog.SPECS:
		if AssetCatalog.is_legacy(logical):
			continue  # (legacy flattened cars: the user's drawings only, no template)
		var template := load(AssetResolver.fallback_path(logical)) as Texture2D
		assert_not_null(template, logical)
		if template != null:
			assert_eq(Vector2i(template.get_size()), AssetCatalog.SPECS[logical].template_size, logical)
		var tex := r.get_texture(logical)  # (the template, or the user's own drawing: any size, same shape)
		if tex != null and template != null:
			assert_almost_eq(tex.get_size().aspect(), template.get_size().aspect(), 0.02, "%s: same aspect ratio" % logical)


func test_ten_cars_are_visually_distinct() -> void:
	var names := [AssetCatalog.CAR_PLAYER]
	for i in range(1, 10):
		names.append(AssetCatalog.ai_car(i))
	var averages := []
	for n in names:
		var img := (load(AssetResolver.fallback_path(AssetCatalog.body_of(n))) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var sum := Vector3.ZERO
		var count := 0
		for y in range(20, 52, 4):
			for x in range(20, 108, 4):
				var c := img.get_pixel(x, y)
				if c.a > 0.9:
					sum += Vector3(c.r, c.g, c.b)
					count += 1
		averages.append(sum / count)
	for i in averages.size():
		for j in range(i + 1, averages.size()):
			assert_gt((averages[i] - averages[j]).length(), 0.06, "%s vs %s" % [names[i], names[j]])


func test_font_and_licence_are_shipped() -> void:
	assert_true(ResourceLoader.exists(HyperTheme.FONT_PATH))
	assert_true(FileAccess.file_exists("res://assets/fonts/Fredoka_OFL.txt"))
	assert_string_contains(FileAccess.get_file_as_string("res://assets/fonts/Fredoka_OFL.txt"), "SIL Open Font License")


func test_engine_load_layer_override_takes_precedence_and_loops() -> void:
	_write("audio/vehicles/engine_load.wav", _wav_bytes(2205))
	var stream := AssetResolver.new(_root).get_audio("vehicles/engine_load", true)
	assert_true(stream is AudioStreamWAV)
	assert_almost_eq(stream.get_length(), 0.1, 0.01)
	assert_eq((stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD)
