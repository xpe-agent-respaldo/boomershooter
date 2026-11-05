class_name Enemy
extends CharacterBody3D

signal attack_player
signal chase_player
signal spawn_ammo(ammo_position: Vector3)
signal spawn_health(health_position: Vector3)

@export var health: int = 2
@export var damage: int = 10
@export var speed: int = 150
@export var skeleton: Skeleton3D
@export var animation_player: AnimationPlayer
@export var proximity_sound_range: float = 13.0
@export var proximity_sound_cooldown: float = 8.0
## Altura (sobre los pies) a partir de la cual un impacto cuenta como headshot.
@export var head_height: float = 1.55

const PROXIMITY_SOUND_PATH := "res://Assets/Sounds/SFX/Enemies/mounstro random.ogg"
## Cada monstruo puede llevar su propio sonido y su propio color, para que los
## nuevos se distingan del original sin duplicar la escena entera.
@export var proximity_sound_path: String = PROXIMITY_SOUND_PATH
@export var tint: Color = Color(1, 1, 1)
@export var spawn_sound_path: String = "res://Assets/Sounds/SFX/Enemies/aparicion.wav"

var dead: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _proximity_sound_timer := 0.0
var _proximity_audio: AudioStreamPlayer3D

@onready var player: Player = Global.player
@onready var state_machine: StateMachine = $EnemyStateMachine

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Antes estaba en true como parche por "bones que no animaban". Lo que hacia
	# era congelar el esqueleto (la animacion cambiaba pero los huesos no se movian)
	# y meter ~23 cuerpos fisicos por enemigo. Con false la animacion corre y se
	# ahorra toda esa simulacion.
	skeleton.animate_physical_bones = false
	# Los 23 huesos fisicos por monstruo costaban fisica y memoria. Solo se mantienen
	# activos en perfil alto (para el ragdoll); el disparo ya golpea la capsula del cuerpo.
	# Antes solo se apagaba su colision, pero los 23 nodos seguian vivos (575 con 25
	# bichos). Ahora se ELIMINAN: menos nodos, menos memoria y menos trabajo del motor.
	if GameSettings.performance_profile != 2:
		for bone in skeleton.get_children():
			if bone is PhysicalBone3D:
				bone.queue_free()
	_proximity_audio = AudioStreamPlayer3D.new()
	# Audio files added while Godot is open may not have an import file yet.
	# Loading at runtime keeps the enemy script valid during that first import.
	var ruta: String = proximity_sound_path if not proximity_sound_path.is_empty() else PROXIMITY_SOUND_PATH
	if ResourceLoader.exists(ruta):
		_proximity_audio.stream = load(ruta) as AudioStream
	_proximity_audio.bus = &"SFX"
	_proximity_audio.max_distance = 28.0
	_proximity_audio.unit_size = 5.0
	add_child(_proximity_audio)

	# Tinte propio del monstruo: lo colorea sin tocar el modelo original.
	if tint != Color(1, 1, 1):
		_tint_recursive(self)

	# Golpe de aparicion para que se note que entra una amenaza nueva.
	if ResourceLoader.exists(spawn_sound_path):
		var aparicion := AudioStreamPlayer3D.new()
		aparicion.stream = load(spawn_sound_path) as AudioStream
		aparicion.bus = &"SFX"
		aparicion.max_distance = 30.0
		add_child(aparicion)
		aparicion.play()


func _tint_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.45
		mi.material_override = mat
	for c in node.get_children():
		_tint_recursive(c)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if player == null:
		player = Global.player
	if dead or player == null:
		return
	_proximity_sound_timer = maxf(0.0, _proximity_sound_timer - delta)
	if global_position.distance_to(player.global_position) <= proximity_sound_range and _proximity_sound_timer <= 0.0:
		_proximity_audio.pitch_scale = randf_range(0.9, 1.08)
		_proximity_audio.play()
		_proximity_sound_timer = proximity_sound_cooldown + randf_range(0.0, 3.0)


## Movimiento en el plano del suelo con gravedad acumulada: el monstruo camina,
## no vuela hacia el jugador aunque este en una torre. Se corrige tambien la
## inclinacion del cuerpo (solo gira en Y).
func walk_towards(target: Vector3, delta: float) -> void:
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dir := flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var speed_units: float = speed / 60.0
	velocity.x = dir.x * speed_units
	velocity.z = dir.z * speed_units
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 10.0))
	move_and_slide()


func headshot() -> void:
	# Un tiro en la cabeza tambien es una baja: antes se saltaba el contador de
	# kills porque ponia la vida a 0 y llamaba directo a handle_damage().
	if health > 0 and not dead:
		Achievements.suma("kills")
		Achievements.suma("headshots")
	health = 0
	handle_damage()


func take_damage() -> void:
	health -= 1
	if health <= 0 and not dead:
		# Logro de bajas: solo cuenta cuando el monstruo muere de verdad.
		Achievements.suma("kills")
	handle_damage()


func handle_damage() -> void:
	if health <= 0 and !dead:
		dead = true
		# Los de elite (oleadas de jefe) llevan la marca puesta por el SpawnManager.
		if has_meta("elite"):
			Achievements.suma("elites")
		# Sin esto el cadaver seguia corriendo y atacando durante el segundo
		# que tarda en desaparecer.
		if state_machine != null:
			state_machine.set_physics_process(false)
		set_physics_process(false)
		var roll: int = randi_range(1, 100)
		if roll <= 20:
			spawn_ammo.emit(position)
		elif roll <= 35:
			spawn_health.emit(position)

		# El ragdoll solo se activa al morir (1 s). Se detiene la animacion para
		# que la fisica no pelee con los huesos animados.
		# En equipos de 4 GB el ragdoll cuesta 23 cuerpos fisicos por cada muerte
		# y varios cadaveres a la vez hunden los FPS: se reserva al perfil alto.
		var ragdoll: bool = GameSettings.performance_profile == 2
		if animation_player != null:
			animation_player.stop()
		if ragdoll:
			skeleton.physical_bones_start_simulation()

		# Stop enemy collision
		for bone: Node in skeleton.get_children():
			if bone is PhysicalBone3D and not bone.is_queued_for_deletion():
				(bone as PhysicalBone3D).set_collision_layer_value(2, false)

		player.enemy_killed.emit()
		await get_tree().create_timer(1.0).timeout
		# Sin frenar la simulacion, los huesos fisicos siguen vivos un frame mas
		# y algunos quedaban colgados en el mundo.
		if ragdoll and is_instance_valid(skeleton):
			skeleton.physical_bones_stop_simulation()
		queue_free()


func _on_attack_range_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		attack_player.emit()


func _on_attack_range_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		chase_player.emit()
