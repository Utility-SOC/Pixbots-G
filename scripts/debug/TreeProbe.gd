extends Node

# Timestamp marker planted at a fixed place in the tree (process order = tree
# order at equal priority). Each frame the probes append (label, usec); the
# "__last" probe snapshots the sequence so BenchGame can print which gap between
# consecutive probes held a slow frame.

static var marks: Array = []
static var last_marks: Array = []

var label := ""

func _ready():
	if label == "__first":
		process_priority = -1000000
	elif label == "__last":
		process_priority = 1000000

func _process(_d):
	var now = Time.get_ticks_usec()
	if label == "__first":
		marks = []
	marks.append([label, now])
	if label == "__last":
		last_marks = marks

static func worst_gaps(n: int = 2) -> String:
	var gaps = []
	for i in range(1, last_marks.size()):
		gaps.append([(last_marks[i][1] - last_marks[i - 1][1]) / 1000.0, str(last_marks[i - 1][0]) + " -> " + str(last_marks[i][0])])
	gaps.sort_custom(func(a, b): return a[0] > b[0])
	var out = ""
	for k in range(min(n, gaps.size())):
		out += "[%.0fms %s] " % [gaps[k][0], gaps[k][1]]
	return out
