extends Node
## Cliente de equipos: HUD con puntos, balizas en los puntos de captura, y quien es rival.
var fallos := 0
func check(n: String, ok: bool, d = null) -> void:
	print("  ", "ok   " if ok else "FALLA", " ", n, "" if ok else "  [%s]" % str(d))
	if not ok: fallos += 1
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _sesion_falsa() -> void:
	pass
func _estado(modo: String, rojo: int, azul: int, objetivos: Array) -> Dictionary:
	return {"mode": modo, "players": [{"user_id": "yo", "team": "rojo"}, {"user_id": "amigo", "team": "rojo"}, {"user_id": "rival", "team": "azul"}],
		"eq": {"tipo": modo, "puntos": {"rojo": rojo, "azul": azul}, "meta": 200, "objetivos": objetivos,
			"equipos": {"yo": "rojo", "amigo": "rojo", "rival": "azul"}}}
func _correr() -> void:
	DuelClient.yo_para_pruebas = "yo"
	var arbol := get_tree()
	arbol.change_scene_to_file("res://Levels/SnowFields.tscn")
	for _i in 30: await arbol.process_frame
	print("[duelo normal]")
	DuelClient._on_estado_sala({"mode": "duelo", "players": []})
	check("duelo individual: activo, sin equipos", DuelClient.activo and not DuelClient.es_equipos())
	check("duelo individual: todos son rivales", DuelClient.es_rival("cualquiera"))
	DuelClient._on_estado_sala({"mode": "coop_waves", "players": []})
	check("fuera del duelo: se apaga", not DuelClient.activo)
	for modo in ["tdm", "dominio", "caliente"]:
		print("[", modo, "]")
		var objs := [{"id": 1, "x": 5.0, "z": 5.0, "radio": 7.0, "dueno": null, "activo": true, "disputado": false},
			{"id": 2, "x": -9.0, "z": 3.0, "radio": 7.0, "dueno": "rojo", "activo": true, "disputado": false}] if modo != "tdm" else []
		DuelClient._on_estado_sala(_estado(modo, 120, 85, objs))
		check("%s: modo de equipos activo" % modo, DuelClient.es_equipos() and DuelClient.modo == modo)
		check("%s: sabe que soy del equipo rojo" % modo, DuelClient.mi_equipo == "rojo", DuelClient.mi_equipo)
		check("%s: el companero NO es rival" % modo, not DuelClient.es_rival("amigo"))
		check("%s: el otro equipo SI es rival" % modo, DuelClient.es_rival("rival"))
		var hud := DuelClient.find_child("HudEquipos", true, false) as Control
		check("%s: el marcador de equipos es visible" % modo, hud != null and hud.visible)
		check("%s: muestra los puntos 120 y 85" % modo, DuelClient._hud_rojo.text == "ROJO 120" and DuelClient._hud_azul.text == "85 AZUL", [DuelClient._hud_rojo.text, DuelClient._hud_azul.text])
		check("%s: muestra la meta" % modo, DuelClient._hud_meta.text == "META 200", DuelClient._hud_meta.text)
		check("%s: baliza por cada punto (%d)" % [modo, objs.size()], DuelClient._balizas.size() == objs.size(), DuelClient._balizas.size())
		if objs.size() > 0:
			var b: Node3D = DuelClient._balizas[2]
			check("%s: baliza en su sitio (-9,3)" % modo, absf(b.global_position.x + 9.0) < 0.01 and absf(b.global_position.z - 3.0) < 0.01, b.global_position)
			var col := ((b.get_node("Haz") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
			check("%s: punto del equipo rojo se ve ROJO" % modo, col.r > 0.8 and col.b < 0.3, col)
			var neutral := ((DuelClient._balizas[1].get_node("Haz") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
			check("%s: punto sin dueno se ve GRIS" % modo, absf(neutral.r - neutral.b) < 0.05, neutral)
	print("[el punto cambia de dueno y se disputa]")
	DuelClient._on_estado_sala(_estado("dominio", 130, 90, [{"id": 1, "x": 5.0, "z": 5.0, "radio": 7.0, "dueno": "azul", "activo": true, "disputado": false}]))
	var c1 := ((DuelClient._balizas[1].get_node("Haz") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	check("pasa a AZUL cuando lo captura el rival", c1.b > 0.8 and c1.r < 0.4, c1)
	DuelClient._on_estado_sala(_estado("dominio", 130, 90, [{"id": 1, "x": 5.0, "z": 5.0, "radio": 7.0, "dueno": "azul", "activo": true, "disputado": true}]))
	var c2 := ((DuelClient._balizas[1].get_node("Haz") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	check("disputado se ve AMBAR", c2.r > 0.9 and c2.g > 0.6 and c2.b < 0.4, c2)
	print("[punto caliente rota: la baliza vieja desaparece]")
	DuelClient._on_estado_sala(_estado("caliente", 10, 10, [{"id": 1, "x": 5.0, "z": 5.0, "radio": 7.0, "dueno": null, "activo": true}]))
	DuelClient._on_estado_sala(_estado("caliente", 10, 10, [{"id": 1, "x": -20.0, "z": 18.0, "radio": 7.0, "dueno": null, "activo": true}]))
	check("sigue habiendo UNA sola baliza", DuelClient._balizas.size() == 1, DuelClient._balizas.size())
	check("y se movio al nuevo sitio", absf(DuelClient._balizas[1].global_position.x + 20.0) < 0.01, DuelClient._balizas[1].global_position)
	print("[al salir de la partida se limpia todo]")
	DuelClient._on_estado_sala({"mode": "coop_waves", "players": []})
	await arbol.process_frame
	check("sin balizas", DuelClient._balizas.is_empty())
	check("sin equipo", DuelClient.mi_equipo == "" and not DuelClient.es_equipos())
	var hud2 := DuelClient.find_child("HudEquipos", true, false) as Control
	check("marcador de equipos oculto", hud2 == null or not hud2.visible)
	print("EQUIPOS_CLIENTE: ", "TODO OK" if fallos == 0 else "%d FALLOS" % fallos)
	arbol.quit(1 if fallos > 0 else 0)
