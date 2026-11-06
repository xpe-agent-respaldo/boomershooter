extends Node
## Lobby: el modo DUELO aparece, no deja elegir monstruos ni bots, y manda al servidor las opciones correctas.
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
	for _i in 20: await a.process_frame
	var lb: Node = a.current_scene
	var ids: Array = lb.MODES.map(func(m): return str(m.id))
	_ok("duelo" in ids, "DUELO esta en la lista de modos: %s" % str(ids))
	var i: int = ids.find("duelo")
	_ok(i == ids.size() - 1, "y va al final, sin mover los demas modos")
	lb._select_mode(0)
	var norm: Dictionary = lb.opciones_sala()
	_ok(bool(norm.monsters) and int(norm.bots) >= 0, "en OLEADAS siguen las opciones normales: %s" % str(norm))
	_ok(not lb._opt_monstruos.disabled and not lb._opt_bots.disabled, "y los botones de monstruos y bots se pueden pulsar")
	lb._select_mode(i)
	var d: Dictionary = lb.opciones_sala()
	_ok(d.monsters == false, "en DUELO se mandan monstruos = NO")
	_ok(int(d.bots) == 0, "y bots = 0")
	_ok(int(d.max_players) >= 2, "con aforo valido (%s)" % str(d.max_players))
	_ok(lb._opt_monstruos.disabled and lb._opt_bots.disabled, "los botones de monstruos y bots quedan bloqueados")
	_ok(lb._opt_monstruos.text == "MONSTRUOS: NO", "mostrando MONSTRUOS: NO (%s)" % lb._opt_monstruos.text)
	_ok(lb._opt_bots.text == "BOTS: 0", "y BOTS: 0 (%s)" % lb._opt_bots.text)
	_ok(lb.mode_desc.text.contains("Tab"), "la descripcion explica el marcador con Tab")
	lb._monstruos = true
	_ok(lb.opciones_sala().monsters == false, "aunque el interruptor interno estuviera en SI, el duelo manda NO")
	lb._select_mode(0)
	_ok(not lb._opt_monstruos.disabled, "al volver a OLEADAS se desbloquean otra vez")
	_ok(lb._opt_monstruos.text == "MONSTRUOS: SI", "y recuperan su valor (%s)" % lb._opt_monstruos.text)
	print("\nLOBBY DUELO: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(1 if fallos else 0)
