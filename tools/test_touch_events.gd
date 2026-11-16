extends Node
## Real-event touch routing regression for 009-shooter.
## Unlike test_shooter.gd (which drives the stick API directly), this harness
## injects REAL InputEventScreenTouch / InputEventScreenDrag through
## Input.parse_input_event, so the full pipeline is exercised:
##   finger event -> GUI (emulated mouse) -> _unhandled_input -> stick
##   -> TouchState -> PlayerInput -> InputResource -> player motion / fire.
## Reproduces the reported field bug: left disc press dead (only presses
## OUTSIDE the disc move), right disc completely dead.
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tools/test_touch_events.tscn
## Prints TOUCH_EVENTS_PASS / TOUCH_EVENTS_FAIL, exit code 0 / 1.

const ROOM_PATH := "res://addons/top_down/scenes/levels/room_0.tscn"
const ACTION_RES_PATH := "res://addons/top_down/resources/global_resources/action_resource.tres"
const PLAYER_REF_PATH := "res://addons/top_down/resources/ReferenceNodeResources/player_reference.tres"

var _fails := 0


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		print("TOUCH_FAIL: ", what)
	else:
		print("TOUCH_OK: ", what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _touch(index: int, window_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = window_pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, window_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = window_pos
	ev.relative = Vector2.ZERO
	Input.parse_input_event(ev)


## Window-space position of a stick-local point (same transform the drawing
## uses, so this is exactly where the disc appears on screen). Events injected
## via Input.parse_input_event are window coords; the input pipeline converts
## them to design coords (divides by the stretch scale) before _unhandled_input.
func _window_pos(tc: TouchControls, stick: Joystick, local: Vector2) -> Vector2:
	var canvas := tc.get_global_transform_with_canvas() * (stick.position + local)
	return get_viewport().get_screen_transform() * canvas


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("TOUCH_EVENTS_FAIL watchdog timeout")
		get_tree().quit(1))
	_run()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		print("TOUCH_INFO root_unhandled TOUCH idx=%d pos=%s pressed=%s" % [event.index, str(event.position), str(event.pressed)])
	elif event is InputEventScreenDrag:
		print("TOUCH_INFO root_unhandled DRAG idx=%d pos=%s" % [event.index, str(event.position)])


func _run() -> void:
	var action_res: ActionResource = load(ACTION_RES_PATH)
	action_res.load_resource()

	# Mimic a wide-aspect phone (A54: 2340x1080, keep_height -> design 585x270).
	# Half resolution keeps the same 19.5:9 aspect; headless window is virtual.
	get_window().size = Vector2i(1170, 540)
	await _frames(5)
	print("TOUCH_INFO window=%s design=%s" % [str(get_window().size), str(get_viewport().get_visible_rect().size)])

	var room: Node = load(ROOM_PATH).instantiate()
	add_child(room)
	await _frames(15)

	var player_ref: ReferenceNodeResource = load(PLAYER_REF_PATH)
	var player: Node2D = player_ref.node
	_expect(player != null, "player spawned")
	if player == null:
		_finish()
		return
	var input_res: InputResource = player.get_node("ResourceNode").get_resource("input")

	var tc: TouchControls = room.get_node("UI/TouchControls")
	_expect(tc != null, "TouchControls present")

	# Diagnostics: any fullscreen STOP control above/below the HUD eats touches.
	var flash: ColorRect = room.get_node_or_null("ScreenEffects/ColorFlash")
	if flash != null:
		print("TOUCH_INFO ColorFlash mouse_filter=%d (0=STOP 1=PASS 2=IGNORE) rect=%s" % [flash.mouse_filter, str(flash.get_global_rect())])

	# Flip TouchState.touch_active with a real neutral touch (top-center).
	var neutral := get_viewport().get_screen_transform() * tc.get_global_transform_with_canvas() * Vector2(292, 8)
	_touch(0, neutral, true)
	await _frames(3)
	_touch(0, neutral, false)
	await _frames(3)
	_expect(TouchState.touch_active, "touch_active latched via real screen touch")
	_expect(tc.visible, "TouchControls visible")
	await _frames(3)

	var ms: Joystick = tc.move_stick
	var as_: Joystick = tc.aim_stick
	print("TOUCH_INFO move disc window=%s aim disc window=%s" % [
		str(_window_pos(tc, ms, ms.home_center)), str(_window_pos(tc, as_, as_.home_center))])

	# --- LEFT stick: press ON the disc center, then drag right ---
	var lp := _window_pos(tc, ms, ms.home_center)
	_touch(0, lp, true)
	await _frames(3)
	var focus := get_viewport().gui_get_focus_owner()
	var hovered := get_viewport().gui_get_hovered_control()
	print("TOUCH_INFO after left-center press: active=%s gui_focus=%s hovered=%s" % [str(ms.active), str(focus), str(hovered)])
	if focus != null:
		print("TOUCH_INFO focus path=%s visible=%s rect=%s" % [str(focus.get_path()), str(focus.is_visible_in_tree()), str(focus.get_global_rect())])
	if hovered != null:
		print("TOUCH_INFO hovered path=%s filter=%d rect=%s" % [str(hovered.get_path()), hovered.mouse_filter, str(hovered.get_global_rect())])
	_expect(ms.active, "LEFT press ON disc activates stick")
	_drag(0, _window_pos(tc, ms, ms.home_center + Vector2(22, 0)))
	await _frames(3)
	_expect(ms.output.x > 0.5, "LEFT drag on disc steers (output.x=%.2f)" % ms.output.x)
	_expect(TouchState.move_axis.x > 0.5, "LEFT drag reaches TouchState.move_axis")
	var p0 := player.global_position
	await _frames(30)
	_expect(player.global_position.distance_to(p0) > 5.0, "LEFT drag moves player (%.1f px)" % player.global_position.distance_to(p0))
	_touch(0, lp, false)
	await _frames(3)
	_expect(not ms.active and ms.output == Vector2.ZERO, "LEFT release zeroes")

	# --- LEFT stick: press OUTSIDE the disc (the field workaround) ---
	var lo := _window_pos(tc, ms, ms.home_center + Vector2(55, 0))
	_touch(0, lo, true)
	await _frames(3)
	_expect(ms.active, "LEFT press OUTSIDE disc activates stick")
	_expect(ms.output.x > 0.9, "LEFT outside press = immediate full magnitude")
	_touch(0, lo, false)
	await _frames(3)

	# --- RIGHT stick: press ON the disc center, then drag right ---
	var rp := _window_pos(tc, as_, as_.home_center)
	_touch(0, rp, true)
	await _frames(3)
	focus = get_viewport().gui_get_focus_owner()
	print("TOUCH_INFO after right-center press: active=%s gui_focus=%s" % [str(as_.active), str(focus)])
	_expect(as_.active, "RIGHT press ON disc activates stick")
	_drag(0, _window_pos(tc, as_, as_.home_center + Vector2(22, 0)))
	await _frames(3)
	_expect(as_.output.x > 0.5, "RIGHT drag on disc steers (output.x=%.2f)" % as_.output.x)
	_expect(TouchState.aim_axis.x > 0.5, "RIGHT drag reaches TouchState.aim_axis")
	_expect(TouchState.shoot, "RIGHT held beyond deadzone = auto-fire")
	_expect(input_res.action_1, "RIGHT auto-fire reaches InputResource")
	_touch(0, rp, false)
	await _frames(3)
	_expect(not as_.active and not TouchState.shoot, "RIGHT release stops fire")

	# --- RIGHT stick: press OUTSIDE the disc ---
	var ro := _window_pos(tc, as_, as_.home_center + Vector2(-55, 0))
	_touch(0, ro, true)
	await _frames(3)
	_expect(as_.active, "RIGHT press OUTSIDE disc activates stick")
	_expect(as_.output.length() > 0.9, "RIGHT outside press = immediate full magnitude")
	_touch(0, ro, false)
	await _frames(3)

	# --- Multi-touch: move + aim at the same time ---
	_touch(0, lp, true)
	_touch(1, rp, true)
	await _frames(2)
	_drag(0, _window_pos(tc, ms, ms.home_center + Vector2(0, 22)))
	_drag(1, _window_pos(tc, as_, as_.home_center + Vector2(22, 0)))
	await _frames(3)
	_expect(ms.active and as_.active, "MULTI both sticks held simultaneously")
	_expect(TouchState.move_axis.y > 0.5 and TouchState.aim_axis.x > 0.5, "MULTI move down + aim right independent")
	_touch(0, lp, false)
	_touch(1, rp, false)
	await _frames(3)

	_finish()


func _finish() -> void:
	print("TOUCH_EVENTS_SUMMARY fails=%d" % _fails)
	if _fails == 0:
		print("TOUCH_EVENTS_PASS")
	else:
		print("TOUCH_EVENTS_FAIL count=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)