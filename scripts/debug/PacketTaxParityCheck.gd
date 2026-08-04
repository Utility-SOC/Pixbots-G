extends Node

# Regression check for the Rust packet-tax batching port (rust_ext/src/
# packet_tax.rs, wired into Mech._shoot_impl - see Status.md's Phase 4
# section). Same ground-truth-vs-port diffing pattern as
# ProjectileBroadphaseParityCheck.gd: hand-built requests covering tax
# scaling, jamming suppression, ambush multiplier, multi-key synergies, and
# the "input dict must not be mutated" contract - assert PacketTaxRs.
# batch_scale_packets() and Mech._batch_scale_packets_fallback() produce
# identical results, AND that neither one mutates the caller's original
# synergies dict (that dict is the PERSISTENT precalculated packet's own
# Dictionary in real gameplay, reused across every future shot).

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, actual, expected):
	var matches: bool
	if actual is float and expected is float:
		matches = abs(actual - expected) < 0.0001
	else:
		matches = actual == expected
	if not matches:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _dicts_close(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
		if abs(float(a[k]) - float(b[k])) > 0.0001:
			return false
	return true

func _ready():
	var checked = false
	var rasterizer = null
	if ClassDB.class_exists("PacketTaxRs"):
		checked = true
		rasterizer = ClassDB.instantiate("PacketTaxRs")

	if not rasterizer:
		push_error("FAIL: PacketTaxRs not available - rust_ext DLL not built/loaded, can't verify parity")
		get_tree().quit(1)
		return

	var requests = [
		# 1. Plain tax scaling, no jamming, no ambush change.
		{"magnitude": 100.0, "synergies": {0: 60.0, 3: 40.0}, "tax": 0.9, "jammed_synergies": PackedInt32Array(), "ambush_mult": 1.0},
		# 2. Jamming suppresses one synergy (id 3), magnitude reduced accordingly.
		{"magnitude": 200.0, "synergies": {0: 50.0, 3: 150.0}, "tax": 1.0, "jammed_synergies": PackedInt32Array([3]), "ambush_mult": 1.0},
		# 3. Ambush multiplier on top of tax.
		{"magnitude": 50.0, "synergies": {7: 50.0}, "tax": 0.5, "jammed_synergies": PackedInt32Array(), "ambush_mult": 1.5},
		# 4. Multiple synergy keys, multiple jammed ids (one present, one absent).
		{"magnitude": 300.0, "synergies": {0: 100.0, 1: 100.0, 2: 100.0}, "tax": 0.8, "jammed_synergies": PackedInt32Array([1, 9]), "ambush_mult": 1.2},
		# 5. Zero tax edge case.
		{"magnitude": 100.0, "synergies": {0: 100.0}, "tax": 0.0, "jammed_synergies": PackedInt32Array(), "ambush_mult": 1.0},
		# 6. Empty synergies dict.
		{"magnitude": 10.0, "synergies": {}, "tax": 1.0, "jammed_synergies": PackedInt32Array(), "ambush_mult": 1.0},
	]

	# Snapshot the original synergies dicts (by value) so we can prove
	# neither implementation mutated them in place after the calls below.
	var originals = []
	for req in requests:
		originals.append(req.synergies.duplicate())

	var rust_results = rasterizer.batch_scale_packets(requests)
	var fallback_results = MechScript._batch_scale_packets_fallback(requests)

	_check("rust result count", rust_results.size(), requests.size())
	_check("fallback result count", fallback_results.size(), requests.size())

	for i in range(requests.size()):
		var r = rust_results[i]
		var f = fallback_results[i]
		_check("case %d: rust magnitude == fallback magnitude" % i, abs(float(r.magnitude) - float(f.magnitude)) < 0.0001, true)
		_check("case %d: rust synergies == fallback synergies" % i, _dicts_close(r.synergies, f.synergies), true)

	# No-mutation contract: the input requests' synergies dicts must be
	# byte-identical to what they were before either call ran.
	for i in range(requests.size()):
		_check("case %d: input synergies dict untouched" % i, _dicts_close(requests[i].synergies, originals[i]), true)

	if failures == 0:
		print("PASS: Rust packet-tax batching is result-identical to the GDScript fallback across all cases, and neither mutates the input synergies dict")
	else:
		push_error("FAIL: %d mismatches - see above" % failures)
		get_tree().quit(1)
		return

	get_tree().quit(0)
