extends Node
## Touch-only menu adjustments, instanced in title.tscn and pause.tscn:
## 1. Hides keyboard-rebinding entry points (the rebinding screen only makes
##    sense with a keyboard/mouse); each instance points at its scene's
##    "Controls" button.
## 2. Optionally insets a MarginContainer below the Android status bar via
##    the display safe area (set safe_area_margin; empty = skip, so the
##    pause.tscn instance keeps its old behavior).

@export var controls_button: NodePath
@export var safe_area_margin: NodePath

## Cap the status-bar inset (base units) so an unusually large system inset
## can never push the menu back off the bottom of the screen.
const MAX_INSET := 36.0


func _ready() -> void:
	if not TouchState.touch_active:
		return
	if not controls_button.is_empty():
		var node: Node = get_node_or_null(controls_button)
		if node != null:
			node.hide()
	if not safe_area_margin.is_empty():
		var mc := get_node_or_null(safe_area_margin) as MarginContainer
		if mc != null:
			_apply_safe_area_top(mc)


## Push the container's top margin below the system status bar / notch.
## Safe area and window size are in screen pixels; convert to the stretched
## base units the UI layout uses. No-op when the window already avoids the
## system bars (safe area top == window top).
func _apply_safe_area_top(mc: MarginContainer) -> void:
	var win := get_window()
	var safe := DisplayServer.get_display_safe_area()
	var inset_px := maxi(0, safe.position.y - win.position.y)
	if inset_px <= 0:
		return
	var base_h := get_viewport().get_visible_rect().size.y
	var inset := minf(float(inset_px) * base_h / float(win.size.y), MAX_INSET)
	var cur := mc.get_theme_constant("margin_top")
	mc.add_theme_constant_override("margin_top", int(ceilf(cur + inset)))