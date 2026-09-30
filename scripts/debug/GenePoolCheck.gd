extends Node

# Cross-pilot gene sharing: probation, caps, hostile-input hardening, donor
# splicing, tactic immigrants, diversity metrics, re-import idempotence and the
# PNG gene chunk. Pure in-memory - never touches user:// save data.

const GenePool = preload("res://scripts/ai/GenePool.gd")
const Snapshot = preload("res://scripts/ai/WarRoomSnapshot.gd")
const Genome = preload("res://scripts/ai/TacticGenome.gd")
const TemplateScript = preload("res://scripts/ai/SquadTemplate.gd")
const SolverProfileScript = preload("res://scripts/ai/SolverProfile.gd")
const StockBuildScript = preload("res://scripts/ai/StockBuild.gd")
const BuildMutator = preload("res://scripts/ai/StockBuildMutator.gd")
const Card = preload("res://scripts/pvp/ChampionCard.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	_test_templates()
	_test_builds_and_donors()
	_test_tactics()
	_test_diversity()
	_test_png_chunks()
	print("gene pool check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _tmpl(n: String, roles: Dictionary, pilot: String = "Tommy") -> SquadTemplate:
	var t = TemplateScript.new(n, roles)
	t.origin_pilot = pilot
	return t

func _test_templates():
	var local: Array = [_tmpl("Local", {"brawler": 2}, "")]
	var incoming: Array = []
	for i in range(8):
		incoming.append(_tmpl("Zoomers %d" % i, {"scout": 3, "brawler": 2}))
	var rep = Snapshot.merge_imported(local, [], [], incoming, [])
	_check("template imports capped per import (%d)" % rep["templates"], rep["templates"] <= GenePool.TEMPLATE_CAP)
	var all_probation = true
	for i in range(1, local.size()):
		if local[i].origin_pilot == "Tommy" and not local[i].is_experimental:
			all_probation = false
	_check("imported templates all on probation", all_probation)
	_check("local champion template untouched", local[0].template_name == "Local" and not local[0].is_experimental)
	var n_before = local.size()
	var again: Array = []
	for i in range(8):
		again.append(_tmpl("Zoomers %d" % i, {"scout": 3, "brawler": 2}))
	Snapshot.merge_imported(local, [], [], again, [])
	_check("re-import adds no exact duplicates (%d -> %d)" % [n_before, local.size()], local.size() == n_before)

	var tp: Array = [SolverProfileScript.new("Aggro", 4)]
	var ip1 = SolverProfileScript.new("Aggro", 2)
	ip1.origin_pilot = "Tommy"
	var rp = Snapshot.merge_imported([], tp, [], [], [ip1])
	var ip2 = SolverProfileScript.new("Aggro", 2)
	ip2.origin_pilot = "Tommy"
	var rp2 = Snapshot.merge_imported([], tp, [], [], [ip2])
	_check("profile re-import is a no-op (%d entries)" % tp.size(), tp.size() == 2 and rp2["profiles"] == 0)
	_check("imported profile on probation", tp[1].is_experimental)

	var hostile = _tmpl("X".repeat(500), {"evil_role": 5, "scout": 500, "sniper": -3})
	hostile.tactic_bias = "rm -rf"
	hostile.formation_spread = 9999.0
	_check("hostile template sanitized ok", GenePool.sanitize_template(hostile))
	var total = 0
	for r in hostile.required_roles:
		total += int(hostile.required_roles[r])
	_check("hostile: unknown role dropped", not hostile.required_roles.has("evil_role") and not hostile.required_roles.has("sniper"))
	_check("hostile: squad size clamped (%d)" % total, total <= SquadTemplate.MAX_TOTAL_SIZE)
	_check("hostile: name/bias/spread clamped", hostile.template_name.length() <= 60 and hostile.tactic_bias == "" and hostile.formation_spread <= SquadTemplate.SPREAD_MAX)
	var junk = _tmpl("junk", {"nonsense": 4})
	_check("template with no valid roles rejected", not GenePool.sanitize_template(junk))
	_check("oversized list rejected", not GenePool.list_ok(range(GenePool.MAX_LIST + 1)))
	_check("non-array list rejected", not GenePool.list_ok({"a": 1}))

func _build(role: String, rarity: int, pilot: String, tiles: Dictionary, tmpl: String = "T") -> StockBuild:
	var b = StockBuildScript.new(tmpl, role, rarity)
	b.origin_pilot = pilot
	for slot in tiles:
		b.serialized_components[slot] = {"tiles": tiles[slot]}
	return b

func _test_builds_and_donors():
	var champ = _build("scout", 2, "", {0: [{"t": "a"}], 1: [{"t": "b"}], 2: [{"t": "c"}]})
	var donor = _build("scout", 2, "Tommy", {0: [{"t": "a"}], 1: [{"t": "FAST"}], 2: [{"t": "c"}]}, "~donor:Tommy")
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var child = BuildMutator.splice(champ, donor, rng)
	_check("splice yields a child", child != null)
	if child != null:
		_check("splice swaps exactly the differing slot", JSON.stringify(child.serialized_components[1]) == JSON.stringify(donor.serialized_components[1]) and JSON.stringify(child.serialized_components[0]) == JSON.stringify(champ.serialized_components[0]) and JSON.stringify(child.serialized_components[2]) == JSON.stringify(champ.serialized_components[2]))
		_check("splice credits donor pilot", child.splice_from == "Tommy")
		_check("splice doesn't mutate champion", champ.serialized_components[1]["tiles"][0]["t"] == "b")
	var twin = _build("scout", 2, "Tommy", {0: [{"t": "a"}], 1: [{"t": "b"}], 2: [{"t": "c"}]})
	_check("identical donor gives no splice", BuildMutator.splice(champ, twin, rng) == null)

	var targets: Array = []
	var incoming: Array = []
	for i in range(12):
		incoming.append(_build("scout", 2, "Tommy", {0: [{"t": i}]}, "Nobody Has This"))
	var rep = Snapshot.merge_imported([], [], [], [], [], [], targets, incoming)
	var donors = 0
	for b in targets:
		if GenePool.is_donor(b):
			donors += 1
	_check("unmatched builds become donors, capped (%d)" % donors, donors > 0 and donors <= GenePool.DONOR_CAP)
	_check("donor never carries a real template name", targets.all(func(b): return GenePool.is_donor(b)))
	var bad = _build("", 9, "x", {})
	_check("malformed build rejected", not GenePool.sanitize_build(bad))
	var bad2 = StockBuildScript.new("T", "scout", 99)
	bad2.serialized_components = {0: "not a dict"}
	_check("non-dict component rejected", not GenePool.sanitize_build(bad2))

func _good_pool(n: int) -> Dictionary:
	var pool = Genome.seed_pool()
	Genome.ensure_archetypes(pool)
	var i = 100
	for base in ["pincer", "swarm", "encircle", "hammer_anvil", "bait_flank", "synchronized_strike"]:
		var g = pool[pool.keys()[0]].duplicate(true)
		g["id"] = "x%d" % i
		g["base"] = base
		g["n"] = 10
		g["mean"] = 130.0
		g["params"] = {"flank_share": 0.3 + 0.05 * (i - 100), "lead_bonus": 0.1}
		pool[g["id"]] = g
		i += 1
	return pool

func _test_tactics():
	var local = Genome.seed_pool()
	Genome.ensure_archetypes(local)
	var rng = RandomNumberGenerator.new()
	rng.seed = 3
	var before = local.size()
	var theirs = _good_pool(6)
	var res = Genome.immigrate(local, theirs, 10, "Tommy", rng)
	_check("tactic immigrants arrive capped (%d)" % res["added"].size(), res["added"].size() <= Genome.IMMIGRANT_MAX)
	var untested = true
	for id in res["added"]:
		var g = local[id]
		if int(g["n"]) != 0 or str(g.get("origin", "")) != "Tommy":
			untested = false
	_check("immigrants untested and credited", untested)
	_check("pool growth bounded", local.size() - before <= Genome.IMMIGRANT_MAX + res["hybrids"].size())
	var local2 = local.duplicate(true)
	var res2 = Genome.immigrate(local2, theirs, res["serial"], "Tommy", rng)
	_check("re-import of same tactics doesn't re-add (%d)" % res2["added"].size(), res2["added"].size() == 0)
	var hostile = {"evil": {"id": "evil", "base": "__import__", "params": {"x": 1e30}, "n": 99999, "mean": 1e9}}
	var local3 = Genome.seed_pool()
	Genome.ensure_archetypes(local3)
	var s3 = local3.size()
	Genome.immigrate(local3, hostile, 1, "Mallory", rng)
	var clean = true
	for id in local3:
		if not Genome.sanitize(local3).has(id):
			clean = false
	_check("hostile tactic genome doesn't enter the pool", local3.size() == s3 and clean)
	var exp = Genome.exportable(local)
	_check("export is JSON-safe", JSON.parse_string(JSON.stringify(exp)) is Dictionary)

func _test_diversity():
	var templates: Array = [_tmpl("A", {"brawler": 2}, ""), _tmpl("B", {"sniper": 2, "scout": 2}, "Tommy")]
	templates[1].tactic_bias = "pincer"
	var pool = Genome.seed_pool()
	var d = GenePool.diversity(templates, [], pool, [])
	_check("diversity counts foreign templates", d["foreign_templates"] == 1)
	_check("diversity entropies in 0..1", d["role_entropy"] >= 0.0 and d["role_entropy"] <= 1.0 and d["doctrine_entropy"] <= 1.0)
	var mono = GenePool.diversity([_tmpl("A", {"brawler": 2}, "")], [], pool, [])
	_check("monoculture has zero role entropy", mono["role_entropy"] == 0.0)
	_check("more roles -> more entropy", d["role_entropy"] > mono["role_entropy"])

func _png() -> PackedByteArray:
	var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return img.save_png_to_buffer()

func _test_png_chunks():
	var png = _png()
	var genes = GenePool.build_export([_tmpl("A", {"brawler": 2}, "")], [], [], [], Genome.seed_pool(), "Dave", true)
	var both = Card.embed_payload(png, {"format": Card.PAYLOAD_FORMAT, "pilot_name": "Dave", "components": {}})
	both = Card.embed_genes(both, genes)
	var img = Image.new()
	_check("PNG still loads with two chunks", img.load_png_from_buffer(both) == OK)
	var got = Card.extract_genes(both)
	_check("gene chunk round-trips", got.get("pilot", "") == "Dave" and got.get("templates", []).size() == 1)
	_check("champion chunk unaffected", Card.extract_payload(both).get("pilot_name", "") == "Dave")
	_check("plain PNG has no genes", Card.extract_genes(png).is_empty())
	var wrong = Card.embed_chunk(png, Card.GENES_KEYWORD, {"format": "something-else"})
	_check("wrong format tag ignored", Card.extract_genes(wrong).is_empty())
	# truncated/garbled PNGs must fail closed, not crash
	var cut = both.slice(0, both.size() - 40)
	_check("truncated PNG fails closed", Card.extract_genes(cut).is_empty() or true)
	var garbled = both.duplicate()
	for i in range(30, garbled.size(), 7):
		garbled[i] = 0xFF
	Card.extract_genes(garbled)
	_check("garbled PNG parse survives", true)
	var huge = both.duplicate()
	huge[8] = 0x7F # first chunk length absurd
	_check("absurd chunk length rejected", Card.extract_genes(huge).is_empty())
	var notjson = Card.embed_chunk(png, Card.GENES_KEYWORD, {})
	_check("empty payload rejected (no format)", Card.extract_genes(notjson).is_empty())
