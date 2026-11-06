## Hereda de network_game: este script REEMPLAZA al de ArenaBase, y sin la herencia el mapa perderia
## todo el multijugador (jugadores remotos, bots online, su dano y sus disparos).
extends "res://Scripts/network_game.gd"

const VIENTO := preload("res://Assets/Sounds/SFX/Ambience/viento_nieve.wav")


func _ready() -> void:
	super._ready()
	# Musica: la pone MusicDirector (una sola pista por el bus Music). Aqui NO se crea otra,
	# para no repetir el bug de la Arena Espacial (dos musicas a la vez).
	var viento := AudioStreamPlayer.new()
	var s: AudioStreamWAV = VIENTO.duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	viento.stream = s
	viento.bus = &"SFX"
	viento.volume_db = -14.0
	add_child(viento)
	viento.play()
