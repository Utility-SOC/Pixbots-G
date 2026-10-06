extends Node

const PS = preload("res://scripts/audio/ProceduralSynth.gd")
const Genome = preload("res://scripts/audio/MusicGenome.gd")

func _rms(d: PackedByteArray) -> float:
	var acc = 0.0
	var n = d.size() / 2
	for i in range(0, n, 7):
		var v = d.decode_s16(i * 2)
		acc += float(v) * float(v)
	return sqrt(acc / max(n / 7, 1)) / 32768.0

func _ready():
	var fails = 0
	var g = Genome.create(1234)
	var p = g.to_params()
	var a = PS.generate_track(PS.Ctx.GARAGE, 0, 1, Callable(), "", false, p)
	var b = PS.generate_track(PS.Ctx.GARAGE, 0, 1, Callable(), "", false, p)
	if a.data != b.data:
		print("FAIL: same genome is not deterministic")
		fails += 1
	var p2 = p.duplicate()
	p2["seed"] = p["seed"] + 1
	if PS.generate_track(PS.Ctx.GARAGE, 0, 1, Callable(), "", false, p2).data == a.data:
		print("FAIL: different seed produced identical track")
		fails += 1
	# Evolution: later generation keeps the progression and adds layers.
	var p3 = p.duplicate()
	p3["gen"] = 3
	var c = PS.generate_track(PS.Ctx.GARAGE, 0, 1, Callable(), "", false, p3)
	if c.data == a.data or c.data.size() != a.data.size():
		print("FAIL: generation 3 should differ from 0 with the same loop length")
		fails += 1
	print("rms gen0=%.3f gen3=%.3f" % [_rms(a.data), _rms(c.data)])
	# Generation schedule + persistence roundtrip.
	var m = Genome.create(5)
	if m.note_wave(7) or m.generation != 0:
		print("FAIL: gen should not advance below 8 waves")
		fails += 1
	if not m.note_wave(17) or m.generation != 2:
		print("FAIL: wave 17 should reach gen 2 (got %d)" % m.generation)
		fails += 1
	if m.note_wave(10):
		print("FAIL: lower wave must not change generation")
		fails += 1
	var r = Genome.from_dict(m.to_dict())
	if r.tag() != m.tag() or r.prog_pick != m.prog_pick or r.best_wave != 17:
		print("FAIL: genome dict roundtrip")
		fails += 1
	# PCM roundtrip.
	var s2 = AudioManager.pcm_to_stream(a.data)
	if s2.data != a.data or s2.loop_end != a.loop_end:
		print("FAIL: pcm roundtrip")
		fails += 1
	print("music genome check done, failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
