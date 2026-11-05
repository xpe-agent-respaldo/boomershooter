extends Control

# Touch foundation for future Android/iOS exports. It is intentionally hidden on
# desktop so keyboard, mouse and controller input are never affected.
const MOVE_RADIUS := 108.0
const ACTION_RADIUS := 42.0

var _touches: Dictionary = {}
var _move_vector := Vector2.ZERO
var _aim_touch_id := -1
var _player: Player


func _ready() -> void:
	visible = OS.has_feature("mobile")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not visible:
		set_process(false)
		return
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var viewport_size := size
	var move_center := Vector2(142.0, viewport_size.y - 142.0)
	var fire_center := Vector2(viewport_size.x - 118.0, viewport_size.y - 136.0)
	draw_circle(move_center, MOVE_RADIUS, Color(0.08, 0.04, 0.1, 0.42))
	draw_arc(move_center, MOVE_RADIUS, 0.0, TAU, 36, Color(1.0, 0.34, 0.12, 0.78), 3.0)
	draw_circle(move_center + _move_vector * MOVE_RADIUS, 34.0, Color(1.0, 0.5, 0.16, 0.48))
	draw_circle(fire_center, 64.0, Color(0.78, 0.12, 0.06, 0.5))
	draw_arc(fire_center, 64.0, 0.0, TAU, 28, Color(1.0, 0.74, 0.28, 0.88), 3.0)
	draw_string(ThemeDB.fallback_font, fire_center + Vector2(-23, 6), "FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	_draw_action(viewport_size - Vector2(250, 250), "JUMP")
	_draw_action(viewport_size - Vector2(90, 275), "CROUCH")
	_draw_action(viewport_size - Vector2(330, 105), "RELOAD")


func _draw_action(center: Vector2, label: String) -> void:
	draw_circle(center, ACTION_RADIUS, Color(0.11, 0.09, 0.18, 0.64))
	draw_arc(center, ACTION_RADIUS, 0.0, TAU, 24, Color(0.8, 0.75, 1.0, 0.82), 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-24, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_handle_touch_press(event.index, event.position)
		else:
			_touches.erase(event.index)
			if event.index == _aim_touch_id:
				_aim_touch_id = -1
			_update_mobile_actions()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if event.index == _aim_touch_id and _player:
			_player._rotation_input = -event.relative.x * 0.32
			_player._tilt_input = -event.relative.y * 0.22
		_update_mobile_actions()


func _handle_touch_press(touch_id: int, position: Vector2) -> void:
	var viewport_size := size
	var fire_center := Vector2(viewport_size.x - 118.0, viewport_size.y - 136.0)
	if position.distance_to(fire_center) <= 74.0:
		Input.action_press("attack")
		return
	if position.distance_to(viewport_size - Vector2(250, 250)) <= ACTION_RADIUS:
		Input.action_press("jump")
		return
	if position.distance_to(viewport_size - Vector2(90, 275)) <= ACTION_RADIUS:
		Input.action_press("crouch")
		return
	if position.distance_to(viewport_size - Vector2(330, 105)) <= ACTION_RADIUS:
		Input.action_press("reload")
		return
	if position.x > viewport_size.x * 0.5:
		_aim_touch_id = touch_id
	_update_mobile_actions()


func _update_mobile_actions() -> void:
	var center := Vector2(142.0, size.y - 142.0)
	_move_vector = Vector2.ZERO
	for touch_position in _touches.values():
		if touch_position.x < size.x * 0.48:
			_move_vector = (touch_position - center).limit_length(MOVE_RADIUS) / MOVE_RADIUS
			break
	_set_action("move_left", _move_vector.x < -0.16)
	_set_action("move_right", _move_vector.x > 0.16)
	_set_action("move_forward", _move_vector.y < -0.16)
	_set_action("move_backward", _move_vector.y > 0.16)
	_set_action("attack", _has_touch_near(Vector2(size.x - 118.0, size.y - 136.0), 74.0))
	_set_action("jump", _has_touch_near(size - Vector2(250, 250), ACTION_RADIUS))
	_set_action("crouch", _has_touch_near(size - Vector2(90, 275), ACTION_RADIUS))
	_set_action("reload", _has_touch_near(size - Vector2(330, 105), ACTION_RADIUS))
	queue_redraw()


func _has_touch_near(center: Vector2, radius: float) -> bool:
	for touch_position in _touches.values():
		if touch_position.distance_to(center) <= radius:
			return true
	return false


func _set_action(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
