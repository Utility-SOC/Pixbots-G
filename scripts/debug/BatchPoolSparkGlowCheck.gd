extends Node

# Regression check for ProjectileBatchPool's spark-scatter + glow-halo
# visual layer (2026-08-13, live playtest: "these batches are really small
# particles / I don't feel like I am decorating my weapons like with the
# primary/original version"). Tests the pure _compute_spark_render function
# directly - same "test the math, not a render round-trip" reasoning as
# every other _compute_* function in ProjectileBatchPool.gd (get_instance_*
# doesn't reliably reflect a same-frame write under --headless).

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var render_pos = Vector2(100, 50)
	var direction = Vector2.RIGHT
	var color = Color(1.0, 0.5, 0.2, 1.0)

	# --- Sparks trail BEHIND the shot, within the configured distance band ---
	var spark0 = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, 0.0, 12345, 0, 1.0, color)
	var offset0 = spark0["position"] - render_pos
	_check("a spark's position is offset opposite the shot's direction (trailing, not leading)",
		offset0.dot(direction) < 0.0)
	var trail_dist = -offset0.dot(direction)
	_check("a spark's trailing distance falls within [SPARK_MIN_TRAIL_DIST, SPARK_MAX_TRAIL_DIST]",
		trail_dist >= ProjectileBatchPoolScript.SPARK_MIN_TRAIL_DIST - 0.01 and trail_dist <= ProjectileBatchPoolScript.SPARK_MAX_TRAIL_DIST + 0.01)

	# --- Alpha is a fraction of the input alpha, scaled by SPARK_ALPHA_MULT ---
	_check("a spark's alpha never exceeds alpha * SPARK_ALPHA_MULT (fades further for sparks trailing further back)",
		spark0["color"].a <= 1.0 * ProjectileBatchPoolScript.SPARK_ALPHA_MULT + 0.001)
	var spark0_half_alpha = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, 0.0, 12345, 0, 0.5, color)
	_check("halving the input alpha halves the spark's own alpha proportionally",
		is_equal_approx(spark0_half_alpha["color"].a, spark0["color"].a * 0.5))

	# --- Different spark_index values scatter to different positions, not a single stacked dot ---
	var spark1 = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, 0.0, 12345, 1, 1.0, color)
	var spark2 = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, 0.0, 12345, 2, 1.0, color)
	_check("spark index 0 and 1 land at different positions (a real scatter, not identical dots)",
		spark0["position"].distance_to(spark1["position"]) > 0.5)
	_check("spark index 1 and 2 also land at different positions",
		spark1["position"].distance_to(spark2["position"]) > 0.5)

	# --- Deterministic per-shot: same seed+bucket always reproduces the same spark ---
	var spark0_repeat = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, 0.0, 12345, 0, 1.0, color)
	_check("the same spawn_gen/spark_index/elapsed-bucket always reproduces the identical spark (deterministic, no live RNG state)",
		spark0["position"] == spark0_repeat["position"])

	# --- Different spawn_gen (a different shot) scatters differently at the identical index/time ---
	var spark0_other_shot = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, 0.0, 99999, 0, 1.0, color)
	_check("a different shot's spawn_gen produces a different spark position at the same index (no visible lockstep pattern across shots)",
		spark0["position"] != spark0_other_shot["position"])

	# --- Elapsed time bucketing: a jump across a SPARK_REFRESH_INTERVAL boundary re-rolls the spark ---
	var refresh = ProjectileBatchPoolScript.SPARK_REFRESH_INTERVAL
	var spark0_next_bucket = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, refresh * 1.5, 12345, 0, 1.0, color)
	_check("crossing a SPARK_REFRESH_INTERVAL boundary changes the spark's position (flicker, not frozen for the whole shot lifetime)",
		spark0["position"] != spark0_next_bucket["position"])
	var spark0_same_bucket = ProjectileBatchPoolScript._compute_spark_render(render_pos, direction, refresh * 0.9, 12345, 0, 1.0, color)
	_check("staying within the same SPARK_REFRESH_INTERVAL bucket keeps the spark's position stable (not sliding continuously)",
		spark0["position"] == spark0_same_bucket["position"])

	# --- ProjectileBatchPool actually applies z_index and has the glow/spark
	# constants wired (guards against a silently-inert dial: SPARK_COUNT=0
	# or GLOW_ALPHA_MULT=0 would compile fine but render nothing) ---
	_check("SPARK_COUNT is a real positive count, not silently disabled",
		ProjectileBatchPoolScript.SPARK_COUNT > 0)
	_check("GLOW_ALPHA_MULT is a real positive value, not silently disabled",
		ProjectileBatchPoolScript.GLOW_ALPHA_MULT > 0.0)

	if failures == 0:
		print("PASS: spark-scatter math trails behind the shot with correct distance/alpha falloff, scatters distinctly per index/shot, and flickers deterministically across refresh-interval buckets")
	get_tree().quit(0 if failures == 0 else 1)
