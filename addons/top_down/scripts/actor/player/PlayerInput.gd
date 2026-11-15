class_name PlayerInput
extends Node

@export var enabled:bool = true

## Used for getting mouse local position
@export var position_node:Node2D

## Offset aim to the body to shoot at shadow collider (feet position)
@export var aim_offset:Vector2
@export var resource_node:ResourceNode
@export var action_resource:ActionResource

var input_resource:InputResource

func set_enabled(value:bool)->void:
	enabled = value
	set_physics_process(enabled)

func _ready()->void:
	input_resource = resource_node.get_resource("input")
	assert(input_resource != null)
	
	# Read input before mover
	process_physics_priority -= 1
	set_enabled(enabled)
	
	request_ready()

func _input(event:InputEvent)->void:
	# Touch mode: aim comes from the right virtual stick (TouchState), not
	# from the mouse emulated by touches. Keyboard/mouse stay live on desktop
	# until the first real screen touch flips TouchState.touch_active.
	if TouchState.touch_active:
		return
	if event is InputEventMouseMotion:
		action_resource.mouse_aim = true
		var aim_direction:Vector2 = position_node.get_local_mouse_position() + aim_offset
		input_resource.set_aim_direction(aim_direction.normalized())
		return
	# mark that mouse is not used
	if event.is_action(action_resource.aim_left_action):
		action_resource.mouse_aim = false
		return
	if event.is_action(action_resource.aim_right_action):
		action_resource.mouse_aim = false
		return
	if event.is_action(action_resource.aim_up_action):
		if event is InputEventJoypadMotion && abs(event.axis_value) < action_resource.aim_deadzone:
			return
		action_resource.mouse_aim = false
		return
	if event.is_action(action_resource.aim_down_action):
		if event is InputEventJoypadMotion && abs(event.axis_value) < action_resource.aim_deadzone:
			return
		action_resource.mouse_aim = false
		return

func _physics_process(_delta:float)->void:
	if TouchState.touch_active:
		_process_touch()
		return
	
	# Walking direction
	var _axis:Vector2 = Vector2(Input.get_axis(action_resource.left_action, action_resource.right_action), Input.get_axis(action_resource.up_action, action_resource.down_action))
	
	var _length:float = _axis.length()
	if _length > 0.01:
		_axis = _axis.normalized()
	
	input_resource.set_axis(_axis)
	
	# Aiming
	if !action_resource.mouse_aim:
		var _aim:Vector2 = Vector2(Input.get_axis(action_resource.aim_left_action, action_resource.aim_right_action), Input.get_axis(action_resource.aim_up_action, action_resource.aim_down_action))
		if _aim.length() > 0.01:
			input_resource.set_aim_direction(_aim.normalized())
	
	# Shooting
	input_resource.set_action(Input.is_action_pressed(action_resource.action_1_action))
	
	var weapon_switch_dir:int = int(Input.is_action_just_released(action_resource.previous_action)) - int(Input.is_action_just_released(action_resource.next_action))
	if weapon_switch_dir != 0:
		input_resource.set_switch_weapon(weapon_switch_dir)
	
	# Dashing
	input_resource.set_action_2(Input.is_action_pressed(action_resource.action_2_action))

## Touch twin-stick path: same InputResource writes as the keyboard/mouse
## path above, sourced from the TouchState autoload (written by TouchControls).
func _process_touch()->void:
	input_resource.set_axis(TouchState.move_axis)
	
	if TouchState.aim_axis.length_squared() > 0.0001:
		action_resource.mouse_aim = false
		input_resource.set_aim_direction(TouchState.aim_axis.normalized())
	
	# Auto-fire while the aim stick is held beyond its deadzone.
	input_resource.set_action(TouchState.shoot)
	
	if TouchState.switch_dir != 0:
		input_resource.set_switch_weapon(TouchState.switch_dir)
		TouchState.switch_dir = 0
	
	input_resource.set_action_2(TouchState.dash)
