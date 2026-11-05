class_name EnemyState
extends State


var ENEMY: Enemy
var _player_cache: Player
## Siempre el jugador vivo: en online el enemigo puede nacer antes que el jugador local, o
## el jugador reaparecer, y una copia tomada una sola vez se quedaba en Nil para siempre.
var PLAYER: Player:
	get:
		if _player_cache != null and is_instance_valid(_player_cache):
			return _player_cache
		if ENEMY != null and ENEMY.player != null and is_instance_valid(ENEMY.player):
			_player_cache = ENEMY.player
		elif Global.player != null and is_instance_valid(Global.player):
			_player_cache = Global.player
		return _player_cache
	set(value):
		_player_cache = value
var ANIMATION: AnimationPlayer


func _ready() -> void:
	await owner.ready
	ENEMY = owner as Enemy
	PLAYER = ENEMY.player
	ANIMATION = ENEMY.animation_player
