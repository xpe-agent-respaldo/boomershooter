extends Node
## Pedir ayuda deja un marcador con el nombre de quien lo pide y una baliza en el mundo hasta que llegas.
var fallos := 0
func _ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FALLA ") + m)
	if not c: fallos += 1
func _ready() -> void:
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_correr.call_deferred()
func _correr() -> void:
	var a := get_tree()
	await a.process_frame
	a.change_scene_to_file("res://Levels/SpaceArena.tscn")
	await a.create_timer(6.0).timeout
	var p: Player = Global.player
	var lejos: Vector3 = p.global_position + Vector3(30, 0, 0)
	var aviso := {"kind": "help", "reason": "help", "user_id": "otro-1", "username": "Marta", "text": "Marta necesita ayuda.",
		"severity": 2, "pos": {"x": lejos.x, "y": lejos.y, "z": lejos.z}}
	TeamAlerts._on_team_alert(aviso)
	await a.create_timer(0.3).timeout
	_ok(TeamAlerts._arrows.has("otro-1"), "se crea el marcador de ayuda")
	var m: Dictionary = TeamAlerts._arrows.get("otro-1", {})
	var dist_label: Label = m.node.get_node("Distance")
	_ok(dist_label.text.begins_with("Marta"), "el marcador lleva el NOMBRE de quien pide ayuda: '%s'" % dist_label.text)
	_ok(dist_label.text.ends_with("m"), "y la distancia")
	_ok(a.get_nodes_in_group("baliza_ayuda").size() == 1, "hay una baliza vertical en el mundo 3D")
	var restante: float = m.expires - Time.get_ticks_msec() / 1000.0
	_ok(restante > 30.0, "dura mas que una flecha normal (%.0f s)" % restante)
	# una flecha normal (jugador caido) NO lleva baliza y dura menos
	TeamAlerts._on_team_alert({"kind": "player_down", "user_id": "otro-2", "username": "Leo", "text": "Leo cayo", "severity": 3, "pos": {"x": lejos.x, "y": lejos.y, "z": lejos.z + 10}})
	_ok(a.get_nodes_in_group("baliza_ayuda").size() == 1, "un jugador caido no pone baliza (solo la peticion de ayuda)")
	# al llegar, se retira marcador y baliza
	p.global_position = lejos + Vector3(2, 0, 0)
	await a.create_timer(0.6).timeout
	_ok(not TeamAlerts._arrows.has("otro-1"), "al llegar a menos de 6 m el marcador desaparece")
	await a.process_frame
	_ok(a.get_nodes_in_group("baliza_ayuda").size() == 0, "y la baliza tambien")
	# quien pide ayuda soy yo: no se me marca a mi mismo
	TeamAlerts._on_team_alert({"kind": "help", "user_id": OnlineManager.get_local_user_id(), "username": "yo", "text": "yo necesito ayuda", "severity": 2, "pos": {"x": 0, "y": 0, "z": 0}})
	_ok(not TeamAlerts._arrows.has(OnlineManager.get_local_user_id()), "mi propia peticion no me pone un marcador a mi")
	print("AYUDA_MARCA: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(0 if fallos == 0 else 1)
