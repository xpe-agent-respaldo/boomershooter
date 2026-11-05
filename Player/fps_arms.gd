extends Node3D

@export var animation_player: AnimationPlayer

var is_reloading: bool = false
var _reload_token: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_player.animation_finished.connect(func(animation_name: StringName) -> void:
		if animation_name == "ReloadMag":
			_finish_reload()
	)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func ground_impact() -> void:
	animation_player.play("GroundImpact")


func fire() -> void:
	animation_player.play("Fire")


func shake() -> void:
	animation_player.play("Shake")


func reload() -> void:
	is_reloading = true
	_reload_token += 1
	var token: int = _reload_token
	animation_player.play("ReloadMag")
	# Si otra animacion (correr, disparar, idle) interrumpe ReloadMag, la señal
	# animation_finished nunca llega con ese nombre y el arma quedaba bloqueada.
	var length: float = 0.6
	var anim: Animation = animation_player.get_animation("ReloadMag")
	if anim != null:
		length = anim.length / maxf(0.01, animation_player.speed_scale)
	await get_tree().create_timer(length + 0.15).timeout
	if token == _reload_token:
		_finish_reload()


func _finish_reload() -> void:
	is_reloading = false


func walk() -> void:
	animation_player.play("Walk")


func idle() -> void:
	animation_player.play("Idle")
