extends RefCounted
## V2 bomb_reset is emitted only from the parser's actual RoundStart callback.
## This index does not infer rounds from bomb outcomes or label match scores.
var starts: Array[float] = []
func build(events: Array, duration: float) -> void:
	starts.clear()
	for event in events:
		if event.type == "bomb_reset" and is_finite(event.time) and event.time >= 0 and event.time <= duration:
			starts.append(float(event.time))
	starts.sort()
	var unique: Array[float] = []
	for time in starts:
		if unique.is_empty() or time != unique[-1]: unique.append(time)
	starts = unique
func current_index(seconds: float) -> int:
	var low := 0
	var high := starts.size()
	while low < high:
		var middle := (low + high) / 2
		if starts[middle] <= seconds: low = middle + 1
		else: high = middle
	return low - 1
func target(seconds: float, direction: int) -> float:
	var index := current_index(seconds) + direction
	return starts[index] if index >= 0 and index < starts.size() else -1.0
