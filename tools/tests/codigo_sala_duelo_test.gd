extends Node
## En un Duelo (sin oleadas) el anfitrion ve el codigo de la sala para pasarselo al amigo.
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
	OnlineManager.room_code = "K7M2Q"
	OnlineManager.room_private = true
	a.change_scene_to_file("res://Levels/SpaceArena.tscn")
	await a.create_timer(6.0).timeout
	var hud: Node = null
	for n in a.get_nodes_in_group("wave_hud"): hud = n
	if hud == null:
		hud = a.current_scene.find_child("WaveHUD", true, false)
	if hud == null:
		for n in a.current_scene.find_children("*", "", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("wave_hud.gd"): hud = n; break
	_ok(hud != null, "el HUD de la partida existe en SpaceArena")
	if hud != null:
		hud._on_codigo_sala("K7M2Q")
		_ok(hud._sala.visible, "la etiqueta de la sala se ve")
		_ok(hud._sala.text.contains("K7M2Q") and hud._sala.text.contains("PRIVADA"), "dice el codigo y PRIVADA (%s)" % hud._sala.text)
	print("\nCODIGO SALA: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(1 if fallos else 0)
