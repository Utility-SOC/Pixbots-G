extends Node

# Splits a slow frame into phases using callbacks pinned to the first and last
# positions of both the physics and process passes (process_priority):
#   gap_pre  = previous frame's last process callback -> this frame's first physics/process callback
#              (rendering, deferred-call flush, deletion queue, input, audio...)
#   phys     = first physics callback start -> last physics callback end (all steps this frame)
#   gap_post = last physics callback end -> first process callback (includes the physics server step)
#   proc     = first process callback -> last process callback
# Static so the first/last instances share state. BenchGame prints it on spikes.

static var t_prev_proc_end := 0
static var t_phys_start := 0
static var t_phys_end := 0
static var t_proc_start := 0
static var physics_steps := 0
static var last_split := {}

var is_last := false

func _ready():
	process_priority = 100000 if is_last else -100000
	process_physics_priority = 100000 if is_last else -100000

func _physics_process(_d):
	var now = Time.get_ticks_usec()
	if is_last:
		t_phys_end = now
	else:
		if t_phys_start == 0 or t_proc_start != 0:
			t_phys_start = now # first step of this frame
			physics_steps = 0
			t_proc_start = 0
		physics_steps += 1

func _process(_d):
	var now = Time.get_ticks_usec()
	if not is_last:
		t_proc_start = now
		return
	var first = t_phys_start if t_phys_start > 0 and t_phys_start > t_prev_proc_end else t_proc_start
	last_split = {
		"gap_pre": (first - t_prev_proc_end) / 1000.0 if t_prev_proc_end > 0 else 0.0,
		"phys": (t_phys_end - t_phys_start) / 1000.0 if t_phys_start > t_prev_proc_end else 0.0,
		"gap_post": (t_proc_start - t_phys_end) / 1000.0 if t_phys_end > t_prev_proc_end else 0.0,
		"proc": (now - t_proc_start) / 1000.0,
		"steps": physics_steps if t_phys_start > t_prev_proc_end else 0,
	}
	t_prev_proc_end = now
	t_phys_start = 0
	t_proc_start = 0
