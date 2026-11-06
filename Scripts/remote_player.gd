class_name RemotePlayer
extends Node3D

## Personaje online visible. Temática del juego: un reciclador de chatarra con
## placa de acero, franja de peligro y visor encendido; el color del visor, la
## franja y el nombre identifican a cada jugador.
##
## El original no tenía cuerpo para los demás: cada peer instanciaba un Player.tscn
## completo (otra cámara y otros controles) y aun así nadie veía a nadie.

const LERP_SPEED := 14.0
const WALK_BOB_SPEED := 9.0
const IDLE_BOB_SPEED := 1.6

@onready var name_tag: Label3D = %NameTag
@onready var body_root: Node3D = %Body
@onready var torso: MeshInstance3D = %Torso
@onready var head: MeshInstance3D = %Head
@onready var visor: MeshInstance3D = %Visor
@onready var hazard: MeshInstance3D = %HazardStripe
@onready var antenna_tip: MeshInstance3D = %AntennaTip
@onready var leg_l: MeshInstance3D = %LegL
@onready var leg_r: MeshInstance3D = %LegR
@onready var ring: MeshInstance3D = get_node_or_null("GroundRing")

## Más allá de esta distancia la etiqueta del nombre se oculta.
const NAME_VISIBLE_DISTANCE := 30.0
## La etiqueta ya NO es de tamano fijo en pantalla (eso la hacia enorme de cerca y de lejos).
## Mide lo mismo en el mundo que una persona: se ve grande de cerca y pequena de lejos.
const NAME_MIN_SCALE := 0.7
const NAME_MAX_SCALE := 1.6

var display_name: String = ""

var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _has_target: bool = false
var _prev_position: Vector3 = Vector3.ZERO
var _bob_time: float = 0.0


## Apariencia Neko (la misma de los bots y de la tienda de skins). El robot de cajas original
## solo queda como respaldo si el modelo no carga.
var _neko: BotLook
var _skin_id: String = ""


func _enter_tree() -> void:
	add_to_group("remote_player")


func setup(player_name: String, tint: Color, skin_id: String = "") -> void:
	display_name = player_name if not player_name.is_empty() else "Jugador"
	if is_instance_valid(name_tag):
		name_tag.text = display_name
		name_tag.modulate = tint.lightened(0.4)
	_apply_tint(tint)
	set_skin(skin_id, tint)


## Viste al jugador con una skin de la tienda (id "neko_fuego", etc.). Sin skin conocida usa el
## color de equipo. El cuerpo de cajas se oculta en cuanto el Neko esta listo.
func set_skin(skin_id: String, fallback_tint: Color = Color(0.35, 0.85, 1.0)) -> void:
	_skin_id = skin_id
	var color := fallback_tint
	# Shop.skin() devuelve la clasica si el id no existe; solo se usa la skin cuando el id es valido
	if skin_id != "":
		for def in Shop.SKINS:
			if def["id"] == skin_id:
				color = def["color"]
				break
	if _neko == null:
		_neko = BotLook.new()
		_neko.name = "Neko"
		add_child(_neko)
		_neko.build(color)
		if _neko.get_child_count() > 0:
			# el Neko esta listo: fuera el robot de cajas (se mantienen los nodos por si algo los consulta)
			for n in [body_root]:
				if is_instance_valid(n):
					n.visible = false
	else:
		_neko.set_tint(color)


func _apply_tint(tint: Color) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.17, 0.19, 0.22)
	steel.metallic = 0.72
	steel.roughness = 0.48
	for mesh_node in [torso, head, leg_l, leg_r]:
		if is_instance_valid(mesh_node):
			mesh_node.material_override = steel

	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.11, 0.12, 0.14)
	plate.metallic = 0.6
	plate.roughness = 0.55
	for child in body_root.get_children():
		if child is MeshInstance3D and child.material_override == null:
			child.material_override = plate

	var glow := StandardMaterial3D.new()
	glow.albedo_color = tint
	glow.emission_enabled = true
	glow.emission = tint
	glow.emission_energy_multiplier = 2.2
	if is_instance_valid(visor):
		visor.material_override = glow
	if is_instance_valid(hazard):
		var stripe := StandardMaterial3D.new()
		stripe.albedo_color = tint
		stripe.emission_enabled = true
		stripe.emission = tint
		stripe.emission_energy_multiplier = 1.4
		hazard.material_override = stripe
	if is_instance_valid(ring):
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.85)
		ring.material_override = ring_mat
	if is_instance_valid(antenna_tip):
		var beacon := StandardMaterial3D.new()
		beacon.albedo_color = tint.lightened(0.3)
		beacon.emission_enabled = true
		beacon.emission = tint.lightened(0.2)
		beacon.emission_energy_multiplier = 2.6
		antenna_tip.material_override = beacon


## Recibe el estado del dueño del personaje y arranca la suavización.
func push_transform(world_position: Vector3, yaw: float) -> void:
	_target_position = world_position
	_target_yaw = yaw
	if not _has_target:
		global_position = world_position
		rotation.y = yaw
		_prev_position = world_position
		_has_target = true


## A mas de esta distancia (m) un avatar remoto no se anima: no se distingue y cuesta CPU en portatiles.
const LEJOS_SIN_ANIMAR := 70.0


func _process(delta: float) -> void:
	if not _has_target:
		return
	var step := clampf(LERP_SPEED * delta, 0.0, 1.0)
	global_position = global_position.lerp(_target_position, step)
	rotation.y = lerp_angle(rotation.y, _target_yaw, step)
	# Muy lejos de la camara (o invisible) nadie ve las piernas ni la etiqueta: se ahorra la animacion.
	if not visible:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(global_position) > LEJOS_SIN_ANIMAR * LEJOS_SIN_ANIMAR:
		_prev_position = global_position
		return
	_animate_body(delta)


## Balanceo de piernas y respiración: sin esto el avatar parecía una estatua
## deslizándose por el mapa.
func _animate_body(delta: float) -> void:
	if body_root == null:
		return
	var speed: float = global_position.distance_to(_prev_position) / maxf(delta, 0.0001)
	_prev_position = global_position
	var moving: bool = speed > 0.35
	if _neko != null:
		_neko.animate(delta, speed, false, false)
	_bob_time += delta * (WALK_BOB_SPEED if moving else IDLE_BOB_SPEED)
	var amplitude: float = 0.55 if moving else 0.06
	var swing: float = sin(_bob_time) * amplitude
	if is_instance_valid(leg_l):
		leg_l.rotation.x = swing
	if is_instance_valid(leg_r):
		leg_r.rotation.x = -swing
	body_root.position.y = absf(sin(_bob_time)) * (0.045 if moving else 0.012)
	if is_instance_valid(name_tag):
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			var dist: float = camera.global_position.distance_to(global_position)
			name_tag.visible = dist < NAME_VISIBLE_DISTANCE
			# un poco mas grande al alejarse para seguir leyendose, sin pasarse
			var k: float = clampf(0.6 + dist * 0.045, NAME_MIN_SCALE, NAME_MAX_SCALE)
			name_tag.scale = Vector3.ONE * k


## Color estable por jugador: el mismo nombre siempre da el mismo tono.
static func color_for(key: String) -> Color:
	var seed_value: int = abs(key.hash())
	var hue: float = float(seed_value % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 1.0)
