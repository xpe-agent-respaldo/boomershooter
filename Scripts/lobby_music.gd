extends Node
## Musica del lobby: UN solo reproductor para todos los menus.
##
## Antes cada pantalla (menu principal, lobby) creaba su propio reproductor y elegia una
## pista al azar, asi que al cambiar de interfaz la musica se cortaba y volvia a empezar,
## y ademas MusicDirector ponia otra encima. Ahora vive aqui, sobrevive a los cambios de
## escena y decide sola por la escena activa:
##   - en cualquier menu suena, sin cortarse al pasar de una pantalla a otra;
##   - al entrar a una partida se apaga con un fundido y NO vuelve hasta salir;
##   - tiene su propio bus "Lobby" (volumen aparte de la musica de la partida).

const BUS := &"Lobby"
const VOLUMEN_DB := -6.0
const FUNDIDO := 0.6

## Escenas de menu: aqui suena la musica del lobby. Cualquier otra escena es partida.
## Se identifican por su ARCHIVO, no por el nombre del nodo: "Shop" y "Achievements" tambien son
## nombres de autoloads, y al chocar en root Godot renombra la escena a "@Control@332".
const ESCENAS_MENU := [
	"res://Levels/MainMenu.tscn", "res://Levels/Lobby.tscn", "res://Levels/ArenaSelect.tscn",
	"res://Levels/Shop.tscn", "res://Levels/Achievements.tscn",
]

var _player: AudioStreamPlayer
var _ultima := ""
var _en_menu := false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.volume_db = -80.0
	_player.finished.connect(_siguiente)
	add_child(_player)
	await get_tree().process_frame
	_vigilar()


func _vigilar() -> void:
	while true:
		await get_tree().process_frame
		var escena := get_tree().current_scene
		if escena == null:
			continue
		var menu := es_menu_escena(escena)
		if menu == _en_menu:
			continue
		_en_menu = menu
		if menu:
			_encender()
		else:
			_apagar()


## True si la escena es una pantalla de menu (no una partida).
static func es_menu_escena(escena: Node) -> bool:
	if escena == null:
		return false
	return escena.scene_file_path in ESCENAS_MENU


func _encender() -> void:
	if not _player.playing:
		_siguiente()
	_fundido(VOLUMEN_DB)


func _apagar() -> void:
	_fundido(-80.0, true)


func _siguiente() -> void:
	# El tema acaba solo en menus: en partida no se elige otro.
	if not _en_menu:
		return
	_ultima = LobbyAudio.play_next(_player, _ultima)
	if _player.playing and _player.volume_db <= -79.0:
		_player.volume_db = VOLUMEN_DB


func _fundido(destino_db: float, parar_al_final := false) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", destino_db, FUNDIDO)
	if parar_al_final:
		_tween.tween_callback(func() -> void:
			# Si mientras tanto se volvio a un menu, no se corta.
			if not _en_menu:
				_player.stop())
