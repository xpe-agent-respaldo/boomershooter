extends Node
## Musica de PARTIDA, por mapa. Escucha los cambios de escena y pone la pista que toca,
## por el bus "Music" (volumen "MUSICA DE PARTIDA" en Ajustes).
## La musica de los menus es de LobbyMusic, con su propio bus y volumen.

const PISTAS := {
	"StormVillage": "res://Assets/Sounds/Music/Maps/aldea_tormenta.wav",
	"SpaceArena": "res://Assets/Sounds/Music/Maps/estacion_lunar.wav",
	"SnowFields": "res://Assets/Sounds/Music/Maps/campos_nieve.wav",
	"RecyclingPlant": "res://Assets/Sounds/Music/Maps/planta_reciclaje.wav",
	"TestLevel": "res://Assets/Sounds/Music/Maps/aldea_tormenta.wav",
}
## Los menus y el lobby los lleva LobbyMusic: aqui solo se calla la musica de partida.
## Por archivo: el nombre del nodo no sirve ("Shop" y "Achievements" son tambien autoloads).
const ESCENAS_SIN_DIRECTOR := [
	"res://Levels/MainMenu.tscn", "res://Levels/Lobby.tscn", "res://Levels/ArenaSelect.tscn",
	"res://Levels/Shop.tscn", "res://Levels/Achievements.tscn",
]

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
		if escena.scene_file_path in ESCENAS_SIN_DIRECTOR:
			_parar()
			continue
		if PISTAS.has(nombre) and _actual != nombre:
			_poner(nombre, PISTAS[nombre])


func _poner(nombre: String, ruta: String) -> void:
	_actual = nombre
	# Si el propio mapa ya tiene su musica sonando por el bus Music (la Arena Espacial pone su pista),
	# el director cede: dos pistas a la vez sonaban como una mezcla.
	var escena := get_tree().current_scene
	if escena != null and _mapa_trae_su_musica(escena):
		_parar_solo_reproductor()
		return
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


## true si algun reproductor del mapa (no el del director) suena ya por el bus Music.
func _mapa_trae_su_musica(nodo: Node) -> bool:
	for h in nodo.find_children("*", "AudioStreamPlayer", true, false):
		var p := h as AudioStreamPlayer
		if p != _player and p.bus == &"Music" and p.stream != null and p.playing:
			return true
	return false


func _parar_solo_reproductor() -> void:
	if _player.playing:
		_player.stop()
