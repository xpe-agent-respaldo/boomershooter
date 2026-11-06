extends SceneTree
## Carga las escenas REALES del juego con el cambio de escena real del motor y comprueba
## musica y chat. Es un SceneTree (no una escena) para sobrevivir a los cambios de escena.
## Uso: godot --headless --script tools/tests/escenas_reales_test.gd
var fallos := 0
var aciertos := 0

func _es_menu(escena: Node) -> bool:
	return root.get_node("LobbyMusic").es_menu_escena(escena)

func ok(n: String, c: bool, d: String = "") -> void:
	if c: aciertos += 1; print("  ok   ", n)
	else: fallos += 1; print("  FALLA ", n, "  ", d)

func _ir(ruta: String) -> void:
	# Cambio de escena REAL: libera la anterior antes de instalar la nueva, como hace el juego.
	change_scene_to_packed(load(ruta) as PackedScene)
	await create_timer(0.7).timeout

func _initialize() -> void:
	_correr()


func _correr() -> void:
	print("== ESCENAS REALES ==")
	for i in 8: await process_frame
	var lm := root.get_node("LobbyMusic")
	var chat := root.get_node("GameChat")
	var p: AudioStreamPlayer = lm._player

	await _ir("res://Levels/MainMenu.tscn")
	ok("MainMenu real: suena el lobby", p.playing)
	ok("MainMenu real: nombre de escena reconocido como menu", _es_menu(current_scene), current_scene.name)
	ok("MainMenu real: ya no crea un reproductor propio", current_scene.get("lobby_music") == null)
	var tema := p.stream
	for ruta in ["res://Levels/Lobby.tscn", "res://Levels/Shop.tscn", "res://Levels/Achievements.tscn", "res://Levels/ArenaSelect.tscn", "res://Levels/MainMenu.tscn"]:
		await _ir(ruta)
		var nom: String = ruta.get_file().get_basename()
		ok("%s real: es menu y la musica sigue (mismo tema)" % nom, _es_menu(current_scene) and p.playing and p.stream == tema, "nodo=" + str(current_scene.name))
		ok("%s real: chat oculto" % nom, not chat._panel.visible)
	for ruta in ["res://Levels/StormVillage.tscn", "res://Levels/SpaceArena.tscn", "res://Levels/RecyclingPlant.tscn"]:
		await _ir(ruta)
		await create_timer(1.0).timeout
		var nom2: String = ruta.get_file().get_basename()
		ok("%s real: NO es menu y la musica del lobby se apaga" % nom2, not _es_menu(current_scene) and not p.playing, "%s playing=%s" % [nom2, p.playing])
		chat.show_system_message("prueba")
		ok("%s real: el chat funciona en partida" % nom2, chat._panel.visible and chat._lines.size() == 1, "lineas=%d" % chat._lines.size())
	await _ir("res://Levels/MainMenu.tscn")
	await create_timer(0.4).timeout
	ok("de vuelta al menu: el lobby suena", p.playing)
	ok("de vuelta al menu: el chat se ve vacio y oculto", not chat._panel.visible and chat._lines.is_empty())

	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	quit(1 if fallos > 0 else 0)
