extends Node
## Duelo, lado cliente: se activa solo con el modo "duelo", los rivales se pueden disparar, la vida la
## manda el servidor, morir es caer 5 s (nunca "game over") y reaparecer.
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
	_ok(not DuelClient.es_duelo(), "fuera de una sala de duelo el modo esta apagado")
	a.change_scene_to_file("res://Levels/SpaceArena.tscn")
	await a.create_timer(6.0).timeout
	var p: Player = Global.player
	var escena := a.current_scene
	var yo := OnlineManager.get_local_user_id()

	# --- sin duelo: los rivales NO se pueden disparar -------------------------------------------
	var remoto := (load("res://Player/RemotePlayer.tscn") as PackedScene).instantiate()
	escena.add_child(remoto)
	remoto.setup("Beto", Color.RED)
	escena._dar_cuerpo_de_duelo(remoto, "ub")
	_ok(remoto.get_node_or_null("CuerpoDuelo") == null, "en una sala normal el rival NO tiene cuerpo de colision (no se le puede danar)")
	_ok(remoto.is_in_group("remote_player"), "el avatar remoto esta en el grupo remote_player")

	# --- el servidor dice que la sala es un duelo ------------------------------------------------
	OnlineManager.wave_state_received.emit({"mode": "duelo"})
	_ok(DuelClient.es_duelo(), "al decir el servidor mode=duelo, el cliente entra en duelo")
	_ok(DuelClient.visible, "y se muestra su capa de interfaz")
	escena._dar_cuerpo_de_duelo(remoto, "ub")
	var cuerpo := remoto.get_node_or_null("CuerpoDuelo")
	_ok(cuerpo != null, "en duelo el rival SI tiene cuerpo de colision")
	_ok(cuerpo != null and cuerpo.collision_layer == 8, "en la capa 4, la que mira el AimCast")
	escena._dar_cuerpo_de_duelo(remoto, "ub")
	_ok(remoto.get_children().filter(func(n): return n.name == "CuerpoDuelo").size() == 1, "llamarlo dos veces no duplica el cuerpo")

	# --- el arma reconoce al rival ---------------------------------------------------------------
	var arma: Node = p.get_node_or_null("%WeaponManager")
	if arma == null:
		arma = a.get_first_node_in_group("weapon")
	var script_arma := load("res://Scenes/Weapons/weapon.gd")
	_ok(script_arma != null and script_arma.new().has_method("_rival_duelo_from"), "el arma sabe sacar el id del rival al que apuntas")
	var w = script_arma.new()
	_ok(w._rival_duelo_from(cuerpo) == "ub", "dispararle al cuerpo del rival devuelve su user_id")
	_ok(w._rival_duelo_from(null) == "", "dispararle a la nada no devuelve nada")
	_ok(w._rival_duelo_from(escena) == "", "ni a una pared o al mapa")
	w.free()

	# --- la vida la manda el servidor ------------------------------------------------------------
	p.health = Player.MAX_HEALTH
	OnlineManager.duel_event_received.emit({"kind": "hit", "from": "ub", "to": yo, "damage": 30, "hp": 70})
	_ok(p.health == 70, "un golpe del servidor deja la vida en lo que dice el servidor (%d)" % p.health)
	OnlineManager.duel_event_received.emit({"kind": "hit", "from": "ub", "to": "otro-alguien", "damage": 30, "hp": 10})
	_ok(p.health == 70, "un golpe a OTRO jugador no me quita vida a mi")

	# --- morir = caer unos segundos, sin game over ------------------------------------------------
	var murio := [false]
	p.player_died.connect(func(): murio[0] = true)
	OnlineManager.duel_event_received.emit({"kind": "kill", "from": "ub", "to": yo, "killer": "Beto", "victim": "Yo",
		"board": [{"user_id": "ub", "name": "Beto", "kills": 1, "deaths": 0}, {"user_id": yo, "name": "Yo", "kills": 0, "deaths": 1}]})
	await a.process_frame
	_ok(p.en_duelo_caido, "al caer, el jugador queda caido")
	_ok(p.health == 0, "con la vida a 0")
	_ok(not p.visible, "y se oculta")
	_ok(not murio[0], "NO salta la pantalla de Game Over (en el duelo se reaparece)")
	await a.create_timer(0.3).timeout        # la cuenta atras se pinta en _process
	_ok(DuelClient._aviso_caida.visible, "se ve la cuenta atras de reaparicion")
	_ok(DuelClient._aviso_caida.text.contains("REAPARECES"), "con su texto: '%s'" % DuelClient._aviso_caida.text)
	_ok(DuelClient._avisos.get_child_count() == 1, "sale el aviso de la baja")
	_ok(DuelClient._marcador.size() == 2, "y llega el marcador con 2 jugadores")

	# --- reaparecer -------------------------------------------------------------------------------
	var antes := p.global_position
	OnlineManager.duel_event_received.emit({"kind": "respawn", "to": yo, "hp": 100, "board": DuelClient._marcador})
	await a.process_frame
	_ok(not p.en_duelo_caido, "al reaparecer deja de estar caido")
	_ok(p.health == 100, "con la vida llena")
	_ok(p.visible, "y visible otra vez")
	_ok(p.is_physics_processing(), "y se puede mover")
	_ok(not DuelClient._aviso_caida.visible, "desaparece la cuenta atras")
	_ok(p.global_position.is_finite(), "en una posicion valida")

	# --- marcador (Tab) ---------------------------------------------------------------------------
	DuelClient._pintar()
	_ok(DuelClient._lista.get_child_count() >= 4, "el marcador pinta titulo, cabecera y una fila por jugador")

	# --- se apaga al salir del duelo ---------------------------------------------------------------
	OnlineManager.wave_state_received.emit({"mode": "coop_waves"})
	_ok(not DuelClient.es_duelo(), "si la sala deja de ser duelo, se apaga")
	OnlineManager.duel_event_received.emit({"kind": "hit", "from": "ub", "to": yo, "damage": 99, "hp": 1})
	_ok(p.health == 100, "y los eventos de duelo se ignoran fuera del duelo")

	print("\nDUELO CLIENTE: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(1 if fallos else 0)
