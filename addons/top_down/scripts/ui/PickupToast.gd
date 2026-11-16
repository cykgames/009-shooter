extends Node
## Unarmed onboarding toast: shows "PICK UP A WEAPON TO SHOOT" while the
## player's weapon inventory is empty, hides as soon as a weapon is picked up.
## Read-only observer of the inventory resource; does not touch weapon stats.

@export var inventory_resource: ItemCollectionResource
@export var label: Label


func _ready() -> void:
	if inventory_resource == null or label == null:
		return
	inventory_resource.updated.connect(_refresh)
	_refresh()


func _refresh() -> void:
	label.visible = inventory_resource.list.is_empty()
