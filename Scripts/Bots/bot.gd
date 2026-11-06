class_name Bot
extends RemotePlayer
## Bot con aspecto de jugador real. Tres conductas:
##  RECLUTABLE: camina tranquilo por el mapa y se deja hacer amigo al acercarse.
##  ALIADO:     sigue al jugador y dispara a los monstruos y a los bots hostiles.
##  HOSTIL:     si le disparas (o pertenece a un escuadron enemigo) te persigue y te ataca.
## No lleva ninguna marca que lo delate: se comporta y se llama como una persona.

enum Mode { RECRUITABLE, ALLY, HOSTILE }

const WALK_SPEED := 3.4
const RUN_SPEED := 6.4
const RECRUIT_RANGE := 3.6
const SIGHT_RANGE := 26.0
const FIRE_RANGE := 22.0
const FIRE_COOLDOWN := 0.62
const STRAFE_SPEED := 4.6
const DODGE_SPEED := 9.5
const DODGE_TIME := 0.42
const DODGE_COOLDOWN := 1.15
const SLIDE_TIME := 0.55
const KEEP_DISTANCE := 11.0   # rango al que el bot orbita a su objetivo
const GRAVITY := 22.0

var mode: int = Mode.RECRUITABLE
var health: int = 3
var squad_id: String = ""
var is_inseparable: bool = false
var ally_index: int = -1

var _target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _fire_timer: float = 0.0
var _look: BotLook
var _weapon_index := 0
var _dodge_timer := 0.0
var _dodge_dir := Vector3.ZERO
var _dodge_cd := 0.0
var _sliding := false
var _slide_timer := 0.0
var _strafe_sign := 1.0
var _strafe_timer := 0.0
var _chat_lines := 0
var _body: CharacterBody3D
var _name_tag: Label3D
var _alive := true


## Armas que alterna el bot. Cambiar de arma cambia cadencia y daño: se nota.
const WEAPONS := [
	{"name": "Rifle", "cooldown": 0.42, "damage": 1, "burst": 3},
	{"name": "Escopeta", "cooldown": 1.05, "damage": 2, "burst": 1},
	{"name": "Subfusil", "cooldown": 0.22, "damage": 1, "burst": 5},
]


func setup_bot(display: String, tint: Color, start_mode: int, squad: String = "") -> void:
	setup(display, tint)
	mode = start_mode
	squad_id = squad
	_wander_timer = randf_range(0.0, 1.5)
	_pick_wander_target()
	if mode == Mode.HOSTILE:
		health = 4


func _ready() -> void:
	add_to_group("bot")
	_body = CharacterBody3D.new()
	_body.collision_layer = 8          # capa de bots: la mira del jugador la ve
	_body.collision_mask = 1 | 4
	# Sin esto el bot "trepaba" paredes inclinadas y esquinas de mallas fusionadas hasta
	# 14 m de altura: suelo caminable solo hasta 38 grados y pegado al suelo al bajar.
	_body.floor_max_angle = deg_to_rad(38.0)
	_body.floor_snap_length = 0.35
	_body.floor_stop_on_slope = true
	_body.floor_constant_speed = true
	_body.wall_min_slide_angle = deg_to_rad(20.0)
	_body.slide_on_ceiling = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	_body.add_child(shape)
	add_child(_body)

	# Personaje Neko encima del cuerpo de bloques heredado (que se oculta).
	_look = BotLook.new()
	_look.name = "NekoLook"
	add_child(_look)
	_look.build(Color(1.0, 0.78, 0.25))
	var inherited := get_node_or_null("%Body")
	if inherited != null:
		inherited.visible = false

	_name_tag = get_node_or_null("%NameTag") as Label3D
	push_transform(global_position, rotation.y)


# ---------- daño y hostilidad ----------
func take_hit(from_position: Vector3) -> void:
	if not _alive:
		return
	health -= 1
	# Dispararle a un bot, aunque sea aliado, lo vuelve enemigo: es su reaccion.
	if health > 0:
		_dodge_from(from_position)
		if mode != Mode.HOSTILE:
			become_hostile()
		_play_tag_flash(Color(1, 0.25, 0.2))
		return
	_die(from_position)


## Esquiva al recibir un disparo: se lanza perpendicular a la línea de tiro y
## a veces encadena un deslizamiento. Es lo que hace que cueste darle.
func _dodge_from(shooter_pos: Vector3) -> void:
	if _dodge_cd > 0.0:
		return
	_dodge_cd = DODGE_COOLDOWN + randf_range(0.0, 0.5)
	var away := (global_position - shooter_pos)
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	var side := Vector3(-away.z, 0, away.x) * (-1.0 if randf() < 0.5 else 1.0)
	_dodge_dir = (side * 1.6 + away * 0.6).normalized()
	_dodge_timer = DODGE_TIME
	if randf() < 0.45:
		_sliding = true
		_slide_timer = SLIDE_TIME


func say(text: String) -> void:
	# Los bots hablan en el chat del servidor, como cualquier jugador.
	if GameChat != null and text != "":
		GameChat.show_system_message(text)
	_chat_lines += 1


func become_hostile() -> void:
	var was_ally := mode == Mode.ALLY
	mode = Mode.HOSTILE
	_apply_mode_tint()
	if was_ally:
		say("%s: ¿Me disparas? Pues se acabó la amistad." % display_name)
	else:
		say("%s: Te tengo en el punto de mira." % display_name)


func become_ally(index: int) -> void:
	mode = Mode.ALLY
	ally_index = index
	_apply_mode_tint()
	_play_tag_flash(Color(0.45, 0.9, 1.0))
	say("%s: Voy contigo. Cambio de arma y te cubro." % display_name)


func is_recruitable() -> bool:
	return _alive and mode == Mode.RECRUITABLE


func distance_to_point(p: Vector3) -> float:
	return global_position.distance_to(p)


func _die(from_position: Vector3) -> void:
	_alive = false
	# El servidor no guarda nada de esto: es un bot local, solo cae y desaparece.
	spawn_debris()
	var dir := (global_position - from_position).normalized()
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", dir.x * 1.4, 0.35)
	tw.parallel().tween_property(self, "position:y", position.y - 1.2, 0.45)
	tw.tween_interval(0.6)
	tw.tween_callback(queue_free)


func spawn_debris() -> void:
	var sparks := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.color = Color(1.0, 0.55, 0.2)
	sparks.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	sparks.draw_pass_1 = mesh
	sparks.amount = 18
	sparks.one_shot = true
	sparks.emitting = true
	sparks.position.y = 1.1
	add_child(sparks)
	get_tree().create_timer(1.2).timeout.connect(sparks.queue_free)


func _apply_mode_tint() -> void:
	var tint := Color(1.0, 0.78, 0.25)
	match mode:
		Mode.ALLY: tint = Color(0.35, 0.85, 1.0)
		Mode.HOSTILE: tint = Color(1.0, 0.22, 0.16)
	if _look != null:
		_look.set_tint(tint)
	match mode:
		Mode.ALLY:
			setup(display_name, Color(0.35, 0.85, 1.0))
		Mode.HOSTILE:
			setup(display_name, Color(1.0, 0.22, 0.16))
		_:
			setup(display_name, Color(1.0, 0.78, 0.25))


func _play_tag_flash(color: Color) -> void:
	if not is_instance_valid(_name_tag):
		return
	var tw := create_tween()
	_name_tag.modulate = color
	tw.tween_property(_name_tag, "modulate", color.lightened(0.5), 0.18)
	tw.tween_property(_name_tag, "modulate", color, 0.18)


# ---------- movimiento ----------
func _pick_wander_target() -> void:
	var angle := randf() * TAU
	var radius := randf_range(6.0, 26.0)
	_target = global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)


const KILL_Y := -6.0              # por debajo de esto el bot esta cayendo al vacio
const MAX_DIST_JUGADOR := 170.0   # mas lejos que esto no esta "en el mapa"
var _ultimo_suelo: Vector3 = Vector3.ZERO
var _t_suelo: float = 0.0
var _rescates: int = 0


func _process(delta: float) -> void:
	if not _alive:
		return
	_vigilar_suelo(delta)
	_step(delta)
	super(delta)


## Un bot nunca debe seguir simulandose fuera del mapa: si cae al vacio o se aleja de
## la partida, vuelve al ultimo punto donde piso suelo. Si ni asi se sostiene, se retira.
func _vigilar_suelo(delta: float) -> void:
	if _body == null:
		return
	_t_suelo += delta
	if _body.is_on_floor():
		# Trepar: si en un instante sube mas de lo que permite una rampa real, se devuelve.
		if _ultimo_suelo != Vector3.ZERO and _body.global_position.y - _ultimo_suelo.y > 3.2:
			_body.global_position = _ultimo_suelo + Vector3(0, 0.3, 0)
			_body.velocity = Vector3.ZERO
			push_transform(_body.global_position, rotation.y)
			return
		if _t_suelo > 0.5:
			_t_suelo = 0.0
			_ultimo_suelo = _body.global_position
		return
	var p: Vector3 = _body.global_position
	var jug: Player = Global.player
	var lejos: bool = jug != null and Vector2(p.x - jug.global_position.x, p.z - jug.global_position.z).length() > MAX_DIST_JUGADOR
	if p.y > KILL_Y and not lejos:
		return
	_rescates += 1
	if _rescates > 3 or _ultimo_suelo == Vector3.ZERO:
		# no se sostiene en este mapa: se retira para no gastar CPU simulando el vacio
		set_process(false)
		if _body:
			_body.set_physics_process(false)
		queue_free()
		return
	_body.global_position = _ultimo_suelo + Vector3(0, 0.3, 0)
	_body.velocity = Vector3.ZERO
	push_transform(_body.global_position, rotation.y)


func _step(delta: float) -> void:
	var player: Player = Global.player
	if player == null:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
	if not _sliding:
		_slide_timer -= delta
	var player_pos := player.global_position
	var dist := global_position.distance_to(player_pos)

	match mode:
		Mode.RECRUITABLE:
			_wander_timer -= delta
			if _wander_timer <= 0.0 or global_position.distance_to(_target) < 1.5:
				_wander_timer = randf_range(2.5, 5.0)
				_pick_wander_target()
			_move_towards(_target, WALK_SPEED, delta)
		Mode.ALLY:
			var target := _nearest_threat()
			if target != null:
				_fight(target, delta)
			elif dist > 4.5:
				_move_towards(player_pos, RUN_SPEED if dist > 10.0 else WALK_SPEED, delta)
			else:
				_idle_sway(delta)
		Mode.HOSTILE:
			if dist < SIGHT_RANGE:
				_fight(player, delta, true)
			else:
				_wander_timer -= delta
				if _wander_timer <= 0.0:
					_wander_timer = randf_range(2.0, 4.0)
					_pick_wander_target()
				_move_towards(_target, WALK_SPEED, delta)

	_animate(delta)


## Movimiento de combate: orbita el objetivo, mantiene distancia y esquiva.
## Esto es lo que hace que el bot no se quede plantado comiendo balas.
func _fight(target: Node3D, delta: float, chase: bool = false) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target.normalized() if dist > 0.01 else Vector3.FORWARD
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.8, 2.0)
		_strafe_sign = -1.0 if randf() < 0.5 else 1.0
		_maybe_switch_weapon()
	var side := Vector3(-dir.z, 0, dir.x) * _strafe_sign

	if _dodge_timer > 0.0:
		# Esquiva: se lanza de lado a toda velocidad (o deslizándose si va rapido).
		_apply_move(_dodge_dir * DODGE_SPEED, delta)
		_sliding = _dodge_timer > DODGE_TIME * 0.45
		return

	var move := Vector3.ZERO
	if dist > KEEP_DISTANCE + 3.0:
		move += dir * 5.4                       # se acerca
	elif dist < KEEP_DISTANCE - 4.0:
		move -= dir * 4.2                       # retrocede si se le echan encima
	move += side * STRAFE_SPEED                 # siempre orbitando
	if _sliding:
		_slide_timer = maxf(0.0, _slide_timer - delta)
		if _slide_timer <= 0.0:
			_sliding = false
	# Se mira al objetivo aunque se mueva de lado: dispara igual.
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 12.0))
	_apply_move(move, delta)

	if _look != null:
		_look.animate(delta, move.length(), _dodge_timer > 0.0, _sliding)

	var aim := target.global_position + Vector3(0, 1.1, 0)
	if dist <= FIRE_RANGE:
		_try_fire(aim, target)


func _apply_move(velocity: Vector3, delta: float) -> void:
	if _body == null:
		return
	_body.velocity.x = velocity.x
	_body.velocity.z = velocity.z
	if _body.is_on_floor():
		_body.velocity.y = -0.5
	else:
		_body.velocity.y -= GRAVITY * delta
	_body.move_and_slide()
	push_transform(_body.global_position, rotation.y)


func _idle_sway(_delta: float) -> void:
	if _body != null:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
	push_transform(global_position, rotation.y)


func _nearest_threat() -> Node3D:
	var best: Node3D = null
	var best_d := FIRE_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and not (e.get("dead") == true):
			var d: float = global_position.distance_to((e as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = e as Node3D
	for b in get_tree().get_nodes_in_group("hostile_bot"):
		if b is Node3D and b != self and is_instance_valid(b):
			var d2: float = global_position.distance_to((b as Node3D).global_position)
			if d2 < best_d:
				best_d = d2
				best = b as Node3D
	return best


func _maybe_switch_weapon() -> void:
	if randf() < 0.45:
		_weapon_index = (_weapon_index + 1) % WEAPONS.size()


func _animate(delta: float) -> void:
	if _look == null:
		return
	var spd := 0.0
	if _body != null:
		spd = Vector2(_body.velocity.x, _body.velocity.z).length()
	_look.animate(delta, spd, _dodge_timer > 0.0, _sliding)


## True si hay linea de vision limpia hacia el punto: un rayo de la boca del bot al objetivo contra el
## mundo (capa 1). Antes el dano al jugador se aplicaba solo por distancia, asi que los bots quitaban
## vida a traves de paredes sin que se les viera disparar.
func ve_al_objetivo(punto: Vector3) -> bool:
	var origen := global_position + Vector3(0, 1.35, 0)
	var mundo := get_world_3d()
	if mundo == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(origen, punto, 1)
	if _body != null:
		q.exclude = [_body.get_rid()]
	var golpe := mundo.direct_space_state.intersect_ray(q)
	if golpe.is_empty():
		return true
	# Algo del mundo corta el rayo: solo cuenta si queda a menos de 0.6 m del objetivo (suelo/borde).
	return (golpe["position"] as Vector3).distance_to(punto) < 0.6


## Dispara con el arma actual. La ráfaga y la cadencia cambian por arma.
func _try_fire(aim: Vector3, target: Node3D) -> void:
	if _fire_timer > 0.0:
		return
	# Sin vision no se dispara ni se hace dano (antes atravesaba paredes).
	if not ve_al_objetivo(aim):
		return
	var w: Dictionary = WEAPONS[_weapon_index]
	_fire_timer = float(w["cooldown"]) + randf_range(0.0, 0.12)
	var rounds: int = int(w["burst"])
	_sonido_disparo(str(w["name"]))
	for i in rounds:
		_fire_at(aim + Vector3(randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), 0))
	# La escopeta reparte, el subfusil pica: el daño sale del arma elegida.
	var dmg: int = int(w["damage"])
	if target is Enemy:
		var en := target as Enemy
		if not en.dead:
			for _k in dmg:
				en.take_damage()
	elif target is Player:
		(target as Player).take_damage(4 * dmg, global_position)
	elif target is Bot:
		(target as Bot).health -= dmg


func _move_towards(point: Vector3, speed: float, delta: float) -> void:
	if _body == null:
		return
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() > 0.15:
		var dir := flat.normalized()
		_body.velocity.x = dir.x * speed
		_body.velocity.z = dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 9.0))
	else:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
	# La gravedad va en el cuerpo fisico para que no floten ni atraviesen el mapa.
	if _body.is_on_floor():
		_body.velocity.y = -0.5
	else:
		_body.velocity.y -= GRAVITY * delta
	_body.move_and_slide()
	# El visual sigue al cuerpo fisico (el que colisiona y recibe balas).
	push_transform(_body.global_position, rotation.y)


func _shoot_nearest_threat(player_pos: Vector3, _delta: float) -> void:
	var best: Node3D = null
	var best_d := FIRE_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and not (e.get("dead") == true):
			var d: float = global_position.distance_to((e as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = e as Node3D
	for b in get_tree().get_nodes_in_group("hostile_bot"):
		if b is Node3D and b != self:
			var d2: float = global_position.distance_to((b as Node3D).global_position)
			if d2 < best_d:
				best_d = d2
				best = b as Node3D
	if best == null:
		return
	rotation.y = atan2(-(best.global_position.x - global_position.x), -(best.global_position.z - global_position.z))
	if _fire_timer > 0.0 or not ve_al_objetivo(best.global_position + Vector3(0, 1.0, 0)):
		return
	_fire_timer = FIRE_COOLDOWN + randf_range(0.0, 0.25)
	_fire_at(best.global_position + Vector3(0, 1.0, 0))
	if best is Enemy:
		var en := best as Enemy
		if not en.dead:
			en.take_damage()


func _try_shoot_player(player: Player, dist: float, _delta: float) -> void:
	if _fire_timer > 0.0 or dist > FIRE_RANGE:
		return
	var pecho := player.global_position + Vector3(0, 1.2, 0)
	if not ve_al_objetivo(pecho):
		return
	_fire_timer = FIRE_COOLDOWN + randf_range(0.0, 0.3)
	_sonido_disparo("Rifle")
	_fire_at(pecho)
	player.take_damage(8, global_position)


## Sonido del disparo con tope global (maximo ~8 por segundo en toda la escena) para que
## una sala llena de bots no sea un muro de ruido ni gaste CPU en un portatil modesto.
static var _sonidos_ventana := 0
static var _sonidos_t0 := 0

func _sonido_disparo(arma: String) -> void:
	var ahora := Time.get_ticks_msec()
	if ahora - _sonidos_t0 > 1000:
		_sonidos_t0 = ahora
		_sonidos_ventana = 0
	if _sonidos_ventana >= 8:
		return
	_sonidos_ventana += 1
	var tipo := "rifle"
	match arma:
		"Escopeta": tipo = "escopeta"
		"Subfusil": tipo = "subfusil"
		"Rifle": tipo = "rifle"
	var pos := global_position + Vector3(0, 1.3, 0)
	# los lejanos suenan mas bajos: el oido del jugador distingue quien esta cerca
	var d := 0.0
	if Global.player != null and is_instance_valid(Global.player):
		d = Global.player.global_position.distance_to(pos)
	if d > 55.0:
		return
	SfxArmas.sonar_en(self, tipo, pos, -4.0 - d * 0.12, 55.0)


## Traza visual del disparo del bot: sale de su arma y termina en el objetivo.
func _fire_at(point: Vector3) -> void:
	var muzzle := global_position + Vector3(0, 1.35, 0) - global_transform.basis.z * 0.5
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.35)
	beam.material_override = mat
	get_tree().current_scene.add_child(beam)
	var mid := (muzzle + point) * 0.5
	beam.global_position = mid
	beam.look_at(point, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	beam.scale = Vector3(1, muzzle.distance_to(point), 1)
	get_tree().create_timer(0.05).timeout.connect(beam.queue_free)
