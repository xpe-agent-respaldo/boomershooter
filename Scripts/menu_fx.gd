class_name MenuFX
extends RefCounted

## Animaciones suaves de hover/focus para los menus, estilo retro limpio.
## Se aplica recursivamente a todos los Button bajo el nodo raiz indicado.

const HOVER_SCALE := 1.035
const HOVER_TINT := Color(1.18, 1.12, 1.0)
const TIME_IN := 0.12
const TIME_OUT := 0.2


static func attach(root: Node) -> void:
	if root == null:
		return
	_attach_recursive(root)


static func _attach_recursive(node: Node) -> void:
	if node is Button:
		_decorate_button(node as Button)
	for child in node.get_children():
		_attach_recursive(child)


static func _decorate_button(button: Button) -> void:
	if button.has_meta("menu_fx"):
		return
	button.set_meta("menu_fx", true)
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(func(): _tween_to(button, true))
	button.mouse_exited.connect(func(): _tween_to(button, false))
	button.focus_entered.connect(func(): _tween_to(button, true))
	button.focus_exited.connect(func(): _tween_to(button, false))


static func _tween_to(button: Button, entered: bool) -> void:
	if not button.is_inside_tree():
		return
	var pivot := button.size * 0.5
	if button.pivot_offset != pivot:
		button.pivot_offset = pivot
	var tween := button.create_tween()
	tween.set_parallel(true)
	var target_scale := HOVER_SCALE if entered else 1.0
	var target_tint := HOVER_TINT if entered else Color.WHITE
	tween.tween_property(button, "scale", Vector2(target_scale, target_scale), TIME_IN if entered else TIME_OUT)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate", target_tint, TIME_IN if entered else TIME_OUT)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

