class_name Chase extends EnemyState


func _ready() -> void:
	super()
	await owner.ready
	ENEMY.attack_player.connect(_on_attack_player)
	ANIMATION.animation_finished.connect(_on_animation_finished)


func enter(_previous_state: State) -> void:
	ANIMATION.play("Run1")


func exit() -> void:
	pass


func physics_update(delta: float) -> void:
	# 'speed' esta en unidades por segundo a 60 fps. Antes se multiplicaba por
	# delta y move_and_slide volvia a multiplicar, asi que la velocidad real
	# dependia de los FPS (a 144 se arrastraban, a 30 te alcanzaban siempre).
	# En online el jugador local puede no existir un instante (cambio de escena, reaparicion):
	# sin objetivo el enemigo espera en vez de lanzar un error por frame.
	var objetivo := PLAYER
	if objetivo == null:
		return
	ENEMY.walk_towards(objetivo.global_position, delta)


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Run1":
		ANIMATION.play("Run2")
	elif anim_name == "Run2":
		ANIMATION.play("Run1")


func _on_attack_player() -> void:
	transition.emit("Attack")
