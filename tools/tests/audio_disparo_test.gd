extends Node
## Dispara en una arena y comprueba que el sonido del arma realmente suena: reproductor activo,
## bus SFX con volumen audible y sin silenciar. Tambien tras entrar en partida con musica.
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()

func _bus(nombre: String) -> String:
	var i := AudioServer.get_bus_index(nombre)
	if i < 0:
		return nombre + "=NO EXISTE"
	return "%s(db=%.1f mute=%s)" % [nombre, AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]

func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	# Camino real del jugador: menu (suena la musica del lobby) -> partida
	arbol.change_scene_to_file("res://Levels/Lobby.tscn")
	await arbol.create_timer(3.0).timeout
	print("AUDIO: en lobby -> ", _bus("Lobby"), " ", _bus("SFX"))
	arbol.change_scene_to_file("res://Levels/SpaceArena.tscn")
	await arbol.create_timer(6.0).timeout
	var p: Player = Global.player
	if p == null:
		print("AUDIO: sin jugador"); arbol.quit(1); return
	print("AUDIO: buses -> ", _bus("Master"), " ", _bus("Music"), " ", _bus("SFX"), " ", _bus("Lobby"))
	var datos = p.WEAPON_DATA
	print("AUDIO: arma equipada = ", datos.weapon_name if datos else "NINGUNA")
	if datos == null:
		arbol.quit(1); return
	var disparos := [0]
	datos.used.connect(func(): disparos[0] += 1)
	var sonaron := 0
	var voces_total := 0
	# mantiene el gatillo 3 s, como un jugador
	Input.action_press("attack")
	var t := 0.0
	while t < 3.0:
		await arbol.physics_frame
		t += get_physics_process_delta_time()
		for w in _buscar_armas(p):
			for v in w._shot_voices:
				if v.playing:
					sonaron += 1
	Input.action_release("attack")
	for w in _buscar_armas(p):
		voces_total += w._shot_voices.size()
	print("AUDIO: disparos (señal used)=", disparos[0], " | voces creadas=", voces_total, " | frames con alguna voz sonando=", sonaron)
	print("AUDIO: municion restante=", datos.ammo, "/", datos.mag)
	print("AUDIO: tras disparar -> ", _bus("Master"), " ", _bus("Music"), " ", _bus("SFX"), " ", _bus("Lobby"))
	var picos := AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("SFX"), 0)
	print("AUDIO: pico del bus SFX = ", snappedf(picos, 0.1), " dB (menos de -60 = silencio)")
	arbol.quit(0 if sonaron > 0 else 1)

func _buscar_armas(raiz: Node) -> Array:
	var r := []
	for c in raiz.get_children():
		if c.get("_shot_voices") != null:
			r.append(c)
		r.append_array(_buscar_armas(c))
	return r
