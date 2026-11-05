class_name BotLook
extends Node3D
## Apariencia del bot: el personaje Neko (CC0, chibineko) tintado con el color
## del equipo. El modelo viene con esqueleto pero sin animaciones, así que el
## movimiento se anima por código: rebote al andar, inclinación al esquivar y
## giro al deslizarse.

const MODEL := "res://Assets/Characters/chibineko.glb"
## Altura final del personaje en metros. Se mide la caja real del modelo y se
## escala a esto, para que quede del tamaño de los jugadores y no gigante.
const TARGET_HEIGHT := 1.8

var _model: Node3D
var _tint: Color = Color(0.35, 0.85, 1.0)
var _bob := 0.0
var _lean := 0.0
var _spin := 0.0

## Caminata procedural: el modelo trae esqueleto pero ninguna animacion, asi que se mueven los
## huesos por codigo. Se guardan las poses de reposo para animar sobre ellas, nunca a ciegas.
var _skel: Skeleton3D
var _huesos := {}      # nombre -> {idx, reposo (Quaternion)}
var _fase := 0.0
var _amp := 0.0        # amplitud suavizada (0 = quieto)
const HUESOS_ANIM := ["upper_leg.L", "upper_leg.R", "lower_leg.L", "lower_leg.R", "upper_arm.L", "upper_arm.R", "spine", "tail", "tail4", "tail8"]


func build(tint: Color) -> void:
	_tint = tint
	var res := load(MODEL)
	if res == null:
		return
	var inst: Node3D = res.instantiate()
	if inst == null:
		return
	_model = inst
	add_child(_model)
	_fit_to_height()
	_apply_tint(_model, tint)
	_preparar_huesos()


## Ajusta escala y altura del modelo para que mida TARGET_HEIGHT y apoye los pies
## en el suelo. Antes se escalaba a mano y salia de 2,4 m: mas alto que el jugador.
func _fit_to_height() -> void:
	_model.scale = Vector3.ONE
	var caja := _local_aabb(_model)
	if caja.size.y <= 0.001:
		return
	var factor: float = TARGET_HEIGHT / caja.size.y
	_model.scale = Vector3.ONE * factor
	# Se recoloca para que la base quede exactamente en y=0.
	_model.position.y = -caja.position.y * factor


func _local_aabb(node: Node3D) -> AABB:
	var total := AABB()
	var primero := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var caja: AABB = m.transform * m.get_aabb()
		if primero:
			total = caja
			primero = false
		else:
			total = total.merge(caja)
	return total


## El color marca el bando sin tapar el diseño del personaje: se tiñe solo la
## emisión, nunca el albedo, para que la skin siga viéndose.
func _apply_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1)
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.55
		mat.vertex_color_use_as_albedo = true
		mi.material_override = mat
	for c in node.get_children():
		_apply_tint(c, tint)


func set_tint(tint: Color) -> void:
	_tint = tint
	if _model:
		_apply_tint(_model, tint)


## speed: m/s reales; dodging: esquiva lateral; sliding: deslizamiento.
func animate(delta: float, speed: float, dodging: bool, sliding: bool) -> void:
	if _model == null:
		return
	_caminar(delta, speed)
	_bob += delta * (6.0 + speed * 1.6)
	var hop := absf(sin(_bob)) * minf(0.12, 0.02 + speed * 0.018)
	_model.position.y = hop
	if sliding:
		# Tumbado y girando: el deslizamiento se nota de un vistazo.
		_lean = lerpf(_lean, -0.55, minf(1.0, delta * 8.0))
		_spin += delta * 3.2
		_model.rotation = Vector3(_lean, _spin, _lean * 0.6)
	elif dodging:
		_lean = lerpf(_lean, -0.22, minf(1.0, delta * 10.0))
		_spin = lerpf(_spin, 0.0, minf(1.0, delta * 8.0))
		_model.rotation = Vector3(_lean, 0.0, _lean)
	else:
		_lean = lerpf(_lean, 0.0, minf(1.0, delta * 7.0))
		_spin = lerpf(_spin, 0.0, minf(1.0, delta * 7.0))
		_model.rotation.x = lerpf(_model.rotation.x, _lean, minf(1.0, delta * 7.0))
		_model.rotation.y = _spin
		_model.rotation.z = 0.0


func _preparar_huesos() -> void:
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_skel = sk[0] as Skeleton3D
	for nombre in HUESOS_ANIM:
		var i := _skel.find_bone(nombre)
		if i >= 0:
			_huesos[nombre] = {"idx": i, "reposo": _skel.get_bone_pose_rotation(i)}


func _girar(nombre: String, eje: Vector3, angulo: float) -> void:
	var h = _huesos.get(nombre)
	if h == null:
		return
	_skel.set_bone_pose_rotation(h["idx"], (h["reposo"] as Quaternion) * Quaternion(eje, angulo))


## Ciclo de caminata: piernas y brazos en oposicion, rodilla que se dobla al levantar el pie, torso
## con un leve giro y cola que se balancea. speed (m/s) fija el ritmo y la amplitud.
func _caminar(delta: float, speed: float) -> void:
	if _skel == null:
		return
	var objetivo := clampf(speed / 3.0, 0.0, 1.0) if speed > 0.35 else 0.0
	_amp = lerpf(_amp, objetivo, minf(1.0, delta * 8.0))
	_fase += delta * (4.0 + minf(speed, 6.0) * 1.7)
	var s := sin(_fase)
	var c := cos(_fase)
	var paso := 0.75 * _amp
	_girar("upper_leg.L", Vector3.RIGHT, s * paso)
	_girar("upper_leg.R", Vector3.RIGHT, -s * paso)
	# la rodilla solo se dobla hacia atras, cuando la pierna sube
	_girar("lower_leg.L", Vector3.RIGHT, maxf(0.0, -c) * 0.9 * _amp)
	_girar("lower_leg.R", Vector3.RIGHT, maxf(0.0, c) * 0.9 * _amp)
	_girar("upper_arm.L", Vector3.RIGHT, -s * 0.55 * _amp)
	_girar("upper_arm.R", Vector3.RIGHT, s * 0.55 * _amp)
	_girar("spine", Vector3.UP, s * 0.12 * _amp)
	var cola := sin(_fase * 0.5) * (0.18 + 0.12 * _amp)
	_girar("tail", Vector3.UP, cola)
	_girar("tail4", Vector3.UP, cola * 0.8)
	_girar("tail8", Vector3.UP, cola * 0.6)
