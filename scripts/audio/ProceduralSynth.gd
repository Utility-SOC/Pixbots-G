class_name ProceduralSynth
extends RefCounted

const SAMPLE_RATE: int = 44100
const TWO_PI: float = TAU

# Frequencies for a C Minor Pentatonic Scale
const SCALE_FREQS = [261.63, 311.13, 349.23, 392.00, 466.16, 523.25]

# cancel_check: optional callable polled during the (multi-second) sample
# loop so the caller's worker thread can be shut down promptly at app quit -
# returns null when cancelled.
static func generate_level_loop(synergy: EnergyPacket.SynergyType, is_combat: bool, cancel_check: Callable = Callable()) -> AudioStreamWAV:
	# Generate a longer loop for more variability (16 seconds ambient, 8 seconds combat)
	var duration_sec: float = 8.0
	if not is_combat:
		duration_sec = 16.0
		
	var total_samples: int = int(duration_sec * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2) # 16-bit audio = 2 bytes per sample
	
	# Audio parameters based on synergy
	var root_note_index = randi() % 3
	var bass_freq = SCALE_FREQS[root_note_index] / 2.0
	
	var use_square = synergy == EnergyPacket.SynergyType.LIGHTNING or synergy == EnergyPacket.SynergyType.KINETIC
	var use_saw = synergy == EnergyPacket.SynergyType.FIRE or synergy == EnergyPacket.SynergyType.EXPLOSION
	
	for i in range(total_samples):
		if (i & 0xFFFF) == 0 and cancel_check.is_valid() and cancel_check.call():
			return null
		var time = float(i) / SAMPLE_RATE
		var sample_val = 0.0
		
		# Chord progression: change root bass note every 4 seconds
		var chord_phase = int(time / 4.0) % 4
		var current_bass = bass_freq
		if chord_phase == 1:
			current_bass = SCALE_FREQS[(root_note_index + 2) % SCALE_FREQS.size()] / 2.0
		elif chord_phase == 2:
			current_bass = SCALE_FREQS[(root_note_index + 4) % SCALE_FREQS.size()] / 2.0
		elif chord_phase == 3:
			current_bass = SCALE_FREQS[(root_note_index + 1) % SCALE_FREQS.size()] / 2.0
		
		# 1. Bassline (Sine or Square)
		var bass_wave = sin(time * current_bass * TWO_PI)
		if use_square:
			bass_wave = 1.0 if bass_wave > 0 else -1.0
			bass_wave *= 0.4
			
		sample_val += bass_wave * 0.4
		
		# 2. Arpeggiator / Melody
		# Change note every 0.25 seconds, and shift up depending on the chord phase
		var step = (int(time * 4) + chord_phase) % SCALE_FREQS.size()
		var arp_freq = SCALE_FREQS[step]
		if is_combat:
			# Faster arpeggios in combat (eighth notes)
			step = (int(time * 8) + chord_phase) % SCALE_FREQS.size()
			arp_freq = SCALE_FREQS[step]
			
		var melody_wave = sin(time * arp_freq * TWO_PI)
		
		if use_saw:
			# Simple sawtooth approximation
			melody_wave = 2.0 * fmod(time * arp_freq, 1.0) - 1.0
			
		# Enveloping (quick decay for pluck sound)
		var env = exp(-8.0 * fmod(time, 0.25 if not is_combat else 0.125))
		sample_val += melody_wave * env * 0.3
		
		# 3. Combat Drums (White Noise Burst on downbeats)
		if is_combat:
			var beat_time = fmod(time, 0.5)
			if beat_time < 0.05: # Kick/Snare transient
				sample_val += (randf() * 2.0 - 1.0) * exp(-40.0 * beat_time) * 0.4
				
		# Clip to prevent distortion
		sample_val = clamp(sample_val, -1.0, 1.0)
		
		# Convert float [-1.0, 1.0] to 16-bit integer
		var pcm = int(sample_val * 32767.0)
		# Write little-endian bytes
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total_samples
	
	return stream
