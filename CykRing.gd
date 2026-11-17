class_name CykRing
extends RefCounted
## W2 test-only receipt ring (P1+P2 plan v4.17 W2b). Fixed-capacity ring buffer
## with a process-lifetime monotonic seq counter and an overflow counter that
## counts ONLY overwrites of not-yet-drained entries (data loss). Normal
## operation (drain keeps up) keeps overflow at 0; the host requires the
## run-window overflow delta == 0 (a historical overwrite before the run still
## rejects if it falls in the window). Short keys keep serialized lines small
## ([CYKTEST-RING] <= 900 bytes). Read-only telemetry: never touches gameplay.

var capacity: int
var ring_name: String
var _buf: Array = []
var _seq: int = 0          # absolute seq assigned so far (never resets)
var _overflow: int = 0     # process-lifetime count of un-drained overwrites
var _emitted: int = 0      # drain cursor: highest seq emitted


func _init(name: String, cap: int) -> void:
	ring_name = name
	capacity = cap
	_buf.resize(cap)


func push(entry: Dictionary) -> int:
	_seq += 1
	entry["s"] = _seq
	var idx := (_seq - 1) % capacity
	var old = _buf[idx]
	if old != null and old["s"] > _emitted:
		_overflow += 1     # overwriting an entry the host has not seen = loss
	_buf[idx] = entry
	return _seq


func seq() -> int:
	return _seq


func overflow() -> int:
	return _overflow


func watermark() -> Dictionary:
	var oldest := maxi(1, _seq - capacity + 1)
	return {"ring": ring_name, "capacity": capacity, "oldest_seq": oldest,
		"newest_seq": _seq, "overflow": _overflow, "count": mini(_seq, capacity)}


func pending() -> Array:
	## Entries with seq > drain cursor that still survive in the buffer, in
	## ascending seq order. A hole (overwritten un-drained entry) is skipped;
	## the host detects the gap via seq_range + overflow delta.
	var out := []
	var lo := maxi(_emitted + 1, maxi(1, _seq - capacity + 1))
	for s in range(lo, _seq + 1):
		var e = _buf[(s - 1) % capacity]
		if e != null and e["s"] == s:
			out.append(e)
	return out


func mark_emitted(seq: int) -> void:
	_emitted = maxi(_emitted, seq)


func find(field: String, value):
	## Scan the live buffer for an entry whose field == value (exact event
	## identity lookup by instance id). Returns the entry dict or null.
	for e in _buf:
		if e != null and e.has(field) and e[field] == value:
			return e
	return null