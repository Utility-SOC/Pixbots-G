extends AudioStreamPlayer

var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback

var time_passed: float = 0.0
var sample_hz: float = 44100.0

# Procedural synth state
var current_biome: String = "Open Field"
var tempo_bpm: float = 120.0
var beat_interval: float = 0.5
var next_beat_time: float = 0.0
var beat_counter: int = 0

var notes_playing: Array = []
static var _perf_fill_usec: int = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_hz
	generator.buffer_length = 0.1
	
	stream = generator
	play()
	playback = get_stream_playback()

func set_biome(biome_name: String):
	current_biome = biome_name
	if biome_name == "Island":
		tempo_bpm = 140.0 # Fast surf rock vibe
	elif biome_name == "Snow":
		tempo_bpm = 90.0  # Slow, atmospheric
	elif biome_name == "Desert":
		tempo_bpm = 110.0 # Rhythmic
	else:
		tempo_bpm = 120.0
		
	beat_interval = 60.0 / tempo_bpm
	notes_playing.clear()

func _process(delta):
	time_passed += delta
	
	if time_passed >= next_beat_time:
		_trigger_beat()
		next_beat_time += beat_interval
		beat_counter += 1

	var t0 = Time.get_ticks_usec()
	_fill_buffer()
	_perf_fill_usec += Time.get_ticks_usec() - t0

func _trigger_beat():
	# Generate notes based on biome
	if current_biome == "Island":
		# Surf guitar vibe (fast arpeggios, pentatonic)
		if beat_counter % 2 == 0:
			_play_note(_midi_to_freq(55), 0.2, "pluck") # G3
		if beat_counter % 4 == 0:
			_play_note(_midi_to_freq(62), 0.4, "pluck") # D4
		if beat_counter % 8 == 6:
			_play_note(_midi_to_freq(67), 0.2, "pluck") # G4
	elif current_biome == "Snow":
		# Atmospheric, sustained chords
		if beat_counter % 16 == 0:
			_play_note(_midi_to_freq(60), 2.0, "sine") # C4
			_play_note(_midi_to_freq(63), 2.0, "sine") # Eb4
			_play_note(_midi_to_freq(67), 2.0, "sine") # G4
	elif current_biome == "Desert":
		# Rhythmic, bass heavy, phrygian dominant
		if beat_counter % 4 == 0:
			_play_note(_midi_to_freq(40), 0.5, "saw") # E2
		if beat_counter % 8 == 2 or beat_counter % 8 == 5:
			_play_note(_midi_to_freq(41), 0.2, "saw") # F2
	else:
		# Generic Open Field
		if beat_counter % 4 == 0:
			_play_note(_midi_to_freq(48), 0.3, "square") # C3
		if beat_counter % 8 == 4:
			_play_note(_midi_to_freq(55), 0.3, "square") # G3

func _play_note(freq: float, duration: float, waveform: String):
	notes_playing.append({
		"freq": freq,
		"duration": duration,
		"life": 0.0,
		"waveform": waveform
	})

func _midi_to_freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

func _fill_buffer():
	if not playback: return

	var frames_available = playback.get_frames_available()
	if frames_available <= 0: return

	var mono = PackedFloat32Array()
	mono.resize(frames_available)
	var dt = 1.0 / sample_hz
	var survivors: Array = []
	for n in notes_playing:
		var life: float = n.life
		var duration: float = n.duration
		if life >= duration:
			continue
		var freq: float = n.freq
		var waveform: String = n.waveform
		for i in range(frames_available):
			if life >= duration:
				break
			var amp = 1.0
			if life < 0.05:
				amp = life / 0.05
			elif duration - life < 0.1:
				amp = (duration - life) / 0.1
			var val = 0.0
			if waveform == "sine":
				val = sin(TAU * freq * life)
			elif waveform == "square":
				val = sign(sin(TAU * freq * life)) * 0.5
			elif waveform == "saw":
				val = (fmod(life * freq, 1.0) * 2.0 - 1.0) * 0.5
			elif waveform == "pluck":
				val = sin(TAU * freq * life) * exp(-10.0 * life)
			mono[i] += val * amp * 0.1
			life += dt
		n.life = life
		survivors.append(n)
	notes_playing = survivors

	var buffer = PackedVector2Array()
	buffer.resize(frames_available)
	for i in range(frames_available):
		buffer[i] = Vector2(mono[i], mono[i])
	playback.push_buffer(buffer)
