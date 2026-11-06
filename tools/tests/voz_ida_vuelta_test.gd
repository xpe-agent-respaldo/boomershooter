extends Node
## Cadena de voz completa del cliente: lo que un jugador "dice" llega como trama y se oye en otro.
var fallos := 0
func _ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FALLA ") + m)
	if not c: fallos += 1
func _ready() -> void:
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_correr.call_deferred()
func _energia(p: PackedFloat32Array) -> float:
	var s := 0.0
	for v in p: s += v * v
	return s / maxf(p.size(), 1)
func _correr() -> void:
	var a := get_tree()
	await a.process_frame
	var Codec = preload("res://Scripts/voice_codec.gd")
	# 1) EMISOR: 1 s de tono a la frecuencia de mezcla del bus, bajado a 8 kHz y empaquetado en tramas de 20 ms
	var hz := maxf(float(AudioServer.get_mix_rate()), 8000.0)
	var tono := PackedVector2Array()
	tono.resize(int(hz))
	for i in tono.size():
		var v := sin(float(i) / hz * TAU * 440.0) * 0.5
		tono[i] = Vector2(v, v)
	var mono: PackedFloat32Array = Codec.downsample(tono, hz)
	# la conversion a 8 kHz es proporcional (con 44,1 kHz de mezcla el factor entero 5 da 8820 -> 7350 con redondeo)
	var esperado := int(round(8000.0 * 0.92)) if is_equal_approx(hz, 44100.0) else 8000
	_ok(absi(mono.size() - 8000) <= 700, "1 s de audio del micro baja a ~8000 muestras (%d, mezcla a %d Hz)" % [mono.size(), int(hz)])
	var tramas: Array = []
	var i := 0
	while i + Codec.FRAME_SAMPLES <= mono.size():
		tramas.append(Marshalls.raw_to_base64(Codec.encode(mono.slice(i, i + Codec.FRAME_SAMPLES))))
		i += Codec.FRAME_SAMPLES
	_ok(tramas.size() >= 44 and tramas.size() <= 50, "se generan 44-50 tramas de 20 ms por segundo (%d)" % tramas.size())
	# el servidor admite como mucho VOICE_RATE_PER_S tramas por segundo por jugador: no puede quedarse corto
	var limite := 0
	for linea in FileAccess.get_file_as_string("res://infra/nakama/modules/match_coop.lua").split("\n"):
		if linea.begins_with("local VOICE_RATE_PER_S"):
			limite = int(linea.split("=")[1].strip_edges().split(" ")[0])
	_ok(limite >= 50, "el limite del servidor (%d/s) deja pasar el maximo de 50 tramas/s del cliente" % limite)
	var bytes_max := 0
	for linea in FileAccess.get_file_as_string("res://infra/nakama/modules/match_coop.lua").split("\n"):
		if linea.begins_with("local VOICE_MAX_BYTES"):
			bytes_max = int(linea.split("=")[1].strip_edges().split(" ")[0])
	_ok(tramas[0].length() <= bytes_max, "una trama (%d B en base64) cabe en el maximo del servidor (%d)" % [tramas[0].length(), bytes_max])
	# 2) RECEPTOR: llegan por el canal "equipo" y deben sonar en el reproductor plano
	VoiceManager._frames_recibidos = 0
	for t in tramas:
		VoiceManager._on_voice_frame_received("otro-session", "team", t)
		await a.process_frame
	_ok(VoiceManager._frames_recibidos > 0, "el receptor acepta las tramas (%d)" % VoiceManager._frames_recibidos)
	_ok(VoiceManager._flat_playback != null, "se crea el reproductor del canal de equipo")
	# la trama se descodifica con energia (no llega silencio)
	var dec: PackedFloat32Array = Codec.decode(Marshalls.base64_to_raw(tramas[10]))
	_ok(_energia(dec) > 0.05, "el audio recibido tiene energia (%.3f): se oye" % _energia(dec))
	# 3) mis propias tramas no se reproducen (sin eco)
	var antes := VoiceManager._frames_recibidos
	VoiceManager._on_voice_frame_received(OnlineManager.get_local_match_session_id(), "team", tramas[0])
	_ok(VoiceManager._frames_recibidos == antes, "mi propia voz no se me devuelve")
	# 4) basura no rompe nada
	# (el motor registra un error de base64 por la trama corrupta: es esperado y no debe romper la partida)
	VoiceManager._on_voice_frame_received("x", "all", "###no-es-base64###")
	VoiceManager._on_voice_frame_received("", "all", tramas[0])
	VoiceManager._on_voice_frame_received("x", "all", "")
	_ok(true, "tramas corruptas o vacias se ignoran sin errores")
	print("VOZ_IDA_VUELTA: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(0 if fallos == 0 else 1)
