class_name ItemPickup
extends Node2D

signal success

@export var item_resource:ItemResource

@export var icon_sprite:Sprite2D

@export var halo_sprite:Sprite2D

@export var data_transmitter:DataChannelTransmitter

@export var sound_resource:SoundResource

func _ready() -> void:
	if item_resource == null:
		return
	icon_sprite.texture = item_resource.icon
	_start_halo_pulse()
	
	var _transmission_resource:ItemTransmission = ItemTransmission.new()
	_transmission_resource.transmission_name = "item"
	_transmission_resource.item_resource = item_resource
	data_transmitter.transmission_resource = _transmission_resource
	
	data_transmitter.success.connect(prepare_remove, CONNECT_ONE_SHOT)
	data_transmitter.set_enabled(false)
	get_tree().physics_frame.connect(_delay_enable, CONNECT_ONE_SHOT)

## Pulsing ring under the drop so unarmed players can spot weapon pickups.
func _start_halo_pulse() -> void:
	if halo_sprite == null:
		return
	halo_sprite.scale = Vector2(0.85, 0.85)
	halo_sprite.modulate = Color(1, 1, 1, 0.45)
	var tw := create_tween().set_loops()
	tw.tween_property(halo_sprite, "scale", Vector2(1.25, 1.25), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(halo_sprite, "modulate:a", 0.95, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(halo_sprite, "scale", Vector2(0.85, 0.85), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(halo_sprite, "modulate:a", 0.45, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## delay to avoid triggering if overlap at spawn
func _delay_enable()->void:
	get_tree().physics_frame.connect(data_transmitter.set_enabled.bind(true), CONNECT_ONE_SHOT)

func prepare_remove()->void:
	data_transmitter.set_enabled(false)
	sound_resource.play_managed()
	success.emit()
	## TODO: DO proper VFX
	queue_free()
