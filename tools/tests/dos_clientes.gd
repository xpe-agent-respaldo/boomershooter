extends Node
## Un cliente Godot real. QUIEN = nombre. SALA = texto de la fila a la que entrar (vacio = crear).
var ops70 := 0
var ops60 := 0

func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()

func _correr() -> void:
	var arbol := get_tree()
	var nombre := OS.get_environment("QUIEN")
	await arbol.process_frame
	# cada cliente de prueba necesita su propia identidad: en el mismo equipo comparten el archivo
	Nakama._device_id = nombre + "-" + OS.get_environment("TAG") + "-" + str(randi())
	OnlineManager.username = nombre + "_" + OS.get_environment("TAG")
	OnlineManager.player_state_received.connect(func(_s, _p, _y, _n): ops70 += 1)
	OnlineManager.wave_state_received.connect(func(e):
		ops60 += 1
		if ops60 == 20:
			var mios := []
			for p in (e.get("players", []) as Array):
				mios.append({"u": str(p.get("username", "?")).substr(0, 10), "bot": p.get("bot", false), "pos": p.get("pos", {})})
			print(nombre, " JUGADORES_EN_ESTADO_DEL_SERVIDOR=", mios))
	var crudos := {}
	var conectado := [false]
	var vigilar := func():
		if conectado[0] or OnlineManager.socket == null: return
		conectado[0] = true
		OnlineManager.socket.received_match_state.connect(func(ms): crudos[int(ms.op_code)] = int(crudos.get(int(ms.op_code), 0)) + 1)
	arbol.process_frame.connect(vigilar)
	set_meta("crudos", crudos)
	arbol.change_scene_to_file("res://Levels/Lobby.tscn")
	for _i in 15: await arbol.process_frame
	var lb := arbol.current_scene
	var t := 0.0
	while lb._refreshing or lb._rooms_status.text == "":
		await arbol.create_timer(0.25).timeout
		t += 0.25
		if t > 25: break
	var destino := OS.get_environment("SALA")
	if destino == "":
		lb.play_button.pressed.emit()
		var w := 0.0
		while OnlineManager.match_id.is_empty() and w < 30.0:
			await arbol.create_timer(0.25).timeout
			w += 0.25
		var f := FileAccess.open("/tmp/sala_id.txt", FileAccess.WRITE)
		f.store_string(OnlineManager.match_id)
		f.close()
		print(nombre, " SALA_ID=", OnlineManager.match_id.substr(0, 8))
	else:
		var id := FileAccess.get_file_as_string("/tmp/sala_id.txt").strip_edges()
		print(nombre, " ENTRA_A=", id.substr(0, 8))
		lb._entrar(id, "Entrando a la sala...")
	t = 0.0
	while arbol.current_scene == lb and t < 40:
		await arbol.create_timer(0.25).timeout
		t += 0.25
	print(nombre, " ESCENA=", arbol.current_scene.scene_file_path if arbol.current_scene else "null", " tras ", t, "s")
	var jug := arbol.current_scene.find_child("Player1", true, false)
	for i in 120:
		await arbol.create_timer(0.25).timeout
		if jug != null:
			jug.global_position += Vector3(0.15, 0, 0.0)
	var rp := arbol.current_scene.find_children("*", "RemotePlayer", true, false)
	var humanos := rp.filter(func(n): return n.name.begins_with("Remote_"))
	print(nombre, " HUMANOS_VISTOS=", humanos.map(func(n): return n.display_name))
	print(nombre, " RECIBIDOS op70=", ops70, " op60=", ops60, " | remotos=", rp.size(), " humanos=", humanos.size())
	print(nombre, " CRUDOS_DEL_SOCKET=", get_meta("crudos"))
	print(nombre, " EN_SALA=", OnlineManager.is_in_match(), " mi_session=", OnlineManager.get_local_match_session_id().substr(0, 8))
	arbol.quit()
