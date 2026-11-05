extends Node
## Manda perfiles y resultados de partida a Supabase a traves de la web.
## Si no hay red o la web no responde, el juego sigue igual: esto nunca bloquea.

const API := "https://boomershooter.vercel.app/api"
const ESPERA := 6.0

var activo: bool = true
var _cola: Array = []
var _enviando: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(3.0).timeout
	_enviar_perfil()


## La base solo admite windows, linux, web o unknown.
func _plataforma() -> String:
	match OS.get_name():
		"Windows": return "windows"
		"Linux": return "linux"
		"Web": return "web"
		_: return "unknown"


func _nombre() -> String:
	var n := ""
	if OnlineManager != null and not str(OnlineManager.username).is_empty():
		n = str(OnlineManager.username)
	if n.is_empty():
		n = "invitado"
	return n.substr(0, 24)


func _enviar_perfil() -> void:
	_pedir("POST", "/profile", {
		"display_name": _nombre(),
		"platform": _plataforma(),
		"controller_connected": Input.get_connected_joypads().size() > 0,
	})


## Registra en Supabase por que oleada va la partida y en que mapa.
func reportar_partida(mapa: String, oleada: int, jugadores: int = 1) -> void:
	if not activo:
		return
	_pedir("POST", "/matches", {
		"map_id": mapa,
		"wave_reached": oleada,
		"player_count": jugadores,
		"host_user_id": _nombre(),
		"visibility": "public",
		"status": "active",
	})


func _pedir(metodo: String, ruta: String, cuerpo: Dictionary) -> void:
	if not activo:
		return
	var http := HTTPRequest.new()
	http.timeout = ESPERA
	add_child(http)
	var cabeceras := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(API + ruta, cabeceras, HTTPClient.METHOD_POST if metodo == "POST" else HTTPClient.METHOD_GET, JSON.stringify(cuerpo))
	http.request_completed.connect(func(_r: int, codigo: int, _c: PackedStringArray, _b: PackedByteArray) -> void:
		if codigo < 200 or codigo >= 300:
			activo = false  # la web no esta disponible: se deja de insistir
		http.queue_free())
	if err != OK:
		http.queue_free()
