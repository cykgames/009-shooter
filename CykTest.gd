extends Node
## W2 debug telemetry + receipt rings for 009-shooter (P1+P2 plan v4.17 W2b).
## [CYKTEST] {json} every 0.25 s: canonical payload ts/ms/scene/running/time/
## stick[2]=move/pos[3]=(x,y,0)/aim[2]/shoot/fire_count/fps + optional up
## (SystemClock.uptimeMillis common domain) + session_id (64-bit nonce+pid+
## ready_up) + ring watermarks. [CYKTEST-RING] independent marker <=900 bytes:
## input/route/apply rings (009 has NO jump_log / J bridge).
## running = room gameplay active (fight_mode_resource.value) AND
## player_health.is_dead==false AND not paused (pause_resource.value).
## touch_active is ONLY an input-mode latch, never a run proof (F17).
## time accumulates delta only while running. Test-only observers: never change
## routing/consumption/gameplay. PROCESS_MODE_ALWAYS drains rings during pause.
## Author: cykbot9 (AI agent).

const PERIOD := 0.25
const RING_LINE_MAX := 900
const CAP_INPUT := 512
const CAP_ROUTE := 256
const CAP_APPLY := 256

const PLAYER_REF_PATH := "res://addons/top_down/resources/ReferenceNodeResources/player_reference.tres"
const HEALTH_PATH := "res://addons/top_down/resources/health_resource/player_health.tres"
const PAUSE_PATH := "res://addons/top_down/resources/global_resources/pause_resource.tres"
const FIGHT_PATH := "res://addons/top_down/resources/arena_resources/fight_mode_resource.tres"

var input_ring: CykRing
var route_ring: CykRing
var apply_ring: CykRing

var session_id := ""
var _nonce: int = 0
var _pid: int = -1
var _ready_up: int = -1
var _java_clock = null
var _acc := 0.0
var _time := 0.0
var bullet_count := 0

var _player_ref = null
var _health = null
var _pause = null
var _fight = null
var _discovery_ok := false

var _version := {"move": 0, "aim": 0, "shoot": 0}
var _last_copied := {"move": 0, "aim": 0, "shoot": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("cyktest")
	input_ring = CykRing.new("input_log", CAP_INPUT)
	route_ring = CykRing.new("route_log", CAP_ROUTE)
	apply_ring = CykRing.new("apply_log", CAP_APPLY)
	_init_session()
	_init_discovery()


func _init_session() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hi: int = rng.randi()
	var lo: int = rng.randi()
	_nonce = ((hi << 32) | (lo & 0xFFFFFFFF)) & 0xFFFFFFFFFFFFFFFF
	if Engine.has_singleton("JavaClassWrapper"):
		var jw = Engine.get_singleton("JavaClassWrapper")
		var sc = jw.wrap("android.os.SystemClock")
		if sc != null:
			_java_clock = sc
		var pr = jw.wrap("android.os.Process")
		if pr != null:
			_pid = int(pr.myPid())
	_ready_up = up()
	session_id = "%016x:%d:%d" % [_nonce, _pid, _ready_up]


func _init_discovery() -> void:
	# Startup precondition assert: the state-source resources must load. The
	# player NODE is discovered dynamically (it spawns after boot); a missing
	# resource is a loud failure, never a silent select-style downgrade (F18).
	_player_ref = load(PLAYER_REF_PATH)
	_health = load(HEALTH_PATH)
	_pause = load(PAUSE_PATH)
	_fight = load(FIGHT_PATH)
	_discovery_ok = _player_ref != null and _health != null and _pause != null and _fight != null
	if not _discovery_ok:
		push_error("CykTest 009 discovery FAILED: missing state-source resource")
		print("[CYKTEST-DISCOVERY-FAIL] player_ref=%s health=%s pause=%s fight=%s" % [
			_player_ref != null, _health != null, _pause != null, _fight != null])


func up() -> int:
	if _java_clock != null:
		return int(_java_clock.uptimeMillis())
	return -1


func player_node():
	if _player_ref != null:
		return _player_ref.node
	return null


func is_running() -> bool:
	if not _discovery_ok:
		return false
	var fight: bool = _fight.value
	var dead: bool = _health.is_dead
	var paused: bool = _pause.value
	return fight and (not dead) and (not paused)


## test-only bullet counter: ProjectileSpawner.spawn() calls this per actual
## projectile instance; count only spawners under the player subtree (player
## bullets, not enemy projectiles).
func note_bullet(spawner: Node) -> void:
	var pn = player_node()
	if pn != null and spawner != null and pn.is_ancestor_of(spawner):
		bullet_count += 1


func lookup_input_seq(instance_id: int) -> int:
	var e = input_ring.find("e", instance_id)
	return int(e["s"]) if e != null else -1


func route_push(role: String, source_seq: int, stable_id: int, accepted: bool, value) -> int:
	if accepted:
		_version[role] = int(_version[role]) + 1
	route_ring.push({"u": up(), "src": source_seq, "id": stable_id, "role": role,
		"acc": accepted, "ver": int(_version[role]), "val": value})
	return int(_version[role])


func apply_push(role: String, source_seq: int, value) -> void:
	if int(_version[role]) <= int(_last_copied[role]):
		return
	_last_copied[role] = int(_version[role])
	apply_ring.push({"u": up(), "src": source_seq, "ver": int(_version[role]),
		"role": role, "val": value, "st": "copied"})


func _input(event: InputEvent) -> void:
	var kind := ""
	var idx := 0
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		kind = "touch_down" if event.pressed else "touch_up"
		idx = event.index
		pos = event.position
	elif event is InputEventScreenDrag:
		kind = "drag"
		idx = event.index
		pos = event.position
	elif event is InputEventMouseButton:
		kind = "mouse_down" if event.pressed else "mouse_up"
		pos = event.position
	elif event is InputEventMouseMotion:
		kind = "mouse_motion"
		pos = event.position
	else:
		return
	var disp := get_viewport().get_screen_transform() * pos
	var seq := input_ring.push({"u": up(), "k": kind, "i": idx, "d": event.device,
		"x": snappedf(disp.x, 0.01), "y": snappedf(disp.y, 0.01),
		"e": event.get_instance_id()})
	event.set_meta("cyk_seq", seq)


func _process(delta: float) -> void:
	if is_running():
		_time += delta
	_drain_ring(input_ring)
	_drain_ring(route_ring)
	_drain_ring(apply_ring)
	_acc += delta
	if _acc < PERIOD:
		return
	_acc = 0.0
	_emit_sample()


func _ring_line(name: String, entries: Array) -> String:
	var lo: int = entries[0]["s"]
	var hi: int = entries[entries.size() - 1]["s"]
	return "[CYKTEST-RING] " + JSON.stringify(
		{"sid": session_id, "ring": name, "seq_range": [lo, hi], "entries": entries})


func _drain_ring(r: CykRing) -> void:
	var pend := r.pending()
	if pend.is_empty():
		return
	var entries := []
	for e in pend:
		var trial := entries + [e]
		if entries.size() > 0 and len(_ring_line(r.ring_name, trial).to_utf8_buffer()) > RING_LINE_MAX:
			print(_ring_line(r.ring_name, entries))
			r.mark_emitted(int(entries[entries.size() - 1]["s"]))
			entries = [e]
		else:
			entries = trial
	if entries.size() > 0:
		print(_ring_line(r.ring_name, entries))
		r.mark_emitted(int(entries[entries.size() - 1]["s"]))


func _emit_sample() -> void:
	var d := {"ts": Time.get_unix_time_from_system(), "ms": Time.get_ticks_msec()}
	var u := up()
	if u >= 0:
		d["up"] = u
	d["session_id"] = session_id
	var pn = player_node()
	var running := is_running()
	d["running"] = running
	d["time"] = snappedf(_time, 0.01)
	d["stick"] = [snappedf(TouchState.move_axis.x, 0.001), snappedf(TouchState.move_axis.y, 0.001)]
	d["aim"] = [snappedf(TouchState.aim_axis.x, 0.001), snappedf(TouchState.aim_axis.y, 0.001)]
	d["shoot"] = TouchState.shoot
	d["fire_count"] = bullet_count
	if pn != null and is_instance_valid(pn):
		d["scene"] = "play"
		var gp: Vector2 = pn.global_position
		d["pos"] = [snappedf(gp.x, 0.01), snappedf(gp.y, 0.01), 0.0]
	else:
		d["scene"] = "menu"
		d["pos"] = [0.0, 0.0, 0.0]
	d["fps"] = snappedf(Performance.get_monitor(Performance.TIME_FPS), 0.1)
	# W2e test-only forward display transform evidence (viewport->screen):
	# origin + basis columns. The host applies this to injector display px so
	# atom coords land in the same domain as the input_log receipts (which are
	# get_screen_transform() * event.position). Generic; no device facts.
	var xf := get_viewport().get_screen_transform()
	d["xform"] = [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01),
		snappedf(xf.x.x, 0.0001), snappedf(xf.x.y, 0.0001),
		snappedf(xf.y.x, 0.0001), snappedf(xf.y.y, 0.0001)]
	d["wm"] = {"input": input_ring.watermark(), "route": route_ring.watermark(),
		"apply": apply_ring.watermark()}
	print("[CYKTEST] " + JSON.stringify(d))