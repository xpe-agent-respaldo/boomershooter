extends Area3D

signal exploded

@export var muzzle_velocity: int = 150
@export var g: Vector3 = Vector3.DOWN * 0
@export var lifetime: int = 3

var velocity: Vector3 = Vector3.ZERO
var end_position: Vector3 = Vector3.ZERO
var life_timer: Timer = Timer.new()

func _ready() -> void:
	life_timer.wait_time = lifetime
	life_timer.autostart = true
	life_timer.timeout.connect(_on_lifetimer_timeout)
	add_child(life_timer)
	# if end_position != Vector3.ZERO:
		# velocity = position.direction_to(end_position) * muzzle_velocity
		# look_at_from_position(position, end_position)


func _physics_process(delta: float) -> void:
	velocity += g * delta
	look_at(transform.origin + velocity.normalized(), Vector3.UP)
	# look_at(end_position)
	transform.origin += velocity * delta


func _on_body_entered(_body: Node3D) -> void:
	# El daño lo aplica el hitscan del arma (Scenes/Weapons/weapon.gd). Antes esta
	# bala restaba vida otra vez, asi que cada disparo hacia el doble de daño.
	# El proyectil queda como trazador visual.
	queue_free()

	# emit_signal("exploded", transform.origin)
	# queue_free()


func _on_area_entered(_area: Area3D) -> void:
	pass


func _on_lifetimer_timeout() -> void:
	queue_free()
