class_name Attack extends EnemyState


func _ready() -> void:
	super()
	await owner.ready
	ENEMY.chase_player.connect(_on_chase_player)
	ANIMATION.animation_finished.connect(_on_animation_finished)


func enter(_previous_state: State) -> void:
	ANIMATION.play("Hover_Attack1")


func exit() -> void:
	pass


func physics_update(delta: float) -> void:
	# 'speed' esta en unidades por segundo a 60 fps. Antes se multiplicaba por
	# delta y move_and_slide volvia a multiplicar, asi que la velocidad real
	# dependia de los FPS (a 144 se arrastraban, a 30 te alcanzaban siempre).
	var objetivo := PLAYER
	if objetivo == null:
		return
	ENEMY.walk_towards(objetivo.global_position, delta)


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Hover_Attack1":
		ANIMATION.play("Hover_Attack2")
	elif anim_name == "Hover_Attack2":
		ANIMATION.play("Hover_Attack1")


func _on_chase_player() -> void:
	transition.emit("Chase")
