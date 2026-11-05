extends Node

## Discord Rich Presence por IPC local, en GDScript puro (sin extension nativa ni DLL).
## Si Discord no esta abierto, no hay Application ID o falla algo, NO pasa nada: el juego sigue igual.
## Protocolo: cada trama = [opcode:int32 LE][largo:int32 LE][json utf-8]. Opcode 0 = handshake, 1 = frame.
## Windows: tuberia \\.\pipe\discord-ipc-0..9, que se abre como un fichero.
## Linux/macOS: socket Unix; Godot no tiene cliente Unix, asi que solo hay presencia en Windows.

## ID de aplicacion del portal de Discord (discord.com/developers/applications). Vacio = desactivado.
const CONFIG_PATH := "res://discord_app_id.txt"
const REINTENTO_S := 10.0          # si Discord se abre despues, en 10 s ya aparece
const FRAMES := ["frame0", "frame1", "frame2", "frame3", "frame2", "frame1"]   # zoom + destello del demonio
const CAMBIO_FRAME_S := 15.0       # Discord no anima GIF; se rota la imagen (el limite es 1 cambio / 5 s)
const MIN_ENTRE_ACTUALIZACIONES_S := 5.0   # Discord limita a 1 cambio cada ~5 s

var app_id: String = ""
var habilitada: bool = true
var _pipe: FileAccess = null
var _conectada: bool = false
var _t_reintento: float = 0.0
var _inicio_s: int = 0
var _estado: Dictionary = {}
var _ultimo_envio_ms: int = 0
var _pendiente: bool = false
var _nonce: int = 0
var _frame: int = 0
var _t_frame: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_inicio_s = int(Time.get_unix_time_from_system())
	app_id = _leer_app_id()
	var ruta_pruebas := OS.get_environment("DISCORD_IPC_PATH")   # solo para tests: apunta a un FIFO
	var soportado := OS.get_name() == "Windows" or ruta_pruebas != ""
	if app_id == "" or not soportado:
		set_process(false)
		return
	menu()


## Orden de busqueda: variable de entorno, archivo junto al .exe (se puede poner sin recompilar),
## archivo en user:// y por ultimo el empaquetado en el juego. Un ID de Discord son 17-20 digitos.
func _leer_app_id() -> String:
	var candidatos: Array = [OS.get_environment("DISCORD_APP_ID")]
	for ruta in [OS.get_executable_path().get_base_dir().path_join("discord_app_id.txt"), "user://discord_app_id.txt", CONFIG_PATH]:
		if FileAccess.file_exists(ruta):
			candidatos.append(FileAccess.get_file_as_string(ruta))
	for c in candidatos:
		var id := str(c).strip_edges()
		if id.length() >= 17 and id.length() <= 20 and id.is_valid_int():
			return id
	print("[Discord] Sin Application ID valido: la presencia queda desactivada. Crea la app en discord.com/developers/applications y pon su ID en discord_app_id.txt")
	return ""


# ---- estados que usa el juego ----

func menu() -> void:
	_poner("En el menu principal", "Preparandose para la caceria", false)


const NOMBRES_MODO := {"coop_waves": "Oleadas", "survival": "Supervivencia", "horde": "Horda",
	"boss_rush": "Jefes", "freestylers": "Matadero"}
const NOMBRES_MAPA := {"recycling_plant": "Planta de Reciclaje", "storm_village": "Distrito de Tormenta",
	"space_arena": "Puesto Lunar"}


## Traduce los ids del servidor a texto para el jugador.
func en_partida_id(mode_id: String, map_id: String, jugadores: int) -> void:
	en_partida(NOMBRES_MODO.get(mode_id, mode_id), NOMBRES_MAPA.get(map_id, map_id), jugadores)


func en_partida(modo: String, mapa: String, jugadores: int, maximo: int = 8) -> void:
	_poner("%s · %s" % [modo, mapa], "Sala de %d/%d" % [jugadores, maximo], true)


func en_lobby(jugadores: int) -> void:
	_poner("En el lobby online", "%d jugador(es) esperando" % jugadores, false)


func _poner(detalle: String, estado: String, con_tiempo: bool) -> void:
	_estado = {
		"details": detalle.substr(0, 128),
		"state": estado.substr(0, 128),
		"assets": {"large_image": FRAMES[_frame], "large_text": "Boomer Shooter", "small_image": "icon", "small_text": "Descarga gratis"},
		"buttons": [{"label": "Descargar el juego", "url": "https://boomershooter.vercel.app"}],
	}
	if con_tiempo:
		_estado["timestamps"] = {"start": _inicio_s}
	_pendiente = true


func _process(delta: float) -> void:
	if not habilitada:
		return
	if not _conectada:
		_t_reintento -= delta
		if _t_reintento <= 0.0:
			_t_reintento = REINTENTO_S
			_conectar()
		return
	_t_frame += delta
	if _t_frame >= CAMBIO_FRAME_S and not _estado.is_empty():
		_t_frame = 0.0
		_frame = (_frame + 1) % FRAMES.size()
		_estado["assets"]["large_image"] = FRAMES[_frame]
		_pendiente = true
	if _pendiente and Time.get_ticks_msec() - _ultimo_envio_ms >= int(MIN_ENTRE_ACTUALIZACIONES_S * 1000.0):
		_enviar_actividad()


func _conectar() -> void:
	var rutas: Array = []
	var prueba := OS.get_environment("DISCORD_IPC_PATH")
	if prueba != "":
		rutas.append(prueba)
	else:
		for i in 10:
			rutas.append("\\\\.\\pipe\\discord-ipc-%d" % i)
	for ruta in rutas:
		var f := FileAccess.open(ruta, FileAccess.READ_WRITE)
		if f != null:
			_pipe = f
			if _handshake():
				_conectada = true
				_pendiente = true
				if _estado.is_empty():
					menu()
				return
			_cerrar()


func _handshake() -> bool:
	if not _escribir(0, {"v": 1, "client_id": app_id}):
		return false
	var resp := _leer()
	return resp.get("evt", "") == "READY"


func _enviar_actividad() -> void:
	_nonce += 1
	var ok := _escribir(1, {
		"cmd": "SET_ACTIVITY",
		"args": {"pid": OS.get_process_id(), "activity": _estado},
		"nonce": str(_nonce),
	})
	_ultimo_envio_ms = Time.get_ticks_msec()
	_pendiente = false
	if not ok:
		_cerrar()
		return
	_leer()   # vacia la respuesta; si Discord se cierra, la proxima escritura falla y se reconecta sola


func _escribir(opcode: int, datos: Dictionary) -> bool:
	if _pipe == null:
		return false
	var cuerpo := JSON.stringify(datos).to_utf8_buffer()
	var trama := PackedByteArray()
	trama.resize(8)
	trama.encode_s32(0, opcode)
	trama.encode_s32(4, cuerpo.size())
	trama.append_array(cuerpo)
	if not _pipe.store_buffer(trama):
		return false
	_pipe.flush()
	return _pipe.get_error() == OK


func _leer() -> Dictionary:
	if _pipe == null:
		return {}
	var cab := _pipe.get_buffer(8)
	if cab.size() < 8:
		return {}
	var largo := cab.decode_s32(4)
	if largo <= 0 or largo > 65536:
		return {}
	var texto := _pipe.get_buffer(largo).get_string_from_utf8()
	var j = JSON.parse_string(texto)
	return j if j is Dictionary else {}


func _cerrar() -> void:
	_pipe = null
	_conectada = false


func _exit_tree() -> void:
	if _conectada:
		_escribir(2, {})   # opcode 2 = cerrar
	_cerrar()
