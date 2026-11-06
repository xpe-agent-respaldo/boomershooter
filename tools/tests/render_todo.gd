extends Node
## Renderiza de verdad cada mapa y cada pantalla: carga la escena, deja correr frames y comprueba
## que hay camara activa, luz, geometria visible y que nada revienta. Una linea por escena.
const ESCENAS := [
	"res://Levels/MainMenu.tscn", "res://Levels/Lobby.tscn", "res://Levels/ArenaSelect.tscn",
	"res://Levels/Shop.tscn", "res://Levels/Achievements.tscn",
	"res://Levels/RecyclingPlant.tscn", "res://Levels/StormVillage.tscn", "res://Levels/SpaceArena.tscn", "res://Levels/SnowFields.tscn",
]
var fallos := 0
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _contar(n: Node, t: Dictionary) -> void:
	if n is MeshInstance3D and n.visible and n.mesh != null: t["mallas"] += 1
	elif n is Light3D and n.visible: t["luces"] += 1
	elif n is Camera3D: t["camaras"] += 1
	elif n is Control and n.visible: t["ui"] += 1
	for h in n.get_children(): _contar(h, t)
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	for ruta in ESCENAS:
		var t0 := Time.get_ticks_msec()
		arbol.change_scene_to_file(ruta)
		for _i in 20: await arbol.process_frame
		var esc := arbol.current_scene
		if esc == null:
			print("RENDER FALLA ", ruta, " sin escena"); fallos += 1; continue
		var t := {"mallas": 0, "luces": 0, "camaras": 0, "ui": 0}
		_contar(esc, t)
		var es_mapa: bool = ruta.contains("Plant") or ruta.contains("Village") or ruta.ends_with("SpaceArena.tscn") or ruta.ends_with("SnowFields.tscn")
		var jug := (load("res://Player/Player.tscn") as PackedScene).instantiate() if es_mapa else null
		if jug != null:
			esc.add_child(jug); jug.global_position = Vector3(0, 2, 0)
			for _i in 40: await arbol.process_frame
			_contar(jug, t)
		var cam := arbol.root.get_viewport().get_camera_3d()
		var ok := true
		var motivo := ""
		if es_mapa:
			if t["mallas"] < 20: ok = false; motivo += " pocas mallas(%d)" % t["mallas"]
			if t["luces"] < 1 and arbol.root.get_viewport().world_3d.environment == null: ok = false; motivo += " sin luz ni entorno"
			if cam == null: ok = false; motivo += " sin camara activa"
			if jug != null and jug.global_position.y < -5.0: ok = false; motivo += " jugador cae (y=%.1f)" % jug.global_position.y
		else:
			if t["ui"] < 3: ok = false; motivo += " pocas piezas de UI(%d)" % t["ui"]
		print("RENDER ", "OK   " if ok else "FALLA", " ", ruta.get_file(), " | mallas=", t["mallas"], " luces=", t["luces"], " ui=", t["ui"], " nodos=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), " ", Time.get_ticks_msec() - t0, "ms", motivo)
		if not ok: fallos += 1
	print("RENDER_TODO: ", "TODO OK" if fallos == 0 else "%d FALLOS" % fallos)
	arbol.quit(1 if fallos > 0 else 0)
