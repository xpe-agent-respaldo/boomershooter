extends SceneTree
const VoiceCodec := preload("res://Scripts/voice_codec.gd")
func _init():
	# ida y vuelta de una senal conocida
	var seno := PackedFloat32Array()
	seno.resize(160)
	for i in 160:
		seno[i] = sin(float(i) / 160.0 * TAU * 4.0) * 0.6
	var bytes := VoiceCodec.encode(seno)
	var vuelta := VoiceCodec.decode(bytes)
	var error_max := 0.0
	var suma := 0.0
	for i in 160:
		error_max = maxf(error_max, absf(vuelta[i] - seno[i]))
		suma += vuelta[i] * vuelta[i]
	print("bytes: ", bytes.size())
	print("error maximo: ", snappedf(error_max, 0.001))
	print("energia conservada: ", suma > 10.0)
	# silencio
	var silencio := PackedFloat32Array(); silencio.resize(8)
	print("silencio ok: ", VoiceCodec.decode(VoiceCodec.encode(silencio)).size() == 8)
	# downsample 48k -> 8k
	var frames := PackedVector2Array(); frames.resize(960)
	for i in 960: frames[i] = Vector2(0.5, 0.5)
	var mono := VoiceCodec.downsample(frames, 48000.0)
	print("48k->8k muestras: ", mono.size(), " (esperado 160)")
	print("valor conservado: ", snappedf(mono[0], 0.01))
	quit()
