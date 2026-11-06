extends Node

## Base segura de voz de proximidad para partidas Nakama.
##
## El microfono se captura en el bus Voice, que permanece silenciado para evitar
## eco local. Nakama se usa solo como canal de senalizacion: ofertas, respuestas
## y candidatos ICE nunca deben mezclarse con paquetes de jugabilidad.
##
## El audio viaja de verdad: se captura del microfono, se comprime con mu-law a
## 8 kHz mono (160 muestras = 20 ms = 160 bytes por paquete) y se manda por el
## canal de partida de Nakama con el op 92. El servidor es quien filtra: en
## proximidad solo reenvia a los jugadores a menos de 24 m, en equipo solo a los
## companeros y en "todos" a la sala entera. webrtc-native no se usa para el
## audio (no expone pista ni codec); queda solo para senalizacion futura.

signal microphone_state_changed(transmitting: bool)
signal remote_voice_state_changed(session_id: String, speaking: bool)

const Codec := preload("res://Scripts/voice_codec.gd")

const VOICE_BUS := &"Voice"
const MAX_CAPTURE_FRAMES := 960
const PROXIMITY_UNIT_SIZE := 4.0
const PROXIMITY_MAX_DISTANCE := 26.0
const ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
]

var _microphone_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _hud_label: Label
var _match_active := false
var _transmitting := false
var _webrtc_available := false
var _peers: Dictionary = {}
var _remote_players: Dictionary = {}
## Muestras mono a 8 kHz pendientes de empaquetar antes de enviar.
var _pendiente: PackedFloat32Array = PackedFloat32Array()
## Reproductor plano para los canales equipo/todos (no posicional).
var _flat_player: AudioStreamPlayer
var _flat_playback: AudioStreamGeneratorPlayback
## Paquetes recibidos y enviados (diagnostico y HUD).
var _frames_recibidos := 0
var _frames_enviados := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_hud()
	_webrtc_available = ClassDB.class_exists(&"WebRTCLibPeerConnection")
	OnlineManager.voice_signal_received.connect(_on_voice_signal_received)
	OnlineManager.voice_frame_received.connect(_on_voice_frame_received)
	apply_settings()


func _exit_tree() -> void:
	end_match()


func apply_settings() -> void:
	# Voice es un bus de captura: se mantiene silenciado para que el microfono
	# local no vuelva a reproducirse por los altavoces.
	var bus_index := AudioServer.get_bus_index(VOICE_BUS)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, true)
	if GameSettings.voice_enabled:
		_setup_microphone_capture()
	if _microphone_player:
		_microphone_player.volume_db = linear_to_db(maxf(GameSettings.voice_volume, 0.01))
	_preparar_reproduccion_plana()
	_update_microphone_state()


func begin_match() -> void:
	_match_active = true
	_setup_microphone_capture()
	_update_microphone_state()


func end_match() -> void:
	_match_active = false
	_set_transmitting(false)
	for session_id in _peers.keys():
		var peer = _peers[session_id]
		if is_instance_valid(peer):
			peer.close()
	_peers.clear()
	for session_id in _remote_players.keys():
		unregister_remote_player(str(session_id))


func register_remote_player(session_id: String, character: Node3D) -> void:
	if session_id.is_empty() or not is_instance_valid(character):
		return
	unregister_remote_player(session_id)
	var speaker := AudioStreamPlayer3D.new()
	speaker.name = "ProximityVoice"
	speaker.bus = &"Master"
	speaker.unit_size = PROXIMITY_UNIT_SIZE
	speaker.max_distance = PROXIMITY_MAX_DISTANCE
	speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = float(Codec.SAMPLE_RATE)
	stream.buffer_length = 0.25
	speaker.stream = stream
	character.add_child(speaker)
	speaker.play()
	var icon := Label3D.new()
	icon.name = "VoiceIndicator"
	icon.text = "MIC"
	icon.position = Vector3(0, 2.5, 0)
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.modulate = Color(0.35, 1.0, 0.65)
	icon.visible = false
	character.add_child(icon)
	_remote_players[session_id] = {"speaker": speaker, "icon": icon}
	# Solo uno de los dos jugadores inicia la oferta para evitar glare. La otra
	# punta respondera al recibirla mediante la misma Match Data de Nakama.
	var local_session := OnlineManager.get_local_match_session_id()
	if _webrtc_available and not local_session.is_empty() and local_session < session_id:
		request_peer_connection(session_id)


func unregister_remote_player(session_id: String) -> void:
	if not _remote_players.has(session_id):
		return
	var entry: Dictionary = _remote_players[session_id]
	for node_key in ["speaker", "icon"]:
		var node = entry.get(node_key)
		if is_instance_valid(node):
			node.queue_free()
	_remote_players.erase(session_id)


func _process(_delta: float) -> void:
	_update_microphone_state()
	_enviar_captura()
	for peer in _peers.values():
		if is_instance_valid(peer):
			peer.poll()


## En iOS y Android el micro no se puede abrir sin permiso del usuario: sin esta peticion
## el sistema lo bloquea en silencio (o cierra la app). En PC no hace nada.
signal permiso_microfono(concedido: bool)
var _permiso_pedido := false
var microfono_permitido := true


func pedir_permiso_microfono() -> void:
	if _permiso_pedido or not (OS.has_feature("mobile") or OS.get_name() in ["iOS", "Android"]):
		return
	_permiso_pedido = true
	if not get_tree().on_request_permissions_result.is_connected(_on_permiso):
		get_tree().on_request_permissions_result.connect(_on_permiso)
	var concedidos: PackedStringArray = OS.get_granted_permissions()
	if "RECORD_AUDIO" in concedidos or "android.permission.RECORD_AUDIO" in concedidos:
		microfono_permitido = true
		return
	OS.request_permission("RECORD_AUDIO")


func _on_permiso(permiso: String, concedido: bool) -> void:
	if not permiso.contains("RECORD_AUDIO"):
		return
	microfono_permitido = concedido
	permiso_microfono.emit(concedido)
	if not concedido:
		var avisos := get_tree().get_first_node_in_group("team_alerts")
		push_warning("Microfono denegado: el chat de voz queda desactivado.")


func _setup_microphone_capture() -> void:
	if _microphone_player:
		return
	if not GameSettings.voice_enabled:
		return
	pedir_permiso_microfono()
	var bus_index := AudioServer.get_bus_index(VOICE_BUS)
	if bus_index < 0:
		push_warning("No existe el bus Voice. Se desactiva la captura de microfono.")
		return
	var effect = AudioServer.get_bus_effect(bus_index, 0)
	if effect is AudioEffectCapture:
		_capture = effect
	else:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.25
		AudioServer.add_bus_effect(bus_index, _capture, 0)
	if not ClassDB.class_exists(&"AudioStreamMicrophone"):
		push_warning("AudioStreamMicrophone no esta disponible en este build.")
		return
	_microphone_player = AudioStreamPlayer.new()
	_microphone_player.name = "LocalMicrophoneCapture"
	_microphone_player.stream = AudioStreamMicrophone.new()
	_microphone_player.bus = VOICE_BUS
	add_child(_microphone_player)


## Prueba de micro desde Ajustes: abre el micro un momento para que el medidor se mueva.
## No transmite nada a la red; solo captura localmente y se corta al cerrar la pestana.
var _probando := false

func probar_microfono(activo: bool) -> void:
	if activo == _probando:
		return
	_probando = activo
	if activo:
		if _microphone_player == null:
			var bus_index := AudioServer.get_bus_index(VOICE_BUS)
			if bus_index < 0 or not ClassDB.class_exists(&"AudioStreamMicrophone"):
				_probando = false
				return
			_microphone_player = AudioStreamPlayer.new()
			_microphone_player.name = "LocalMicrophoneCapture"
			_microphone_player.stream = AudioStreamMicrophone.new()
			_microphone_player.bus = VOICE_BUS
			add_child(_microphone_player)
		if not _microphone_player.playing:
			_microphone_player.play()
	elif _microphone_player and not _transmitting:
		_microphone_player.stop()


## Nivel actual del micro (0..1), leido del mismo AudioEffectCapture que usa la voz.
## Un bus silenciado no marca picos, pero su captura si recibe el audio.
func nivel_microfono() -> float:
	# Solo en pruebas desde Ajustes: leer el buffer lo vacia, y en partida lo necesita el envio de voz.
	if _capture == null or not _probando or _match_active:
		return 0.0
	var n := mini(_capture.get_frames_available(), 2048)
	if n <= 0:
		return 0.0
	var frames := _capture.get_buffer(n)
	var pico := 0.0
	for f in frames:
		pico = maxf(pico, maxf(absf(f.x), absf(f.y)))
	return clampf(pico * 2.5, 0.0, 1.0)


func _create_hud() -> void:
	_hud_label = Label.new()
	_hud_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud_label.position = Vector2(-220, -54)
	_hud_label.size = Vector2(200, 28)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 4)
	add_child(_hud_label)
	_refresh_hud()


func _update_microphone_state() -> void:
	var allowed := _match_active and GameSettings.voice_enabled
	if allowed and GameSettings.voice_mode == 0:
		allowed = Input.is_action_pressed("push_to_talk")
	_set_transmitting(allowed)


func _set_transmitting(value: bool) -> void:
	if _transmitting == value:
		return
	_transmitting = value
	if _microphone_player:
		if _transmitting:
			_microphone_player.play()
		else:
			_microphone_player.stop()
	_refresh_hud()
	microphone_state_changed.emit(_transmitting)
	if _match_active:
		OnlineManager.send_voice_signal({"kind": "speaking", "speaking": _transmitting})


func _refresh_hud() -> void:
	if _hud_label == null:
		return
	if not GameSettings.voice_enabled:
		_hud_label.text = "MIC: DESACTIVADO"
		_hud_label.modulate = Color(0.65, 0.65, 0.65)
	elif _transmitting:
		_hud_label.text = "MIC: %s  (%d)" % [_nombre_canal(), _frames_enviados]
		_hud_label.modulate = Color(0.35, 1.0, 0.65)
	elif GameSettings.voice_mode == 0:
		_hud_label.text = "MIC: MANTEN V PARA HABLAR"
		_hud_label.modulate = Color(1.0, 0.78, 0.35)
	else:
		_hud_label.text = "MIC: LISTO"
		_hud_label.modulate = Color(1.0, 0.78, 0.35)


## Nombre legible del canal elegido en Ajustes.
func _nombre_canal() -> String:
	match GameSettings.voice_channel:
		1: return "EQUIPO"
		2: return "TODOS"
		_: return "PROXIMIDAD"


## Canal que se manda al servidor segun los ajustes.
func _canal_actual() -> String:
	match GameSettings.voice_channel:
		1: return "team"
		2: return "all"
		_: return "prox"


## Toma lo capturado, lo baja a 8 kHz mono, lo empaqueta en bloques de 20 ms
## y lo manda. Si no estas transmitiendo, se tira: asi el micro no gasta datos.
func _enviar_captura() -> void:
	if _capture == null:
		return
	var disponible := _capture.get_frames_available()
	if disponible > 0:
		var frames := _capture.get_buffer(mini(disponible, MAX_CAPTURE_FRAMES))
		if not _transmitting or not _match_active:
			return
		var bus_hz := 48000.0
		var idx := AudioServer.get_bus_index(VOICE_BUS)
		if idx >= 0:
			bus_hz = maxf(float(AudioServer.get_mix_rate()), 8000.0)
		var mono: PackedFloat32Array = Codec.downsample(frames, bus_hz)
		if not mono.is_empty():
			_pendiente.append_array(mono)
	# se mandan bloques completos de 20 ms
	while _pendiente.size() >= Codec.FRAME_SAMPLES:
		var bloque := _pendiente.slice(0, Codec.FRAME_SAMPLES)
		_pendiente = _pendiente.slice(Codec.FRAME_SAMPLES)
		var comprimido: PackedByteArray = Codec.encode(bloque)
		_frames_enviados += 1
		OnlineManager.send_voice_frame(_canal_actual(), Marshalls.raw_to_base64(comprimido))


## Reproductor no posicional: equipo y "todos" no se atenuan por distancia.
func _preparar_reproduccion_plana() -> void:
	if _flat_player != null and is_instance_valid(_flat_player):
		return
	var generador := AudioStreamGenerator.new()
	generador.mix_rate = float(Codec.SAMPLE_RATE)
	generador.buffer_length = 0.35
	_flat_player = AudioStreamPlayer.new()
	_flat_player.name = "CanalVozPlano"
	_flat_player.stream = generador
	_flat_player.bus = &"Master"
	_flat_player.volume_db = linear_to_db(maxf(GameSettings.voice_volume, 0.01))
	add_child(_flat_player)
	_flat_player.play()
	_flat_playback = _flat_player.get_stream_playback() as AudioStreamGeneratorPlayback


## Llega un paquete de voz del servidor. Si es de proximidad se oye desde el
## personaje (3D, se apaga con la distancia); si es de equipo o de todos, plano.
func _on_voice_frame_received(sender_session_id: String, channel: String, data_b64: String) -> void:
	if sender_session_id.is_empty() or data_b64.is_empty():
		return
	if sender_session_id == OnlineManager.get_local_match_session_id():
		return
	var comprimido := Marshalls.base64_to_raw(data_b64)
	if comprimido.is_empty():
		return
	var muestras: PackedFloat32Array = Codec.decode(comprimido)
	if muestras.is_empty():
		return
	_frames_recibidos += 1
	_set_remote_speaking(sender_session_id, true)
	if channel == "prox":
		var entrada: Dictionary = _remote_players.get(sender_session_id, {})
		var altavoz = entrada.get("speaker")
		if is_instance_valid(altavoz):
			_empujar(altavoz.get_stream_playback() as AudioStreamGeneratorPlayback, muestras)
		return
	_preparar_reproduccion_plana()
	_empujar(_flat_playback, muestras)


## Mete las muestras en el buffer del generador sin pasarse de capacidad.
func _empujar(playback: AudioStreamGeneratorPlayback, muestras: PackedFloat32Array) -> void:
	if playback == null:
		return
	var hueco := playback.get_frames_available()
	if hueco <= 0:
		return
	var n := mini(muestras.size(), hueco)
	for i in n:
		var v := muestras[i]
		playback.push_frame(Vector2(v, v))


func _on_voice_signal_received(sender_session_id: String, payload: Dictionary) -> void:
	if sender_session_id.is_empty() or sender_session_id == OnlineManager.get_local_match_session_id():
		return
	var target := str(payload.get("target", ""))
	var local_session := OnlineManager.get_local_match_session_id()
	if not target.is_empty() and target != local_session:
		return
	match str(payload.get("kind", "")):
		"speaking":
			_set_remote_speaking(sender_session_id, bool(payload.get("speaking", false)))
		"offer", "answer", "candidate":
			_handle_webrtc_signal(sender_session_id, payload)


func _set_remote_speaking(session_id: String, speaking: bool) -> void:
	var entry: Dictionary = _remote_players.get(session_id, {})
	var icon = entry.get("icon")
	if is_instance_valid(icon):
		icon.visible = speaking
	remote_voice_state_changed.emit(session_id, speaking)


func _handle_webrtc_signal(session_id: String, payload: Dictionary) -> void:
	if not _webrtc_available:
		return
	var peer = _peers.get(session_id)
	if peer == null:
		peer = _create_peer(session_id)
	if peer == null:
		return
	match str(payload.get("kind", "")):
		"offer", "answer":
			peer.set_remote_description(str(payload.get("kind")), str(payload.get("sdp", "")))
		"candidate":
			peer.add_ice_candidate(str(payload.get("media", "0")), int(payload.get("index", 0)), str(payload.get("candidate", "")))


func _create_peer(session_id: String):
	var peer = ClassDB.instantiate(&"WebRTCLibPeerConnection")
	if peer == null or peer.initialize({"iceServers": ICE_SERVERS}) != OK:
		return null
	peer.session_description_created.connect(func(description_type: String, sdp: String):
		OnlineManager.send_voice_signal({"kind": description_type, "sdp": sdp, "target": session_id})
	)
	peer.ice_candidate_created.connect(func(media: String, index: int, candidate: String):
		OnlineManager.send_voice_signal({"kind": "candidate", "media": media, "index": index, "candidate": candidate, "target": session_id})
	)
	_peers[session_id] = peer
	return peer


func request_peer_connection(session_id: String) -> bool:
	if not _webrtc_available or session_id.is_empty():
		return false
	var peer = _create_peer(session_id)
	if peer == null:
		return false
	peer.create_data_channel("voice-control")
	return peer.create_offer() == OK
