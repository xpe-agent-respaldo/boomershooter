class_name Player

extends CharacterBody3D

signal shoot(origin: Vector3, normal: Vector3, gun_end_position: Vector3)
signal weapon_changed(weapon_data: WeaponData)
signal player_ready
signal player_hurt(hit_position: Vector3)
signal health_changed
signal player_died
signal enemy_killed
signal kills_changed

@export var FPS_ARMS: Node3D
@export var MOUSE_SENSITIVITY: float = 0.33
@export var CONTROLLER_SENSITIVITY: float = 2.0
@export var CONTROLLER_VERTICAL_MULTIPLIER: float = 0.6
@export var SPRINT_FOV_MULTIPLIER: float = 1.15
@export var ADS_FOV_MULTIPLIER: float = 0.7
@export var ADS_SENSITIVITY_MULTIPLIER: float = 0.6
@export var ADS_ZOOM_SPEED: float = 12.0
@export var AIM_ASSIST_ANGLE: float = deg_to_rad(5.0)
@export var AIM_ASSIST_RANGE: float = 40.0
@export var AIM_ASSIST_STRENGTH: float = 0.5
@export var TILT_LOWER_LIMIT: float = deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT: float = deg_to_rad(90.0)
@export var ANIMATIONPLAYER: AnimationPlayer
@export var CAMERA_CONTROLLER: Camera3D
@export var ROLL_ANGLE: float = 0.65
@export var ROLL_SPEED: int = 300
@export var WEAPON_DATA: WeaponData = null

const MAX_HEALTH: int = 100

var health: int = MAX_HEALTH
var kills: int = 0

var is_aiming: bool = false
var is_sprinting: bool = false
var _base_fov: float
var _last_forward_press_ms: int = -1000
var _double_tap_sprint_until_ms: int = 0
var crouch_toggle_active := false

var last_firing_time: int = 0

var _mouse_input: bool = false
var _aim_assist := AimAssist.new()
var _aa_friccion := 1.0
var _camera_rotation: Vector3
var _player_rotation: Vector3
var _mouse_rotation: Vector3

var _current_rotation: float
var _rotation_input: float
var _tilt_input: float

# Get the gravity from the project settings to be synced with RigidBody nodes.
# var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var gravity: float = 12.0

var been_hurt: bool = false
var _hurting_bodies: Array[Node3D] = []
var hurt_timer: Timer = Timer.new()

@onready var aimcast: RayCast3D = %AimCast


func _ready() -> void:
	# Este Player es siempre el jugador local. Los demas jugadores son RemotePlayer
	# (network_game.gd): ya no hay peers ni autoridad de Godot de por medio.
	Global.player = self
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_base_fov = CAMERA_CONTROLLER.fov

	enemy_killed.connect(_on_enemy_killed)

	# Hurt Timer
	hurt_timer.wait_time = 1.0
	hurt_timer.autostart = true
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)
	hurt_timer.name = "HurtTimer"
	add_child(hurt_timer)

	player_ready.emit()

func _physics_process(delta: float) -> void:
	update_aim(delta)
	update_controller_look()
	_aa_friccion = _aim_assist.actualizar(delta, self, CAMERA_CONTROLLER)
	var empuje := _aim_assist.empuje(delta, CAMERA_CONTROLLER, Input.is_action_pressed("attack"), is_aiming)
	if empuje != Vector2.ZERO:
		_mouse_rotation.y += empuje.x
		_mouse_rotation.x = clampf(_mouse_rotation.x + empuje.y, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	update_camera(delta)
	CAMERA_CONTROLLER.rotation.z = _calc_roll(ROLL_ANGLE, ROLL_SPEED) * 2


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		crouch_toggle_active = not crouch_toggle_active
	if event.is_action_pressed("move_forward") and GameSettings and GameSettings.double_tap_sprint:
		var now := Time.get_ticks_msec()
		if now - _last_forward_press_ms <= 280:
			_double_tap_sprint_until_ms = now + 900
		_last_forward_press_ms = now

	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		var sensitivity: float = GameSettings.mouse_sensitivity if GameSettings else MOUSE_SENSITIVITY
		if is_aiming:
			sensitivity *= ADS_SENSITIVITY_MULTIPLIER
		# friccion del aim assist de PC: gira un poco mas lento cerca de un enemigo
		sensitivity *= _aa_friccion
		_rotation_input = -event.relative.x * sensitivity
		_tilt_input = -event.relative.y * sensitivity


# Track the aim action and zoom the FOV in for aiming or out for sprint speed
func update_aim(delta: float) -> void:
	is_aiming = Input.is_action_pressed("aim")

	var fov_multiplier: float = 1.0
	if is_aiming:
		fov_multiplier = WEAPON_DATA.ads_fov_multiplier if WEAPON_DATA else ADS_FOV_MULTIPLIER
	elif is_sprinting:
		fov_multiplier = SPRINT_FOV_MULTIPLIER

	CAMERA_CONTROLLER.fov = lerpf(CAMERA_CONTROLLER.fov, _base_fov * fov_multiplier, ADS_ZOOM_SPEED * delta)


# Feed right stick input into the same rotation accumulators the mouse uses
func update_controller_look() -> void:
	if Global.weapon_wheel_open:
		return

	var look_input: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input == Vector2.ZERO:
		return

	# Square each axis so slight off-axis drift barely registers but full tilt keeps full speed
	look_input.x = signf(look_input.x) * look_input.x * look_input.x
	look_input.y = signf(look_input.y) * look_input.y * look_input.y

	var base_controller_sensitivity: float = GameSettings.controller_sensitivity if GameSettings else CONTROLLER_SENSITIVITY
	var sensitivity: float = base_controller_sensitivity * _aim_assist_factor()
	if is_aiming:
		sensitivity *= ADS_SENSITIVITY_MULTIPLIER

	_rotation_input -= look_input.x * sensitivity
	_tilt_input -= look_input.y * sensitivity * CONTROLLER_VERTICAL_MULTIPLIER


# Returns a look sensitivity multiplier that eases toward AIM_ASSIST_STRENGTH
# as the camera points closer to a living enemy, giving controller sticky aim
func _aim_assist_factor() -> float:
	var camera_forward: Vector3 = -CAMERA_CONTROLLER.global_transform.basis.z
	var best_angle: float = AIM_ASSIST_ANGLE

	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.dead:
			continue

		var to_enemy: Vector3 = enemy.global_position + Vector3.UP * 0.5 - CAMERA_CONTROLLER.global_position
		if to_enemy.length() > AIM_ASSIST_RANGE:
			continue

		var angle: float = camera_forward.angle_to(to_enemy)
		if angle < best_angle:
			best_angle = angle

	return lerpf(AIM_ASSIST_STRENGTH, 1.0, best_angle / AIM_ASSIST_ANGLE)


func update_camera(delta: float) -> void:
	_current_rotation = _rotation_input
	_mouse_rotation.x += _tilt_input * delta
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input * delta

	_player_rotation = Vector3(0.0,_mouse_rotation.y,0.0)
	_camera_rotation = Vector3(_mouse_rotation.x,0.0,0.0)

	CAMERA_CONTROLLER.transform.basis = Basis.from_euler(_camera_rotation)
	global_transform.basis = Basis.from_euler(_player_rotation)

	CAMERA_CONTROLLER.rotation.z = 0.0

	_rotation_input = 0.0
	_tilt_input = 0.0


func update_input(speed: float, acceleration: float, deceleration: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = lerp(velocity.x, direction.x * speed, acceleration)
		velocity.z = lerp(velocity.z, direction.z * speed, acceleration)
	else:
		velocity.x = move_toward(velocity.x, 0, deceleration)
		velocity.z = move_toward(velocity.z, 0, deceleration)


# Shift keeps the classic sprint. A second quick press of W can sprint too,
# and automatic sprint only activates while the player is actually moving forward.
func wants_to_sprint() -> bool:
	if Input.is_action_pressed("sprint"):
		return true
	if not Input.is_action_pressed("move_forward"):
		return false
	if GameSettings and GameSettings.auto_sprint:
		return true
	return GameSettings and GameSettings.double_tap_sprint and Time.get_ticks_msec() < _double_tap_sprint_until_ms


func wants_to_crouch() -> bool:
	return crouch_toggle_active or Input.is_action_pressed("crouch")


func update_gravity(delta: float) -> void:
	velocity.y -= gravity * delta


## Altura maxima de escalon que se sube andando, sin saltar. La escalera de las
## casas usa peldanos de 0.45 m; el salto simple llega a 1.58 m.
const STEP_HEIGHT := 0.55


func update_velocity() -> void:
	var was_on_floor := is_on_floor()
	var start_velocity := velocity
	var start_position := global_position
	move_and_slide()
	# CharacterBody3D no sube escalones solo: se queda pegado al borde, con la normal
	# ligeramente inclinada por el redondeo de la capsula (no es 100% vertical).
	# Criterio: si iba por el suelo, queria avanzar y casi no avanzo, hay un obstaculo bajo.
	if not was_on_floor or start_velocity.y > 0.01:
		return
	var wanted := Vector3(start_velocity.x, 0.0, start_velocity.z)
	if wanted.length() < 0.5:
		return
	var moved := global_position - start_position
	moved.y = 0.0
	var expected := wanted.length() * get_physics_process_delta_time()
	# En una rampa el jugador avanza algo aunque tope con el borde de arriba, asi que
	# ademas del avance se mira si hay una pared vertical delante.
	if moved.dot(wanted.normalized()) < expected * 0.35 or _wall_ahead(wanted.normalized()):
		_try_step_up(wanted)


func _wall_ahead(dir: Vector3) -> bool:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.2 and n.dot(dir) < -0.6:
			return true
	return false


func _try_step_up(wanted: Vector3) -> void:
	var dir := wanted.normalized()
	var motion := wanted * get_physics_process_delta_time()
	var origin := global_transform
	var space := get_world_3d().direct_space_state
	# 1) altura del escalon: varios rayos verticales ADELANTE, desde justo fuera de la
	#    capsula hasta 0.75 m. Uno solo a distancia fija falla: en una escalera de peldanos
	#    de 0.9 m de fondo el escalon siguiente puede estar a 0.3 m o a 0.8 m segun donde
	#    se pare el jugador, y un rayo lejano pasa de largo por encima. Se toma el primer
	#    suelo mas alto que el actual. Se usa la normal del rayo (superficie real), no la
	#    de test_move, que es la del borde redondeado de la capsula.
	var hit := {}
	var rise := 0.0
	for dist in [0.35, 0.5, 0.65, 0.8]:
		var ahead: Vector3 = origin.origin + dir * dist
		var query := PhysicsRayQueryParameters3D.create(
			ahead + Vector3.UP * (STEP_HEIGHT + 0.05), ahead + Vector3.DOWN * 0.3)
		query.exclude = [get_rid()]
		var candidate := space.intersect_ray(query)
		if candidate.is_empty() or candidate.normal.y < 0.7:
			continue
		var candidate_rise: float = candidate.position.y - global_position.y
		if candidate_rise > 0.02 and candidate_rise <= STEP_HEIGHT:
			hit = candidate
			rise = candidate_rise
			break
	if hit.is_empty():
		return
	# 2) se eleva SOLO lo necesario (+1 cm de margen). Elevar siempre el maximo hacia que
	#    la capsula chocara con el peldano siguiente en una escalera.
	var lift := rise + 0.01
	if test_move(origin, Vector3.UP * lift):
		return
	var raised := origin.translated(Vector3.UP * lift)
	# 3) se puede avanzar estando arriba?
	if test_move(raised, motion):
		return
	var advanced := raised.translated(motion + dir * 0.12)
	global_position = Vector3(advanced.origin.x, hit.position.y, advanced.origin.z)
	velocity.y = 0.0



# Returns a value for how much the Camera Mount should tilt to the side.
# TODO Fix rotation side
func _calc_roll(rollangle: float, rollspeed: float) -> float:
	if rollangle == 0.0 or rollspeed == 0:
		return 0

	var side: float = velocity.dot(CAMERA_CONTROLLER.transform.basis.x)
	# print("Side: %s" % side)
	var roll_sign: float = 1.0 if side < 0.0 else -1.0
	side = absf(side)

	var value: float = rollangle
	if (side < rollspeed):
		side = side * value / rollspeed
	else:
		side = value

	return side * roll_sign


func set_weapon(weapon_data: WeaponData) -> void:
	# print("Weapon changed! %s" % str(weapon_data))
	WEAPON_DATA = weapon_data
	weapon_changed.emit()


func can_fire() -> bool:
	if WEAPON_DATA == null or FPS_ARMS == null or FPS_ARMS.is_reloading:
		return false

	var shoot_time_diff: int = Time.get_ticks_msec() - last_firing_time
	if shoot_time_diff < WEAPON_DATA.fire_rate:
		return false

	return true


# Restore health up to the maximum and notify the HUD
func heal(amount: int) -> void:
	health = min(MAX_HEALTH, health + amount)
	health_changed.emit()


func take_damage(damage: int, hit_position: Vector3) -> void:
	if !been_hurt:
		been_hurt = true
		health = max(0, health - damage)
		health_changed.emit()

		if !%OuchSound.playing:
			%OuchSound.play()

		if health <= 0:
			player_died.emit()
		else:
			player_hurt.emit(hit_position)


# --- Duelo (jugador contra jugador). La vida la lleva el servidor; aqui solo se refleja. -------------
var en_duelo_caido := false


## El servidor dice cuanta vida te queda tras un impacto de otro jugador.
func recibir_dano_duelo(_dano: int, vida_servidor: int, desde: Vector3) -> void:
	health = clampi(vida_servidor, 0, MAX_HEALTH)
	health_changed.emit()
	if has_node("%OuchSound") and not %OuchSound.playing:
		%OuchSound.play()
	if health > 0:
		player_hurt.emit(desde)


## Te eliminaron: caes unos segundos (sin pantalla de Game Over: en el duelo se reaparece).
func caer_en_duelo() -> void:
	en_duelo_caido = true
	health = 0
	health_changed.emit()
	velocity = Vector3.ZERO
	set_physics_process(false)
	visible = false


## El servidor te hace reaparecer con la vida llena, lejos de donde caiste.
func reaparecer_en_duelo(vida: int) -> void:
	en_duelo_caido = false
	health = clampi(vida, 1, MAX_HEALTH)
	health_changed.emit()
	been_hurt = false
	visible = true
	set_physics_process(true)
	var puntos := get_tree().get_nodes_in_group("spawn_point")
	if puntos.is_empty():
		var raiz := get_tree().current_scene
		var sp := raiz.get_node_or_null("SpawnPoints") if raiz != null else null
		if sp != null:
			puntos = sp.get_children()
	if not puntos.is_empty():
		var lejos: Node3D = puntos[0]
		var mejor := -1.0
		for punto in puntos:
			if not punto is Node3D:
				continue
			var d := 9999.0
			for otro in get_tree().get_nodes_in_group("remote_player"):
				if otro is Node3D:
					d = minf(d, (punto as Node3D).global_position.distance_to(otro.global_position))
			if d > mejor:
				mejor = d
				lejos = punto
		global_position = lejos.global_position + Vector3(0, 0.3, 0)
	velocity = Vector3.ZERO


## Devuelve el nodo enemigo que corresponde a un cuerpo detectado, ya sea el
## propio CharacterBody3D del enemigo o uno de sus huesos.
func _enemy_from_body(body: Node3D) -> Node3D:
	if body.is_in_group("enemy"):
		return body
	if body.owner != null and body.owner.is_in_group("enemy"):
		return body.owner
	return null


func _on_hurt_box_body_entered(body: Node3D) -> void:
	# body_entered se emite una sola vez por solape: si el enemigo se quedaba
	# encima, solo te pegaba una vez. Ahora se recuerda quien esta en contacto y
	# el daño se repite al ritmo del hurt_timer.
	var enemy: Node3D = _enemy_from_body(body)
	if enemy == null:
		return
	if not _hurting_bodies.has(enemy):
		_hurting_bodies.append(enemy)
	_apply_enemy_contact_damage()


func _on_hurt_box_body_exited(body: Node3D) -> void:
	var enemy: Node3D = _enemy_from_body(body)
	if enemy != null:
		_hurting_bodies.erase(enemy)


func _apply_enemy_contact_damage() -> void:
	if been_hurt:
		return
	# Limpiar enemigos que ya murieron o desaparecieron.
	_hurting_bodies = _hurting_bodies.filter(func(node: Node3D) -> bool:
		return is_instance_valid(node) and not node.dead)
	if _hurting_bodies.is_empty():
		return
	var nearest: Node3D = _hurting_bodies[0]
	take_damage(nearest.damage, nearest.global_position)


func _on_hurt_timer_timeout() -> void:
	if been_hurt:
		been_hurt = false
	# Si sigue habiendo enemigos encima, el contacto se cobra de nuevo.
	_apply_enemy_contact_damage()


func _on_enemy_killed() -> void:
	kills += 1
	kills_changed.emit()
