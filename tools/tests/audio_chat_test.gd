extends Node
## Musica del lobby y chat al cambiar de interfaz. Se ejecuta de verdad: cambia de escena
## y mira que reproductor suena, en que bus, y si el chat se ve.

var fallos := 0
var aciertos := 0


func ok(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		aciertos += 1
		print("  ok   ", nombre)
	else:
		fallos += 1
		print("  FALLA ", nombre, "  ", detalle)


func _esperar(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Espera tiempo REAL: los fundidos duran segundos, y sin ventana el motor corre cientos de fps.
func _esperar_s(segundos: float) -> void:
	await get_tree().create_timer(segundos).timeout


func _ir_a(nombre: String) -> void:
	# Se libera la escena anterior ANTES de crear la nueva: si no, Godot renombra el nodo
	# (@Node@12) al chocar con el nombre y la escena activa deja de llamarse como se espera.
	var anterior := get_tree().current_scene
	if anterior != null and anterior != self:
		get_tree().root.remove_child(anterior)
		anterior.free()
	# Cualquier nodo viejo con ese nombre (p.ej. de una escena anterior) se retira tambien.
	var viejo := get_tree().root.get_node_or_null(nombre)
	if viejo != null:
		get_tree().root.remove_child(viejo)
		viejo.free()
	var escena := Node.new()
	escena.name = nombre
	escena.scene_file_path = "res://Levels/%s.tscn" % nombre
	get_tree().root.add_child(escena, true)
	get_tree().current_scene = escena
	await _esperar(6)


func _ready() -> void:
	print("== MUSICA DEL LOBBY Y CHAT ==")
	await _esperar(5)
	var lm := get_node("/root/LobbyMusic")
	var md := get_node("/root/MusicDirector")
	var chat := get_node("/root/GameChat")
	var player: AudioStreamPlayer = lm._player

	# --- bus ---
	var idx := AudioServer.get_bus_index(&"Lobby")
	ok("existe el bus 'Lobby' aparte del de partida", idx >= 0 and AudioServer.get_bus_index(&"Music") >= 0 and idx != AudioServer.get_bus_index(&"Music"))
	ok("la musica del lobby suena por el bus Lobby", player.bus == &"Lobby")
	ok("la musica de partida sigue en el bus Music", md._player.bus == &"Music")
	ok("Ajustes tiene volumen propio para el lobby", GameSettings.BUS_NAMES.has("Lobby") and GameSettings._values.has("Lobby"))

	# --- menus: suena y NO se corta al cambiar de pantalla ---
	await _ir_a("MainMenu")
	ok("en el menu principal suena la musica del lobby", player.playing)
	var stream_menu := player.stream
	var pos_menu := player.get_playback_position()
	await _esperar(30)
	for destino in ["Lobby", "Shop", "Achievements", "ArenaSelect", "MainMenu"]:
		await _ir_a(destino)
		ok("al pasar a %s sigue sonando el MISMO tema" % destino, player.playing and player.stream == stream_menu)
	ok("no se reinicio al cambiar de interfaz (la posicion avanzo)", player.get_playback_position() >= pos_menu,
		"%.2f < %.2f" % [player.get_playback_position(), pos_menu])
	ok("MusicDirector no pone musica de partida en los menus", not md._player.playing)

	# --- entrar a una partida: se apaga la del lobby ---
	await _ir_a("StormVillage")
	await _esperar_s(1.2)
	ok("en partida la musica del lobby se apaga", not player.playing, "playing=%s vol=%.1f" % [player.playing, player.volume_db])
	ok("en partida suena la musica de la partida", md._player.playing)
	await _esperar_s(1.0)
	ok("sigue apagada durante la partida (no vuelve sola)", not player.playing)

	# --- volver al menu: vuelve el lobby y se calla la de partida ---
	await _ir_a("MainMenu")
	await _esperar_s(0.3)
	ok("al volver al menu suena de nuevo la del lobby", player.playing)
	ok("al volver al menu se calla la de partida", not md._player.playing)

	# --- chat ---
	print("-- chat --")
	await _ir_a("MainMenu")
	ok("en el menu el chat no se ve", not chat._panel.visible)
	chat.show_system_message("aviso que llega tarde")
	ok("un mensaje que llega en un menu se descarta", not chat._panel.visible and chat._lines.is_empty())
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	chat._unhandled_input(enter)
	ok("Enter no abre el chat en un menu", not chat._open and not chat._panel.visible)

	await _ir_a("StormVillage")
	chat.show_system_message("hola partida")
	ok("en partida el chat muestra los mensajes", chat._panel.visible and chat._lines.size() == 1)
	chat._unhandled_input(enter)
	ok("en partida Enter abre el chat", chat._open)

	await _ir_a("Lobby")
	ok("al volver al lobby el chat ya no se ve", not chat._panel.visible)
	ok("al volver al lobby el chat esta cerrado y vacio", not chat._open and chat._lines.is_empty() and chat._history.text == "")

	await _ir_a("RecyclingPlant")
	ok("la partida siguiente empieza con el chat limpio", chat._lines.is_empty() and chat._history.text == "")

	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit(1 if fallos > 0 else 0)
