extends Node
## Autoload shared between the touch UI (TouchControls) and PlayerInput.
## TouchControls writes virtual stick/button state here every physics frame;
## PlayerInput reads it INSTEAD of keyboard/mouse/gamepad while touch_active.
## touch_active latches on the first real screen touch (or immediately on
## Android), so desktop keyboard+mouse keeps working until a touch happens.

var touch_active: bool = false

## Left stick: movement direction, already deadzoned and normalized-ish (-1..1).
var move_axis := Vector2.ZERO
## Right stick: aim direction, zero inside the deadzone.
var aim_axis := Vector2.ZERO
## Auto-fire: true while the aim stick is held beyond its deadzone.
var shoot := false
## Dash button held.
var dash := false
## Weapon switch edge: -1 = next, +1 = previous, 0 = none.
## PlayerInput consumes it (resets to 0) once per press.
var switch_dir := 0


func _ready() -> void:
	touch_active = OS.has_feature("android")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch_active = true


## Drop all held state (used when pausing / hiding the touch UI).
func clear() -> void:
	move_axis = Vector2.ZERO
	aim_axis = Vector2.ZERO
	shoot = false
	dash = false
	switch_dir = 0
