class_name SprintingPlayerState extends PlayerMovementState

@export var SPEED: float = 6.0
@export var ACCELERATION : float = 0.1
@export var DECELERATION : float = 0.25
@export var TOP_ANIM_SPEED : float = 1.6
@export var WEAPON_BOB_SPD : float = 8.0
@export var WEAPON_BOB_H : float = 2.5
@export var WEAPON_BOB_V : float = 1.5

## Velocidad minima para deslizar y margen (ms) en el que una pulsacion de C sigue valiendo.
const SLIDE_MIN_SPEED := 3.5
const SLIDE_BUFFER_MS := 250
var _slide_pedido_ms: int = -10000


func enter(_previous_state: State) -> void:
	PLAYER.is_sprinting = true
	# Si C ya estaba pulsada al entrar al sprint, cuenta como peticion de slide.
	if Input.is_action_pressed("crouch"):
		_slide_pedido_ms = Time.get_ticks_msec()
	if ANIMATION.is_playing() and ANIMATION.current_animation == "JumpEnd":
		await ANIMATION.animation_finished
		ANIMATION.play("player_animations/Sprinting",0.5,1.0)
	else:
		ANIMATION.play("player_animations/Sprinting",0.5,1.0)

	# ARMS_VIEW.is_walking = true


func exit() -> void:
	PLAYER.is_sprinting = false
	ANIMATION.speed_scale = 1.0
	# ARMS_VIEW.is_walking = false
	# WEAPON.weapon_bob_amount = Vector2(0,0)


func update(delta: float) -> void:
	PLAYER.update_gravity(delta)
	PLAYER.update_input(SPEED,ACCELERATION,DECELERATION)
	PLAYER.update_velocity()

	# WEAPON.sway_weapon(delta, false)
	# WEAPON._weapon_bob(delta, WEAPON_BOB_SPD, WEAPON_BOB_H, WEAPON_BOB_V)

	set_animation_speed(int(PLAYER.velocity.length()))

	if Input.is_action_pressed("attack"):
		if PLAYER.can_fire():
			WEAPON_DATA.use()

	if Input.is_action_just_pressed("reload"):
		WEAPON_DATA.reload()

	if not PLAYER.wants_to_sprint() or PLAYER.velocity.length() == 0:
		transition.emit("IdlePlayerState" if PLAYER.velocity.length() == 0 else "WalkingPlayerState")

	# Slide: C mientras corres. Antes exigia velocidad > 6 en el frame exacto de la pulsacion,
	# asi que pulsar C nada mas arrancar el sprint (velocidad ~4-5) agachaba en vez de deslizar.
	# Ahora basta con ir a ritmo de carrera, y una pulsacion reciente (0.25 s) tambien vale.
	if Input.is_action_just_pressed("crouch"):
		_slide_pedido_ms = Time.get_ticks_msec()
	var rapido: bool = Vector2(PLAYER.velocity.x, PLAYER.velocity.z).length() > SLIDE_MIN_SPEED
	var pedido: bool = Time.get_ticks_msec() - _slide_pedido_ms <= SLIDE_BUFFER_MS
	if pedido and rapido and PLAYER.is_on_floor():
		_slide_pedido_ms = -10000
		transition.emit("SlidingPlayerState")

	if Input.is_action_just_pressed("jump") and PLAYER.is_on_floor():
		transition.emit("JumpingPlayerState")

	if PLAYER.velocity.y < -3.0 and !PLAYER.is_on_floor():
		transition.emit("FallingPlayerState")


func set_animation_speed(spd: int) -> void:
	var alpha: float = remap(spd, 0.0, SPEED, 0.0, 1.0)
	ANIMATION.speed_scale = lerp(0.0, TOP_ANIM_SPEED, alpha)
