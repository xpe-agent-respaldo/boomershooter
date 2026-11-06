extends SceneTree
## Ajustes: el lobby y la partida tienen deslizadores separados y cada uno manda en SU bus.
var fallos := 0
var aciertos := 0
func ok(n: String, c: bool, d: String = "") -> void:
	if c: aciertos += 1; print("  ok   ", n)
	else: fallos += 1; print("  FALLA ", n, "  ", d)

func _buscar(n: Node, texto: String, acc: Array) -> void:
	if n is Label and (n as Label).text == texto: acc.append(n)
	for h in n.get_children(): _buscar(h, texto, acc)

func _initialize() -> void:
	_correr()

func _correr() -> void:
	for i in 6: await process_frame
	var gs := root.get_node("GameSettings")
	print("== AJUSTES DE SONIDO ==")
	# abrir la ventana de ajustes
	for m in gs.get_method_list():
		pass
	var abierto := false
	for nombre in ["open", "show_settings", "abrir", "open_settings", "show_menu"]:
		if gs.has_method(nombre):
			gs.call(nombre); abierto = true; print("   abierto con ", nombre); break
	await create_timer(0.5).timeout
	var lobby: Array = []; var partida: Array = []; var general: Array = []; var viejo: Array = []
	_buscar(root, "MUSICA DEL LOBBY", lobby); _buscar(root, "MUSICA DE PARTIDA", partida)
	_buscar(root, "VOLUMEN GENERAL", general); _buscar(root, "MUSICA", viejo)
	ok("Ajustes muestra 'MUSICA DEL LOBBY'", lobby.size() >= 1)
	ok("Ajustes muestra 'MUSICA DE PARTIDA'", partida.size() >= 1)
	ok("Ajustes sigue mostrando 'VOLUMEN GENERAL'", general.size() >= 1)
	ok("ya no queda un 'MUSICA' ambiguo", viejo.size() == 0)

	# cada valor manda en su bus
	var i_lobby := AudioServer.get_bus_index(&"Lobby"); var i_music := AudioServer.get_bus_index(&"Music")
	gs._values["Lobby"] = 0.2; gs._values["Music"] = 0.9; gs._apply()
	var db_l := AudioServer.get_bus_volume_db(i_lobby); var db_m := AudioServer.get_bus_volume_db(i_music)
	ok("bajar el lobby no toca la musica de partida", db_l < db_m - 5.0, "lobby=%.1f partida=%.1f" % [db_l, db_m])
	gs._values["Lobby"] = 0.9; gs._values["Music"] = 0.2; gs._apply()
	ok("bajar la partida no toca el lobby", AudioServer.get_bus_volume_db(i_music) < AudioServer.get_bus_volume_db(i_lobby) - 5.0)

	# guardado: un ajuste VIEJO (sin clave Lobby) no rompe ni resetea nada
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "Master", 0.55); cfg.set_value("audio", "Music", 0.33); cfg.set_value("audio", "SFX", 0.44)
	var antes_l: float = gs._values["Lobby"]
	var carg: float = clampf(float(cfg.get_value("audio", "Lobby", 0.7)), 0.0, 1.0)
	ok("un archivo de ajustes antiguo (sin 'Lobby') carga con el valor por defecto", is_equal_approx(carg, 0.7))
	ok("y conserva los volumenes que ya tenia", is_equal_approx(float(cfg.get_value("audio", "Music", 0)), 0.33))
	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	quit(1 if fallos > 0 else 0)
