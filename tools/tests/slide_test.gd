extends Node
## Reproduce el caso del jugador: corre con W + Shift y pulsa C. Mide la velocidad real y si entra en el slide.
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()

func _tecla(accion: String, pulsada: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = accion
	ev.pressed = pulsada
	Input.parse_input_event(ev)

func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file("res://Levels/SpaceArena.tscn")
	await arbol.create_timer(6.0).timeout
	var p: Player = Global.player
	if p == null:
		print("SLIDE: sin jugador"); arbol.quit(1); return
	var maquina = p.get_node("PlayerStateMachine")
	_tecla("move_forward", true)
	_tecla("sprint", true)
	var vmax_sprint := 0.0
	var estados: Array = []
	var ultimo := ""
	var entro := false
	var pulso := false
	for i in 400:
		# W y Shift se refrescan cada frame: asi el sprint no se corta
		_tecla("move_forward", true)
		_tecla("sprint", true)
		await arbol.physics_frame
		var nom := str(maquina.CURRENT_STATE.name)
		if nom != ultimo:
			estados.append(nom); ultimo = nom
		if nom == "SprintingPlayerState":
			var v := Vector2(p.velocity.x, p.velocity.z).length()
			vmax_sprint = maxf(vmax_sprint, v)
			# pulsa C cuando ya va rapido, como un jugador
			if v > 4.5 and not pulso:
				pulso = true
				print("SLIDE: pulso C a velocidad ", snappedf(v, 0.01))
				_tecla("crouch", true)
		if nom == "SlidingPlayerState":
			entro = true
			break
	print("SLIDE: secuencia de estados = ", estados)
	print("SLIDE: velocidad maxima EN SPRINT = ", snappedf(vmax_sprint, 0.01))
	print("SLIDE: pulso C = ", pulso, " | entro al deslizamiento = ", entro)
	arbol.quit(0 if entro else 1)
