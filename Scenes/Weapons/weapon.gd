extends Node3D

@export var weapon_data: WeaponData
@export var bullet_scene: PackedScene
@export_range(0.4, 1.6, 0.01) var shot_pitch_scale: float = 1.0
@export_range(0.0, 0.25, 0.01) var shot_pitch_variation: float = 0.08
## Timbre propio del disparo ("pistola", "subfusil", "escopeta", "rifle"). Vacio = conserva el
## sonido de la escena (el francotirador usa su archivo). Antes pistola y subfusil compartian
## el mismo laser y sonaban igual.
@export var timbre_disparo: String = ""

var bullet_hole: Resource = preload("res://Scenes/raycast_test.tscn")
## Dano por impacto a un jugador entrenado (aguanta 100: cae en 4 tiros).
const ENTRENADO_SHOT_DAMAGE := 25

## Tope de impactos visibles: antes cada disparo dejaba un Decal vivo 3.5 s sin
## limite, y con el SMG o la escopeta se acumulaban decenas encima de la escena.
const MAX_BULLET_HOLES := 24
var _holes: Array[Decal] = []

## Voces de sonido de disparo. Un solo AudioStreamPlayer reinicia el disparo
## anterior en cada tiro y a cadencia alta parece que el arma no suena.
const SHOT_VOICES := 3
var _shot_voices: Array[AudioStreamPlayer] = []
var _shot_voice_index: int = 0

@onready var gun_end: Marker3D = %GunEnd
@onready var fps_arms: Node3D = get_tree().get_first_node_in_group("fps_arms")
@onready var player: Player = get_tree().get_first_node_in_group("player")

func _ready() -> void:
	# Weapon scenes can enter before the player registers its group.
	if player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player") as Player
	if player == null or weapon_data == null:
		push_error("Weapon could not initialize: player or weapon data is missing.")
		return
	if not player.is_node_ready():
		await player.ready
	if fps_arms == null:
		fps_arms = player.FPS_ARMS
	# El sonido se prepara AHORA y no en el primer disparo: sintetizarlo cuesta un bucle de miles
	# de muestras y, en un equipo flojo, el primer tiro salia tarde o mudo.
	_preparar_voces()
	weapon_data.used.connect(_on_weapon_used)
	weapon_data.empty.connect(_on_weapon_empty)
	weapon_data.needs_reload.connect(_on_weapon_needs_reload)
	weapon_data.reloaded.connect(_on_weapon_reloaded)
	# player.WEAPON_DATA = weapon_data


func _on_weapon_used() -> void:
	if player == null or fps_arms == null:
		return
	var shoot_time_diff: int = Time.get_ticks_msec() - player.last_firing_time
	var busy: bool = fps_arms.is_reloading or !(shoot_time_diff > weapon_data.fire_rate)
	if !busy:
		player.last_firing_time = Time.get_ticks_msec()
		fps_arms.fire()
		_play_shot_sound()

		var target: Object = player.aimcast.get_collider()
		# El dano se resuelve subiendo hasta el nodo Enemy: asi mata tanto si el rayo
		# toca un hueso fisico como la capsula del cuerpo (en perfil bajo no hay huesos).
		# Los bots (aliados o enemigos) tambien reciben impacto: dispararle a uno
		# lo convierte en hostil.
		var entrenado := _entrenado_from(target)
		if not entrenado.is_empty():
			OnlineManager.report_entrenado_hit(entrenado, ENTRENADO_SHOT_DAMAGE)

		var hit_bot: Bot = _bot_from(target)
		if hit_bot != null:
			hit_bot.take_hit(player.global_position)

		var victim: Enemy = _enemy_from(target)
		if victim != null and not victim.dead:
			var hit_point: Vector3 = player.aimcast.get_collision_point()
			var is_head: bool = (target is Node and (target as Node).name == "Head") \
				or hit_point.y > victim.global_position.y + victim.head_height
			if is_head:
				victim.headshot()
			else:
				victim.take_damage()

		# Spawn bullet projectiles in the weapon's spread cone
		var aim_direction: Vector3
		if player.aimcast.is_colliding():
			aim_direction = gun_end.global_position.direction_to(player.aimcast.get_collision_point())
		else:
			aim_direction = gun_end.global_transform.basis.z

		for pellet: int in weapon_data.pellet_count:
			_spawn_bullet(_spread_direction(aim_direction))

		# Create Bullet Hole
		if target:
			_bullet_hole(player.aimcast.get_collision_point(), player.aimcast.get_collision_normal())


func _preparar_voces() -> void:
	if not _shot_voices.is_empty():
		return
	for i in SHOT_VOICES:
		var v := AudioStreamPlayer.new()
		v.bus = &"SFX"
		v.stream = SfxArmas.stream(timbre_disparo) if timbre_disparo != "" else %ShotSound.stream
		if timbre_disparo != "":
			v.volume_db = 4.0
		add_child(v)
		_shot_voices.append(v)


## Reparte el disparo entre varias voces para que no se corte el anterior.
func _play_shot_sound() -> void:
	_preparar_voces()
	var voice: AudioStreamPlayer = _shot_voices[_shot_voice_index]
	_shot_voice_index = (_shot_voice_index + 1) % _shot_voices.size()
	if voice.stream == null:
		return
	voice.pitch_scale = randf_range(shot_pitch_scale - shot_pitch_variation, shot_pitch_scale + shot_pitch_variation)
	voice.play()
	%ShotSound.stop()


func _bot_from(hit: Object) -> Bot:
	var node := hit as Node
	while node != null:
		if node is Bot:
			return node as Bot
		node = node.get_parent()
	return null


func _enemy_from(hit: Object) -> Enemy:
	var node := hit as Node
	while node != null:
		if node is Enemy:
			return node as Enemy
		node = node.get_parent()
	return null


func _spawn_bullet(direction: Vector3) -> void:
	var bullet: Area3D = bullet_scene.instantiate()
	bullet.transform = gun_end.global_transform
	bullet.scale = Vector3(5, 5, 5)
	bullet.velocity = direction * bullet.muzzle_velocity
	bullet.exploded.connect(_on_bullet_exploded)
	_projectile_host().add_child(bullet)


# Deviate the aim direction by a random angle inside the weapon's spread cone
func _spread_direction(aim_direction: Vector3) -> Vector3:
	if weapon_data.spread_degrees <= 0.0:
		return aim_direction

	var spread: float = deg_to_rad(weapon_data.spread_degrees)
	var right: Vector3 = aim_direction.cross(Vector3.UP)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(aim_direction).normalized()

	return aim_direction.rotated(up, randf_range(-spread, spread)).rotated(right, randf_range(-spread, spread)).normalized()


func get_gun_end_position() -> Vector3:
	var camera: Camera3D = Global.player.CAMERA_CONTROLLER
	var depth: int = Global.player.arms_view.camera.to_local(gun_end.global_position).length()
	var screen_pos: Vector2 = Global.player.arms_view.camera.unproject_position(gun_end.global_position)
	return (camera.project_position(screen_pos, depth))


func _on_bullet_exploded(explosion_position: Vector3) -> void:
	var hole_decal: Decal = bullet_hole.instantiate()
	hole_decal.position = explosion_position
	get_tree().root.add_child(hole_decal)


func _on_weapon_empty() -> void:
	# Sin reserva: solo el gesto de cargador vacio.
	if fps_arms:
		fps_arms.shake()


func _on_weapon_needs_reload() -> void:
	# Recarga automatica al vaciar el cargador (mantiene la animacion y el sonido).
	if weapon_data != null and weapon_data.mag > 0 and weapon_data.ammo < weapon_data.max_ammo:
		weapon_data.reload()


func _on_weapon_reloaded() -> void:
	if has_node("ReloadSound"):
		%ReloadSound.play()
	if fps_arms:
		fps_arms.reload()


func _exit_tree() -> void:
	for hole in _holes:
		if is_instance_valid(hole):
			hole.queue_free()
	_holes.clear()


func _max_holes() -> int:
	return 8 if GameSettings.performance_profile == 0 else MAX_BULLET_HOLES


## Escena donde viven balas y agujeros: la actual si existe, si no la raiz.
func _projectile_host() -> Node:
	var current: Node = get_tree().current_scene
	return current if current != null else get_tree().root


func _prune_holes() -> void:
	var limit := _max_holes()
	while _holes.size() >= limit:
		var oldest: Decal = _holes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Devuelve el id del jugador entrenado al que le pegaste, o "" si no era uno.
## El cuerpo de colision vive en el avatar remoto (grupo "entrenado").
func _entrenado_from(body: Object) -> String:
	var nodo := body as Node
	while nodo != null:
		if nodo.is_in_group("entrenado"):
			return str(nodo.get_meta("entrenado_id", ""))
		nodo = nodo.get_parent()
	return ""


func _bullet_hole(hole_position: Vector3, normal: Vector3) -> void:
	_prune_holes()
	var instance: Decal = bullet_hole.instantiate()
	_holes.append(instance)
	# Colgado de la escena actual, no de root: si se cambia de mapa con el decal
	# vivo, al liberar la escena se va con ella y no queda huerfano en memoria.
	_projectile_host().add_child(instance)
	instance.global_position = hole_position
	if normal != Vector3.UP:
		instance.look_at(instance.global_transform.origin + normal, Vector3.UP)

	if normal != Vector3.UP and normal != Vector3.DOWN:
		instance.rotate_object_local(Vector3(1, 0, 0), 90)

	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(instance):
		return

	var face: Tween = instance.create_tween()
	face.tween_property(instance, "modulate:a", 0, 1.5)

	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(instance):
		instance.queue_free()
