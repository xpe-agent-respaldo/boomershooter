class_name SfxArmas
extends RefCounted

## Sonidos de armas sintetizados en codigo: no dependen de archivos externos ni de licencias.
## Cada arma tiene un timbre distinto (antes pistola y subfusil compartian el mismo laser y los
## bots disparaban en silencio, asi que en una sala llena no se sabia de donde venia cada tiro).

const RATE := 22050
static var _cache: Dictionary = {}

## kind: "rifle", "escopeta", "subfusil", "pistola", "impacto", "recarga"
static func stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var s := _sintetizar(kind)
	_cache[kind] = s
	return s


static func _sintetizar(kind: String) -> AudioStreamWAV:
	var dur := 0.25
	var grave := 140.0
	var ruido := 0.7
	var caida := 18.0
	match kind:
		"rifle":
			dur = 0.28; grave = 110.0; ruido = 0.75; caida = 16.0
		"escopeta":
			dur = 0.42; grave = 70.0; ruido = 0.95; caida = 9.0
		"subfusil":
			dur = 0.12; grave = 190.0; ruido = 0.6; caida = 34.0
		"pistola":
			dur = 0.18; grave = 150.0; ruido = 0.55; caida = 24.0
		"impacto":
			dur = 0.10; grave = 320.0; ruido = 0.5; caida = 40.0
		"recarga":
			dur = 0.16; grave = 900.0; ruido = 0.15; caida = 30.0
	var n := int(RATE * dur)
	var datos := PackedByteArray()
	datos.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var fase := 0.0
	var filtro := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-caida * t)
		# "pum": tono grave que baja de frecuencia
		var f := grave * (1.0 - 0.55 * (t / dur))
		fase += TAU * f / RATE
		var tono := sin(fase)
		# "chasquido": ruido blanco filtrado
		filtro = filtro * 0.55 + rng.randf_range(-1.0, 1.0) * 0.45
		var muestra := (tono * (1.0 - ruido) + filtro * ruido) * env
		# mordida inicial
		if i < 90:
			muestra += rng.randf_range(-1.0, 1.0) * (1.0 - float(i) / 90.0) * 0.6
		var v := clampi(int(clampf(muestra, -1.0, 1.0) * 30000.0), -32768, 32767)
		datos.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = datos
	return w


## Reproduce un sonido en 3D en la posicion dada y se libera solo.
static func sonar_en(padre: Node, kind: String, pos: Vector3, volumen_db: float = 0.0, alcance: float = 45.0) -> void:
	if padre == null or not is_instance_valid(padre) or not padre.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(kind)
	p.volume_db = volumen_db
	p.max_distance = alcance
	p.unit_size = 6.0
	p.bus = &"SFX"
	padre.get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.pitch_scale = randf_range(0.93, 1.07)
	p.finished.connect(p.queue_free)
	p.play()
