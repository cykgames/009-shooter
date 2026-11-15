extends Node
## Hides keyboard-rebinding entry points on touch devices (the rebinding
## screen only makes sense with a keyboard/mouse). Instanced in title.tscn
## and pause.tscn; each instance points at its scene's "Controls" button.

@export var controls_button: NodePath


func _ready() -> void:
	if not TouchState.touch_active:
		return
	if controls_button.is_empty():
		return
	var node: Node = get_node_or_null(controls_button)
	if node != null:
		node.hide()
