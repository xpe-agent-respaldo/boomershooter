extends Node
## Escondites y cobertura de los mapas de arena. Se colocan al cargar la escena,
## lejos de los puntos de aparicion (que estan a radio 28-30), para que nadie
## aparezca dentro de una caja.

const ARENAS := ["StormVillage", "SpaceArena", "LunarPost", "RecyclingPlant"]

var _hecho: String = ""
## Un solo material para todas las coberturas: antes cada caja creaba el suyo (22 por arena).
var _mat_cobertura: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Antes era un bucle que despertaba CADA frame en todo el juego, incluso en el menu.
	# Ahora solo se mira cuando entra un nodo hijo directo de la raiz (un cambio de escena).
	get_tree().root.child_entered_tree.connect(_on_raiz_cambio)
	_revisar.call_deferred()


func _on_raiz_cambio(_nodo: Node) -> void:
	_revisar.call_deferred()


func _revisar() -> void:
	if not is_inside_tree():
		return
	# current_scene se asigna un frame despues de que la escena entre al arbol
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var escena := get_tree().current_scene
	if escena == null or escena.name == _hecho:
		return
	if escena.name in ARENAS:
		_hecho = escena.name
		_poblar(escena)


func _poblar(raiz: Node) -> void:
	_aligerar_entorno(raiz)
	await _fusionar_mapa(raiz)
	# Marca de "suelo definitivo": los bots esperan a verla para no nacer sobre colisiones
	# que la fusion de mallas esta a punto de borrar y recrear.
	raiz.set_meta("mapa_listo", true)
	if raiz.has_node("Escondites"):
		return
	var grupo := Node3D.new()
	grupo.name = "Escondites"
	raiz.add_child(grupo)
	var piezas := _layout(str(raiz.name))
	for i in piezas.size():
		var p: Dictionary = piezas[i]
		grupo.add_child(_caja("Cobertura%d" % i, p["pos"], p["size"], p.get("giro", 0.0)))


## El cielo procedural (con textura de ruido) se calcula como un shader a pantalla completa
## en cada frame: en una GPU integrada pequena es de lo mas caro de toda la escena. En los
## modo maximo rendimiento se cambia por un color plano del mismo tono que el horizonte, y se
## simplifica el tonemap. Sin el modo, el cielo original se conserva.
func _aligerar_entorno(raiz: Node) -> void:
	# Solo con el interruptor "Modo maximo rendimiento": ningun perfil afea la imagen por si solo.
	if not GameSettings.modo_plano:
		return
	for we in raiz.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env == null:
			continue
		env = env.duplicate()          # no tocar el recurso compartido en disco
		if env.background_mode == Environment.BG_SKY and env.sky != null:
			var color := Color(0.12, 0.11, 0.16)
			var mat := env.sky.sky_material
			if mat is ProceduralSkyMaterial:
				color = (mat as ProceduralSkyMaterial).sky_horizon_color.darkened(0.25)
			env.background_mode = Environment.BG_COLOR
			env.background_color = color
			# sin cielo, la luz ambiente pasa a ser un color fijo (si no, se quedaria negra)
			if env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY:
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.glow_enabled = false
		env.adjustment_enabled = false
		(we as WorldEnvironment).environment = env


## Los mapas estan hechos con cientos de CSGBox3D (una malla, una colision y un draw call
## cada uno). MapOptimizer los hornea en una malla estatica por material. Era la causa
## principal de los 2 FPS: el fusionador existia pero nadie lo llamaba.
func _fusionar_mapa(raiz: Node) -> void:
	var mapa := raiz.get_node_or_null("Map") as Node3D
	if mapa == null:
		mapa = raiz as Node3D
	if mapa == null or mapa.has_node("MergedGeometry"):
		return
	var antes := mapa.find_children("*", "CSGShape3D", true, false).size()
	if antes == 0:
		return
	# un frame para que el CSG termine de generar su malla antes de hornearla
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(mapa) or not mapa.is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	var st: Dictionary = MapOptimizer.optimize(mapa)
	print("[MapBuilder] %s: %d piezas CSG -> %d mallas, %d triangulos (%d ms)" % [
		raiz.name, int(st.get("pieces", 0)), int(st.get("materials", 0)),
		int(st.get("triangles", 0)), Time.get_ticks_msec() - t0])


## Cada mapa tiene su propio reparto: no se ven igual dos partidas ni dos mapas.
func _layout(mapa: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mapa)
	var out: Array = []
	# anillo interior de coberturas medias
	for k in 10:
		var ang := TAU * float(k) / 10.0 + rng.randf_range(-0.2, 0.2)
		var radio := rng.randf_range(9.0, 19.0)
		var alto := rng.randf_range(1.2, 2.4)
		var ancho := rng.randf_range(1.6, 3.4)
		out.append({
			"pos": Vector3(cos(ang) * radio, alto * 0.5, sin(ang) * radio),
			"size": Vector3(ancho, alto, rng.randf_range(0.6, 1.2)),
			"giro": ang + PI * 0.5,
		})
	# dos casetas con techo para esconderse de verdad
	for k in 2:
		var ang2 := PI * float(k) + rng.randf_range(-0.5, 0.5)
		var r2 := rng.randf_range(11.0, 15.0)
		var centro := Vector3(cos(ang2) * r2, 0.0, sin(ang2) * r2)
		out.append({"pos": centro + Vector3(0, 1.4, -1.2), "size": Vector3(3.0, 2.8, 0.4), "giro": ang2})
		out.append({"pos": centro + Vector3(0, 1.4, 1.2), "size": Vector3(3.0, 2.8, 0.4), "giro": ang2})
		out.append({"pos": centro + Vector3(0, 2.8, 0), "size": Vector3(3.4, 0.3, 2.8), "giro": ang2})
	# cajas sueltas cerca del centro
	for k in 6:
		var a3 := rng.randf_range(0, TAU)
		var r3 := rng.randf_range(4.0, 8.0)
		out.append({
			"pos": Vector3(cos(a3) * r3, 0.55, sin(a3) * r3),
			"size": Vector3(1.1, 1.1, 1.1),
			"giro": rng.randf_range(0, TAU),
		})
	return out


func _caja(nombre: String, pos: Vector3, size: Vector3, giro: float) -> Node3D:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = nombre
	cuerpo.position = pos
	cuerpo.rotation.y = giro
	cuerpo.add_to_group("cover")

	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = size
	forma.shape = caja
	cuerpo.add_child(forma)

	var malla := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	malla.mesh = mesh
	if _mat_cobertura == null:
		_mat_cobertura = StandardMaterial3D.new()
		_mat_cobertura.albedo_color = Color(0.18, 0.17, 0.16)
		_mat_cobertura.metallic = 0.55
		_mat_cobertura.roughness = 0.65
	malla.material_override = _mat_cobertura
	malla.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cuerpo.add_child(malla)
	return cuerpo
