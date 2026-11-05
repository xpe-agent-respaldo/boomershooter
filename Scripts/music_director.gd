extends Node
## Musica por mapa. Escucha los cambios de escena y pone la pista que toca,
## siempre por el bus "Music" para que el control de volumen de Ajustes mande.

const PISTAS := {
	"StormVillage": "res://Assets/Sounds/Music/Maps/aldea_tormenta.wav",
	"SpaceArena": "res://Assets/Sounds/Music/Maps/estacion_lunar.wav",
	"LunarPost": "res://Assets/Sounds/Music/Maps/estacion_lunar.wav",
	"RecyclingPlant": "res://Assets/Sounds/Music/Maps/planta_reciclaje.wav",
	"ArenaSelect": "res://Assets/Sounds/Music/Lobby/musica del lobby 1.mp3",
	"Shop": "res://Assets/Sounds/Music/Lobby/musica del lobby 1.mp3",
	"Achievements": "res://Assets/Sounds/Music/Lobby/musica del lobby 1.mp3",
	"MainMenu": "res://Assets/Sounds/Music/Lobby/musica del lobby 1.mp3",
	"TestLevel": "res://Assets/Sounds/Music/Maps/aldea_tormenta.wav",
}
## El lobby tiene su propio reproductor con lista de temas: no se toca.
const ESCENAS_SIN_DIRECTOR := ["Lobby"]

var _player: AudioStreamPlayer
var _actual: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.volume_db = -80.0
	add_child(_player)
	await get_tree().process_frame
	_watch()


func _watch() -> void:
	while true:
		await get_tree().process_frame
		var escena := get_tree().current_scene
		if escena == null:
			continue
		var nombre := escena.name
		if nombre in ESCENAS_SIN_DIRECTOR:
			_parar()
			continue
		if PISTAS.has(nombre) and _actual != nombre:
			_poner(nombre, PISTAS[nombre])


func _poner(nombre: String, ruta: String) -> void:
	_actual = nombre
	if not ResourceLoader.exists(ruta):
		return
	var stream := load(ruta)
	if stream is AudioStreamWAV:
		# Los tracks generados son cortos: se reproducen en bucle.
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.get_length() * wav.mix_rate
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player.stream = stream
	_player.volume_db = -6.0
	_player.play()


func _parar() -> void:
	if _player.playing:
		_player.stop()
	_actual = ""
