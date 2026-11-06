extends Node
## Pantalla de crear sala: las opciones ciclan, viajan al servidor y todo cabe en pantalla.
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
	a.change_scene_to_file("res://Levels/Lobby.tscn")
	await a.create_timer(2.5).timeout
	var lobby = a.current_scene
	var o: Dictionary = lobby.opciones_sala()
	_ok(o.monsters == true and o.bots == 3 and o.max_players == 20, "valores por defecto = los del servidor: " + str(o))
	lobby._opt_monstruos.pressed.emit()
	_ok(lobby.opciones_sala().monsters == false and lobby._opt_monstruos.text == "MONSTRUOS: NO", "el boton MONSTRUOS alterna sin monstruos")
	for i in 5: lobby._opt_bots.pressed.emit()
	_ok(lobby.opciones_sala().bots == 3, "BOTS da la vuelta completa (0,1,2,3,5)")
	# vuelta completa de BOTS: tras otras 5 pulsaciones se pasa por todos los valores y se ve el 0
	var vistos := {}
	for i in 5:
		lobby._opt_bots.pressed.emit()
		vistos[lobby.opciones_sala().bots] = true
	_ok(vistos.has(0) and vistos.has(5) and vistos.size() == 5, "BOTS recorre 0,1,2,3,5 (incluye sala sin bots): " + str(vistos.keys()))
	lobby._opt_jug.pressed.emit()
	_ok(lobby.opciones_sala().max_players == 2, "JUGADORES cicla (20 -> 2)")
	# el lienzo base es 1920x1080 y se escala a la ventana: todo debe caber en 1080 de alto
	var base := a.root.get_visible_rect().size
	print("    lienzo base = ", base)
	var r: Rect2 = lobby.play_button.get_global_rect()
	print("    boton CREAR SALA: y=", snappedf(r.position.y, 1), " a ", snappedf(r.end.y, 1))
	_ok(r.end.y <= base.y - 8.0, "el boton CREAR SALA cabe en el lienzo (termina en %d de %d)" % [r.end.y, base.y])
	var mayor := 0.0
	for hijo in lobby.find_children("*", "Control", true, false):
		# el fondo animado (TextureRect directo del lobby) es mas grande que la pantalla a proposito
		if hijo.is_visible_in_tree() and not (hijo is TextureRect and hijo.get_parent() == lobby):
			var fin: float = (hijo as Control).get_global_rect().end.y
			if fin > base.y:
				print("    fuera: ", hijo.get_class(), " '", hijo.name, "' texto='", hijo.get("text") if hijo.get("text") != null else "", "' y=", snappedf(fin, 1), " padre=", hijo.get_parent().name)
			mayor = maxf(mayor, fin)
	_ok(mayor <= base.y + 1.0, "ningun control visible se sale por abajo (el mas bajo termina en %d)" % mayor)
	print("OPCIONES_SALA: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(0 if fallos == 0 else 1)
