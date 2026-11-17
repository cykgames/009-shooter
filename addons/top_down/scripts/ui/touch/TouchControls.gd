class_name TouchControls
extends Control
## Mobile twin-stick overlay, instanced inside the arena HUD CanvasLayer.
## Left stick = movement, right stick = aim + AUTO-FIRE while held beyond the
## deadzone, plus DASH / weapon-switch / pause buttons with 1.5x hit radii.
## All routing goes through _unhandled_input with explicit touch-index
## tracking (multi-touch safe: move + aim + dash at the same time). Buttons
## and sticks are pure drawing surfaces (MOUSE_FILTER_IGNORE) so menu Buttons
## elsewhere keep receiving emulated-mouse touches.
## Writes virtual input into the TouchState autoload; PlayerInput reads it
## instead of keyboard/mouse while TouchState.touch_active. Hidden while
## paused (pause menu Buttons are touch-usable via mouse emulation).

## Right-edge offsets (design units measured FROM the right edge of the
## viewport). At the 480-wide 16:9 design these reproduce the original
## fixed centers (444/356/452); on wider aspects the whole right cluster
## tracks the right edge instead of floating near screen center.
const DASH_RIGHT := 36.0
const SWITCH_RIGHT := 124.0
const PAUSE_RIGHT := 28.0
const BUTTON_Y := 122.0
const PAUSE_Y := 18.0
## Touch targets: the P1 pass measured DASH/WPN at 109 px on a 1080p phone
## (radius 16 design units x ~3.2 scale). Radius 20 renders ~128 px and, with
## HIT_SCALE, accepts touches up to ~193 px across.
const BUTTON_RADIUS := 20.0
const PAUSE_RADIUS := 16.0
## Same generous hit factor as the joystick grab radius.
const HIT_SCALE := 1.5
## Aim stick zone width (matches touch_controls.tscn offset span 240..480).
const AIM_ZONE_W := 240.0
const AIM_ZONE_TOP := 120.0
const AIM_ZONE_H := 150.0

var dash_center := Vector2(444, 122)
var switch_center := Vector2(356, 122)
var pause_center := Vector2(452, 18)
var _last_w := -1.0

const ACTION_RESOURCE_PATH := "res://addons/top_down/resources/global_resources/action_resource.tres"
const PAUSE_RESOURCE_PATH := "res://addons/top_down/resources/global_resources/pause_resource.tres"

var action_resource: ActionResource
var pause_bool_resource: BoolResource

@onready var move_stick: Joystick = $MoveStick
@onready var aim_stick: Joystick = $AimStick

var _dash_touch := -1
var _switch_touch := -1
var _pause_touch := -1
var _move_src := -1   # W2: last move route source arrival seq
var _aim_src := -1    # W2: last aim route source arrival seq


func _ready() -> void:
	action_resource = load(ACTION_RESOURCE_PATH)
	pause_bool_resource = load(PAUSE_RESOURCE_PATH)
	assert(action_resource != null)
	assert(pause_bool_resource != null)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_bool_resource.updated.connect(_on_pause_changed)
	visible = TouchState.touch_active and not pause_bool_resource.value
	_relayout()


## Right-anchor the aim stick zone and the DASH/WPN/pause cluster to the
## viewport's right edge so wide aspects (e.g. 19.5:9 phones) keep the aim
## thumb at the bottom-right instead of drifting toward screen center.
## At the 480-wide 16:9 design this is identical to the original layout.
## NOTE: the AimStick zone is ALSO right-anchored in touch_controls.tscn
## (anchor_left/right=1, offsets -240..0) so it tracks the right edge from
## instantiation even if this runtime assignment is deferred by layout.
func _relayout() -> void:
	var w := size.x
	if w <= 0.0:
		return
	dash_center = Vector2(w - DASH_RIGHT, BUTTON_Y)
	switch_center = Vector2(w - SWITCH_RIGHT, BUTTON_Y)
	pause_center = Vector2(w - PAUSE_RIGHT, PAUSE_Y)
	aim_stick.position = Vector2(w - AIM_ZONE_W, AIM_ZONE_TOP)
	aim_stick.size = Vector2(AIM_ZONE_W, AIM_ZONE_H)
	# Homes assigned at runtime: scene property overrides for these were
	# silently dropped in compiled-script APK exports (A54, 2026-11-16).
	move_stick.set_home(Vector2(66, 82))
	aim_stick.set_home(Vector2(174, 82))
	queue_redraw()


func _on_pause_changed() -> void:
	var show := TouchState.touch_active and not pause_bool_resource.value
	if visible == show:
		return
	visible = show
	if not show:
		_release_all()


func _release_all() -> void:
	move_stick.force_release()
	aim_stick.force_release()
	_dash_touch = -1
	_switch_touch = -1
	_pause_touch = -1
	TouchState.clear()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# Re-anchor on first valid layout and on any aspect/resize change.
	if size.x != _last_w:
		_last_w = size.x
		_relayout()
	# First touch on a touch-capable desktop flips TouchState.touch_active.
	var show := TouchState.touch_active and not pause_bool_resource.value
	if visible != show:
		visible = show
		if not show:
			_release_all()
	if not visible:
		return
	TouchState.move_axis = move_stick.output
	TouchState.aim_axis = aim_stick.output
	TouchState.shoot = aim_stick.output.length_squared() > 0.0001
	# W2 test-only applied receipts (consumer copy point, edge-triggered).
	CykTest.apply_push("move", _move_src, [move_stick.output.x, move_stick.output.y])
	CykTest.apply_push("aim", _aim_src, [aim_stick.output.x, aim_stick.output.y])
	CykTest.route_push("shoot", _aim_src, 1, true, TouchState.shoot)
	CykTest.apply_push("shoot", _aim_src, TouchState.shoot)


## Local point for a window-space touch position (stretch-aware).
func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _hit(p: Vector2, c: Vector2, r: float) -> bool:
	return p.distance_to(c) <= r * HIT_SCALE


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		var p := _local(touch.position)
		if touch.pressed:
			_press(p, touch.index, event)
		else:
			_release(p, touch.index, event)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		var p := _local(drag.position)
		if drag.index == move_stick.touch_index():
			move_stick.drag_to(p - move_stick.position)
			_move_src = CykTest.lookup_input_seq(drag.get_instance_id())
			CykTest.route_push("move", _move_src, 0, true, [move_stick.output.x, move_stick.output.y])
		elif drag.index == aim_stick.touch_index():
			aim_stick.drag_to(p - aim_stick.position)
			_aim_src = CykTest.lookup_input_seq(drag.get_instance_id())
			CykTest.route_push("aim", _aim_src, 1, true, [aim_stick.output.x, aim_stick.output.y])


func _press(p: Vector2, index: int, event: InputEvent) -> void:
	# Buttons win over stick zones (they sit above the aim zone).
	if _hit(p, pause_center, PAUSE_RADIUS):
		_pause_touch = index
		_toggle_pause()
		queue_redraw()
		return
	if _hit(p, dash_center, BUTTON_RADIUS):
		_dash_touch = index
		TouchState.dash = true
		queue_redraw()
		return
	if _hit(p, switch_center, BUTTON_RADIUS):
		_switch_touch = index
		TouchState.switch_dir = -1
		queue_redraw()
		return
	var lp := p - move_stick.position
	if move_stick.touch_index() == -1 and move_stick.can_activate(lp):
		move_stick.press_at(lp, index)
		_move_src = CykTest.lookup_input_seq(event.get_instance_id())
		CykTest.route_push("move", _move_src, 0, true, [move_stick.output.x, move_stick.output.y])
		return
	var rp := p - aim_stick.position
	if aim_stick.touch_index() == -1 and aim_stick.can_activate(rp):
		aim_stick.press_at(rp, index)
		_aim_src = CykTest.lookup_input_seq(event.get_instance_id())
		CykTest.route_push("aim", _aim_src, 1, true, [aim_stick.output.x, aim_stick.output.y])


func _release(_p: Vector2, index: int, event: InputEvent) -> void:
	# W2 test-only release route receipts: releasing a stick writes output->0,
	# a real routed write that must carry a route token (src == the touch_up
	# arrival seq) so the host chain can link the UP atom (per-role namespace).
	if index == move_stick.touch_index():
		move_stick.release_touch()
		var src := CykTest.lookup_input_seq(event.get_instance_id())
		CykTest.route_push("move", src, 0, true, [move_stick.output.x, move_stick.output.y])
	elif index == aim_stick.touch_index():
		aim_stick.release_touch()
		var src := CykTest.lookup_input_seq(event.get_instance_id())
		CykTest.route_push("aim", src, 1, true, [aim_stick.output.x, aim_stick.output.y])
	if index == _dash_touch:
		_dash_touch = -1
		TouchState.dash = false
		queue_redraw()
	elif index == _switch_touch:
		_switch_touch = -1
		queue_redraw()
	elif index == _pause_touch:
		_pause_touch = -1
		queue_redraw()


## Inject the project's pause action so PausingManager handles menu depth
## (resume at root, back inside submenus) exactly like the keyboard does.
func _toggle_pause() -> void:
	var press := InputEventAction.new()
	press.action = action_resource.pause_action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action_resource.pause_action
	release.pressed = false
	Input.parse_input_event(release)


func _draw_button(c: Vector2, r: float, held: bool, label: String) -> void:
	var base_a := 0.85 if held else 0.55
	var rim_a := 0.95 if held else 0.45
	var fill := Color(0.10, 0.34, 0.72, base_a) if held else Color(0.07, 0.10, 0.16, base_a)
	draw_circle(c, r, fill)
	draw_arc(c, r - 0.5, 0.0, TAU, 32, Color(0.85, 0.92, 1.0, rim_a), 1.0, true)
	var font := ThemeDB.fallback_font
	var col := Color(1, 1, 1, 0.9 if held else 0.65)
	draw_string(font, c + Vector2(-r, 2.5), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 7, col)


func _draw_pause(c: Vector2, r: float, held: bool) -> void:
	var base_a := 0.85 if held else 0.55
	var fill := Color(0.10, 0.34, 0.72, base_a) if held else Color(0.07, 0.10, 0.16, base_a)
	draw_circle(c, r, fill)
	draw_arc(c, r - 0.5, 0.0, TAU, 32, Color(0.85, 0.92, 1.0, 0.95 if held else 0.45), 1.0, true)
	var col := Color(1, 1, 1, 0.9 if held else 0.65)
	draw_rect(Rect2(c + Vector2(-4.0, -4.0), Vector2(2.5, 8.0)), col)
	draw_rect(Rect2(c + Vector2(1.5, -4.0), Vector2(2.5, 8.0)), col)


func _draw() -> void:
	_draw_button(dash_center, BUTTON_RADIUS, _dash_touch != -1, "DASH")
	_draw_button(switch_center, BUTTON_RADIUS, _switch_touch != -1, "WPN")
	_draw_pause(pause_center, PAUSE_RADIUS, _pause_touch != -1)
