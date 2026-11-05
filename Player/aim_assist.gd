class_name AimAssist
extends RefCounted
## Asistencia de punteria para raton y teclado (PC).
##
## Dos efectos, los dos suaves para que se sienta punteria buena y no un aimbot:
##  - FRICCION: cuanto mas cerca de un enemigo pasa la mira, mas lento gira el raton,
##    asi cuesta menos quedarse encima del objetivo.
##  - ATRACCION: al disparar o apuntar (ADS) la mira se desliza un poco hacia el torso.
##
## Coste: el objetivo se recalcula cada INTERVALO segundos, no cada frame, y solo mira
## a los enemigos y jugadores cercanos. En equipos flojos cuesta practicamente nada.

const INTERVALO := 0.05
const CONO := deg_to_rad(18.0)          # a partir de este angulo ya no ayuda
const ALCANCE := 80.0
const FRICCION_MIN := 0.22             # sensibilidad minima justo encima del objetivo
const ATRACCION := 9.0                 # rad/s de empuje maximo (se multiplica por la fuerza)
const ALTURA_TORSO := 1.35

## 0 = apagada, 1 = suave, 2 = media, 3 = fuerte.
const FUERZAS := [0.0, 1.2, 2.2, 3.4]

var _objetivo: Node3D = null
var _angulo := 99.0
var _reloj := 0.0
var _pos_objetivo := Vector3.ZERO


func nivel() -> int:
	return clampi(GameSettings.aim_assist_level if GameSettings else 1, 0, 3)


func fuerza() -> float:
	return FUERZAS[nivel()]


## Se llama cada frame de fisica. Devuelve el multiplicador de sensibilidad (friccion).
func actualizar(delta: float, jugador: Node3D, camara: Camera3D) -> float:
	if nivel() == 0 or camara == null:
		_objetivo = null
		return 1.0
	_reloj -= delta
	if _reloj <= 0.0:
		_reloj = INTERVALO
		_buscar(jugador, camara)
	if _objetivo == null or not is_instance_valid(_objetivo):
		_objetivo = null
		return 1.0
	# la friccion se atenua con la fuerza elegida
	var cerca := 1.0 - clampf(_angulo / CONO, 0.0, 1.0)
	var min_sens := lerpf(1.0, FRICCION_MIN, clampf(fuerza(), 0.0, 1.0))
	return lerpf(1.0, min_sens, cerca)


## Empuje en radianes (yaw, pitch) que se suma al giro del raton este frame.
func empuje(delta: float, camara: Camera3D, disparando: bool, apuntando: bool) -> Vector2:
	if _objetivo == null or not is_instance_valid(_objetivo) or camara == null:
		return Vector2.ZERO
	# Sin disparar ni apuntar el tiron es un cuarto de fuerte (la mira se "pega" sola);
	# al disparar o apuntar con ADS es completo.
	var factor_accion := 1.0 if (disparando or apuntando) else 0.25
	var desde := camara.global_position
	var hacia := _punto_objetivo() - desde
	if hacia.length() < 0.5:
		return Vector2.ZERO
	var local := camara.global_transform.basis.inverse() * hacia.normalized()
	# local.x > 0 = el objetivo esta a la derecha; local.y > 0 = esta arriba
	var yaw := -atan2(local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	var peso := (1.0 - clampf(_angulo / CONO, 0.0, 1.0)) * fuerza() * ATRACCION * factor_accion * delta
	# no se cruza la mira de golpe: tope por frame
	return Vector2(clampf(yaw * peso, -0.09, 0.09), clampf(pitch * peso, -0.09, 0.09))


func _punto_objetivo() -> Vector3:
	if _objetivo is Enemy:
		return _objetivo.global_position + Vector3.UP * ALTURA_TORSO
	return _objetivo.global_position + Vector3.UP * ALTURA_TORSO


func _buscar(jugador: Node3D, camara: Camera3D) -> void:
	var adelante := -camara.global_transform.basis.z
	var origen := camara.global_position
	var mejor: Node3D = null
	var mejor_ang := CONO
	var arbol := camara.get_tree()
	for grupo in ["enemy", "bot"]:
		for n in arbol.get_nodes_in_group(grupo):
			var e := n as Node3D
			if e == null or e == jugador:
				continue
			if e is Enemy and (e as Enemy).dead:
				continue
			# los aliados no se apuntan
			if e is Bot and (e as Bot).mode != Bot.Mode.HOSTILE:
				continue
			var v := e.global_position + Vector3.UP * ALTURA_TORSO - origen
			var d := v.length()
			if d > ALCANCE or d < 1.0:
				continue
			var ang := adelante.angle_to(v)
			if ang < mejor_ang and _visible(jugador, camara, e):
				mejor_ang = ang
				mejor = e
	_objetivo = mejor
	_angulo = mejor_ang if mejor != null else 99.0


## Un rayo barato: si hay una pared en medio no se ayuda (no atraviesa muros).
func _visible(jugador: Node3D, camara: Camera3D, e: Node3D) -> bool:
	var espacio := camara.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		camara.global_position, e.global_position + Vector3.UP * ALTURA_TORSO, 1)
	if jugador is CollisionObject3D:
		q.exclude = [(jugador as CollisionObject3D).get_rid()]
	return espacio.intersect_ray(q).is_empty()
