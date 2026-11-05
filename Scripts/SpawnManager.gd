class_name SpawnManager
extends Node

signal wave_countdown(seconds_left: int)
signal wave_started(wave_number: int, enemy_count: int, has_elite: bool)
signal wave_completed(wave_number: int)

const PICKUP_POOL_SIZE := 4
const WAVE_BREAK_SECONDS := 4

@export var difficulty: Curve
@export var enemy_scene: PackedScene
## Variante ligera y rapida: entra mezclada desde la oleada 2.
@export var enemy_scene_alt: PackedScene
@export var elite_scene: PackedScene
@export var ammo_scene: PackedScene
@export var health_scene: PackedScene

var current_wave := 0
var is_spawning := false
var wave_active := false
var ammo_pool: Array[Pickup] = []
var health_pool: Array[Pickup] = []


func _active_enemy_limit() -> int:
	# Limits concurrent work; every enemy in the selected wave still arrives.
	match GameSettings.performance_profile:
		0: return 8
		1: return 14
		_: return 20

@onready var spawn_points: Array[Marker3D] = _get_spawn_points()
@onready var enemies_node: Node = %Enemies


func _ready() -> void:
	add_to_group("wave_director")
	ammo_pool = _create_pool(ammo_scene)
	health_pool = _create_pool(health_scene)
	call_deferred("_begin_next_wave")


func _process(_delta: float) -> void:
	if wave_active and not is_spawning and enemies_node.get_child_count() == 0:
		wave_active = false
		wave_completed.emit(current_wave)
		_begin_next_wave()


func _begin_next_wave() -> void:
	if is_spawning:
		return
	is_spawning = true
	for seconds_left in range(WAVE_BREAK_SECONDS, 0, -1):
		wave_countdown.emit(seconds_left)
		# si el mapa se cierra durante la cuenta atras ya no hay arbol: se corta sin error
		if not is_inside_tree():
			is_spawning = false
			return
		await get_tree().create_timer(1.0, false).timeout
		if not is_inside_tree():
			is_spawning = false
			return
	current_wave += 1
	var enemies_to_spawn := _enemy_count_for_wave(current_wave)
	var has_elite := current_wave % 3 == 0 and elite_scene != null
	wave_started.emit(current_wave, enemies_to_spawn, has_elite)
	Achievements.marca("oleada", current_wave)
	if Engine.has_singleton("CloudSync") == false and get_node_or_null("/root/CloudSync") != null:
		CloudSync.reportar_partida(str(get_tree().current_scene.name), current_wave, 1)
	var available_spawns := spawn_points.duplicate()
	for index in enemies_to_spawn:
		while enemies_node.get_child_count() >= _active_enemy_limit():
			await get_tree().create_timer(0.25, false).timeout
		if available_spawns.is_empty():
			available_spawns = spawn_points.duplicate()
			available_spawns.shuffle()
		var spawn_point: Marker3D = available_spawns.pop_front()
		var scene: PackedScene = _pick_enemy_scene(index, enemies_to_spawn, has_elite)
		_spawn_enemy(scene, spawn_point.global_position)
		await get_tree().create_timer(maxf(0.18, 0.52 - current_wave * 0.018)).timeout
	is_spawning = false
	wave_active = true


## Monstruos nuevos. Se cargan por ruta para que entren en todos los mapas sin
## tener que asignarlos a mano en cada escena de arena.
const NUEVOS := [
	"res://Scenes/Enemies/Nuevos/AshCrawler.tscn",
	"res://Scenes/Enemies/Nuevos/ScrapBrute.tscn",
	"res://Scenes/Enemies/Nuevos/AcidShriek.tscn",
]


## Reparte tipos de enemigo: el ultimo de la oleada puede ser elite, desde la
## oleada 2 entra una variante ligera y desde la 3 se cuelan los nuevos.
func _pick_enemy_scene(index: int, total: int, has_elite: bool) -> PackedScene:
	if has_elite and index == total - 1:
		return elite_scene
	if current_wave >= 3 and index % 4 == 1:
		var ruta: String = NUEVOS[(current_wave + index) % NUEVOS.size()]
		if ResourceLoader.exists(ruta):
			return load(ruta) as PackedScene
	if enemy_scene_alt != null and current_wave >= 2 and index % 3 == 2:
		return enemy_scene_alt
	return enemy_scene


func _enemy_count_for_wave(wave_number: int) -> int:
	# Caps the initial launch mode at a readable amount while still escalating.
	return mini(42, 4 + wave_number * 2 + wave_number / 3)


func _spawn_enemy(scene: PackedScene, at_position: Vector3) -> void:
	if scene == null:
		return
	var enemy: Enemy = scene.instantiate()
	enemy.spawn_ammo.connect(_on_ammo_spawned)
	enemy.spawn_health.connect(_on_health_spawned)
	enemy.add_to_group("enemy")
	enemies_node.add_child(enemy)
	# Debe entrar al arbol antes de fijar la posicion global, si no Godot
	# devuelve Transform3D() y todos los enemigos aparecen en el origen.
	enemy.global_position = at_position


func _get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			points.append(child)
	return points


func _create_pool(scene: PackedScene) -> Array[Pickup]:
	var pool: Array[Pickup] = []
	if scene == null:
		return pool
	for _index in PICKUP_POOL_SIZE:
		pool.append(_add_pooled_pickup(scene))
	return pool


func _add_pooled_pickup(scene: PackedScene) -> Pickup:
	var pickup: Pickup = scene.instantiate()
	pickup.visible = false
	pickup.monitoring = false
	add_child(pickup)
	return pickup


func _take_from_pool(pool: Array[Pickup], scene: PackedScene) -> Pickup:
	for pickup in pool:
		if not pickup.visible:
			return pickup
	var extra := _add_pooled_pickup(scene)
	pool.append(extra)
	return extra


func _drop_pickup(pool: Array[Pickup], scene: PackedScene, at_position: Vector3) -> void:
	if scene == null:
		return
	var pickup := _take_from_pool(pool, scene)
	pickup.activate(at_position + Vector3.UP * 0.5)


func _on_ammo_spawned(ammo_position: Vector3) -> void:
	_drop_pickup(ammo_pool, ammo_scene, ammo_position)


func _on_health_spawned(health_position: Vector3) -> void:
	_drop_pickup(health_pool, health_scene, health_position)
