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
		
	_fill_buffer()

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
	
	var buffer = PackedVector2Array()
	buffer.resize(frames_available)
	
	for i in range(frames_available):
		var sample = 0.0
		var delta = 1.0 / sample_hz
		
		var active_notes = []
		for n in notes_playing:
			if n.life < n.duration:
				var amp = 1.0
				
				# ADSR Envelope (simplified)
				if n.life < 0.05: # Attack
					amp = n.life / 0.05
				elif n.duration - n.life < 0.1: # Release
					amp = (n.duration - n.life) / 0.1
				
				var t = n.life
				var val = 0.0
				if n.waveform == "sine":
					val = sin(TAU * n.freq * t)
				elif n.waveform == "square":
					val = sign(sin(TAU * n.freq * t)) * 0.5
				elif n.waveform == "saw":
					val = fmod(t * n.freq, 1.0) * 2.0 - 1.0
					val *= 0.5
				elif n.waveform == "pluck":
					# Exponential decay simulating a pluck
					var decay = exp(-10.0 * t)
					val = sin(TAU * n.freq * t) * decay
				
				sample += val * amp * 0.1 # Volume attenuation
				n.life += delta
				active_notes.append(n)
				
		notes_playing = active_notes
		buffer[i] = Vector2(sample, sample)
		
	playback.push_buffer(buffer)
