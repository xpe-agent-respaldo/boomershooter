extends Node
## La pantalla de final cuenta lo que paso: victoria/derrota correcta, marcador, recompensa propia,
## cabe en cualquier pantalla (portatil, iPhone) y el boton se puede pulsar.
var fallos := 0
func check(n: String, ok: bool, d = null) -> void:
	print("  ", "ok   " if ok else "FALLA", " ", n, "" if ok else "  [%s]" % str(d))
	if not ok: fallos += 1
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _texto(n: Node, nombre: String) -> String:
	var x := n.find_child(nombre, true, false)
	return (x as Label).text if x is Label else ""
func _crear(res: Dictionary, yo: String) -> EndScreen:
	var p := EndScreen.new()
	add_child(p)
	p.mostrar(res, yo)
	return p
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	var jug := [
		{"user_id": "ua", "username": "Ana", "kills": 31, "damage_dealt": 2400, "rewards": 480, "alive": true, "bot": false},
		{"user_id": "ub", "username": "Beto", "kills": 12, "damage_dealt": 900, "rewards": 210, "alive": false, "bot": false},
		{"user_id": "bot1", "username": "Robo", "kills": 99, "damage_dealt": 5000, "rewards": 0, "alive": true, "bot": true},
	]
	print("[victoria por oleadas]")
	var p := _crear({"mode": "coop_waves", "reason": "victory", "won": true, "wave_goal": 20, "wave_reached": 20, "winner_text": "Superasteis las 20 oleadas", "players": jug}, "ua")
	await arbol.process_frame
	check("titulo VICTORIA", _texto(p, "Titulo") == "VICTORIA", _texto(p, "Titulo"))
	check("subtitulo con modo y texto del servidor", "OLEADAS" in _texto(p, "Subtitulo") and "20 oleadas" in _texto(p, "Subtitulo"), _texto(p, "Subtitulo"))
	check("progreso 'OLEADA 20 DE 20'", _texto(p, "Progreso") == "OLEADA 20 DE 20", _texto(p, "Progreso"))
	check("recompensa propia (+480, la de Ana)", _texto(p, "Recompensa") == "TU RECOMPENSA: +480", _texto(p, "Recompensa"))
	var grid := p.find_child("Marcador", true, false) as GridContainer
	var nombres: Array = []
	for h in grid.get_children():
		if h is Label and (h.text.contains("Ana") or h.text.contains("Beto") or h.text.contains("Robo")): nombres.append(h.text)
	check("el marcador muestra a los humanos y NO al bot", nombres.size() == 2 and not nombres.any(func(t): return "Robo" in t), nombres)
	check("la fila propia lleva (TU)", nombres.any(func(t): return "Ana" in t and "(TU)" in t), nombres)
	check("el mejor (mas bajas) sale primero", nombres.size() > 0 and "Ana" in nombres[0], nombres)
	p.queue_free()

	print("[derrota]")
	p = _crear({"mode": "survival", "reason": "team_wipe", "won": false, "wave_goal": 15, "wave_reached": 6, "players": jug}, "ub")
	await arbol.process_frame
	check("titulo DERROTA", _texto(p, "Titulo") == "DERROTA", _texto(p, "Titulo"))
	check("explica por que: todo el equipo ha caido", "caido" in _texto(p, "Subtitulo"), _texto(p, "Subtitulo"))
	check("progreso 'OLEADA 6 DE 15'", _texto(p, "Progreso") == "OLEADA 6 DE 15", _texto(p, "Progreso"))
	p.queue_free()

	print("[duelo]")
	var duelo := {"mode": "duelo", "reason": "duel_won", "won": true, "winner": "ua", "winner_text": "Ana gana el duelo con 15 bajas", "players": jug}
	p = _crear(duelo, "ua")
	await arbol.process_frame
	check("el ganador ve VICTORIA", _texto(p, "Titulo") == "VICTORIA", _texto(p, "Titulo"))
	check("el duelo dice quien gano", "Ana gana" in _texto(p, "Subtitulo"), _texto(p, "Subtitulo"))
	check("el duelo no enseña oleadas ni recompensa", p.find_child("Progreso", true, false) == null and p.find_child("Recompensa", true, false) == null)
	p.queue_free()
	p = _crear(duelo, "ub")
	await arbol.process_frame
	check("el perdedor del duelo ve DERROTA", _texto(p, "Titulo") == "DERROTA", _texto(p, "Titulo"))
	p.queue_free()

	print("[equipos: gana el rojo]")
	var jug_eq := [
		{"user_id": "ua", "username": "Ana", "kills": 20, "damage_dealt": 1900, "rewards": 0, "alive": true, "bot": false, "team": "rojo"},
		{"user_id": "ub", "username": "Beto", "kills": 9, "damage_dealt": 700, "rewards": 0, "alive": true, "bot": false, "team": "azul"},
		{"user_id": "uc", "username": "Cleo", "kills": 14, "damage_dealt": 1200, "rewards": 0, "alive": true, "bot": false, "team": "rojo"},
	]
	var r_eq := {"mode": "dominio", "reason": "team_won", "won": true, "winner_team": "rojo", "team_points": {"rojo": 203, "azul": 171}, "winner_text": "Equipo ROJO gana 203 a 171", "players": jug_eq}
	p = _crear(r_eq, "ua")
	await arbol.process_frame
	check("equipos: el del equipo ganador ve VICTORIA", _texto(p, "Titulo") == "VICTORIA", _texto(p, "Titulo"))
	check("equipos: se ve el marcador ROJO 203 y 171 AZUL", _texto(p, "PuntosRojo") == "ROJO  203" and _texto(p, "PuntosAzul") == "171  AZUL", [_texto(p, "PuntosRojo"), _texto(p, "PuntosAzul")])
	check("equipos: dice el modo y quien gana", "DOMINAR" in _texto(p, "Subtitulo") and "ROJO gana" in _texto(p, "Subtitulo"), _texto(p, "Subtitulo"))
	check("equipos: no enseña oleadas ni recompensa", p.find_child("Progreso", true, false) == null and p.find_child("Recompensa", true, false) == null)
	p.queue_free()
	p = _crear(r_eq, "ub")
	await arbol.process_frame
	check("equipos: el del equipo perdedor ve DERROTA", _texto(p, "Titulo") == "DERROTA", _texto(p, "Titulo"))
	p.queue_free()
	p = _crear(r_eq, "uc")
	await arbol.process_frame
	check("equipos: el companero del ganador tambien ve VICTORIA", _texto(p, "Titulo") == "VICTORIA", _texto(p, "Titulo"))
	p.queue_free()

	print("[encaja en pantallas reales]")
	for res in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(1920, 1080), Vector2i(2532, 1170)]:
		arbol.root.content_scale_size = Vector2i(1920, 1080)
		arbol.root.size = res
		p = _crear({"mode": "coop_waves", "reason": "victory", "won": true, "wave_goal": 20, "wave_reached": 20, "players": jug + jug + jug}, "ua")
		for _i in 3: await arbol.process_frame
		var panel := p.find_child("BotonSalir", true, false) as Control
		var r := panel.get_global_rect()
		check("%dx%d: el boton de salir esta dentro de la pantalla y es grande" % [res.x, res.y], Rect2(0, 0, 1920, 1080).encloses(r) and r.size.y >= 56.0, r)
		p.queue_free()

	print("[sala llena: 40 jugadores, nombres largos]")
	var llena: Array = []
	for i in 40:
		llena.append({"user_id": "u%d" % i, "username": "JugadorConNombreLargo%02d" % i, "kills": 40 - i, "damage_dealt": 1000 * i, "rewards": 100, "alive": i % 2 == 0, "bot": false})
	for res in [Vector2i(844, 390), Vector2i(1280, 720), Vector2i(2532, 1170)]:
		arbol.root.content_scale_size = Vector2i(1920, 1080)
		arbol.root.size = res
		p = _crear({"mode": "horde", "reason": "team_wipe", "won": false, "wave_goal": 15, "wave_reached": 9, "players": llena}, "u7")
		for _i in 4: await arbol.process_frame
		var b := p.find_child("BotonSalir", true, false) as Control
		var rb := b.get_global_rect()
		check("%dx%d con 40 jugadores: boton de salir visible" % [res.x, res.y], Rect2(0, 0, 1920, 1080).encloses(rb), rb)
		var t := p.find_child("Titulo", true, false) as Control
		check("%dx%d con 40 jugadores: el titulo tambien" % [res.x, res.y], Rect2(0, 0, 1920, 1080).encloses(t.get_global_rect()), t.get_global_rect())
		p.queue_free()

	print("[el boton avisa]")
	p = _crear({"mode": "coop_waves", "reason": "team_wipe", "won": false, "players": jug}, "ua")
	var avisado := [false]
	p.salir_pulsado.connect(func(): avisado[0] = true)
	(p.find_child("BotonSalir", true, false) as Button).pressed.emit()
	check("pulsar VOLVER AL LOBBY emite la salida", avisado[0])
	print("PANTALLA_FINAL: ", "TODO OK" if fallos == 0 else "%d FALLOS" % fallos)
	arbol.quit(1 if fallos > 0 else 0)
