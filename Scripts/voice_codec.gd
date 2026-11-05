extends RefCounted
class_name VoiceCodec

## Codec de voz para el chat de Nakama.
##
## El motor no expone un codificador Opus a GDScript y webrtc-native no entrega
## pista de audio, asi que la voz viaja como PCM comprimido con mu-law (G.711):
## 8 bits por muestra a 8 kHz, 160 muestras por paquete (20 ms) = 8 KB/s por
## hablante. Es el mismo formato que usa la telefonia: inteligible, barato de
## codificar y suficientemente pequeno para el canal de datos de Nakama.

const SAMPLE_RATE := 8000
const FRAME_SAMPLES := 160


## Mezcla a mono y baja de la frecuencia del bus (normalmente 48 kHz) a 8 kHz.
## Se promedian los grupos completos para no meter aliasing fuerte.
static func downsample(frames: PackedVector2Array, origen_hz: float) -> PackedFloat32Array:
	if frames.is_empty():
		return PackedFloat32Array()
	var factor := int(round(maxf(origen_hz, float(SAMPLE_RATE)) / float(SAMPLE_RATE)))
	if factor <= 1:
		var directo := PackedFloat32Array()
		directo.resize(frames.size())
		for i in frames.size():
			directo[i] = (frames[i].x + frames[i].y) * 0.5
		return directo
	var salida := PackedFloat32Array()
	var total := frames.size() / factor
	salida.resize(total)
	for i in total:
		var suma := 0.0
		for j in factor:
			var f := frames[i * factor + j]
			suma += (f.x + f.y) * 0.5
		salida[i] = suma / float(factor)
	return salida


## Comprime muestras [-1, 1] a mu-law de 8 bits (formato telefonico).
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var salida := PackedByteArray()
	salida.resize(samples.size())
	for i in samples.size():
		var s := clampf(samples[i], -1.0, 1.0)
		var signo := 0
		if s < 0.0:
			signo = 0x80
			s = -s
		var escalado := int(round(s * 32767.0))
		if escalado > 32635:
			escalado = 32635
		escalado += 0x84
		var exponente := 7
		var mascara := 0x4000
		while exponente > 0 and (escalado & mascara) == 0:
			exponente -= 1
			mascara >>= 1
		var mantisa := (escalado >> (exponente + 3)) & 0x0F
		salida[i] = (signo | (exponente << 4) | mantisa) ^ 0xFF
	return salida


## Descomprime mu-law a muestras [-1, 1].
static func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	var salida := PackedFloat32Array()
	salida.resize(bytes.size())
	for i in bytes.size():
		var u := (~bytes[i]) & 0xFF
		var signo := u & 0x80
		var exponente := (u >> 4) & 0x07
		var mantisa := u & 0x0F
		var muestra := ((mantisa << 3) + 0x84) << exponente
		muestra -= 0x84
		if signo != 0:
			muestra = -muestra
		salida[i] = clampf(float(muestra) / 32768.0, -1.0, 1.0)
	return salida
