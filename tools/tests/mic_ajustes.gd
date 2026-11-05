extends Node
## Comprueba la pestana de microfono: lista, estado y medidor, sin hardware real (headless).
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	await arbol.process_frame
	var gs = GameSettings
	var lista := AudioServer.get_input_device_list()
	print("MIC dispositivos de entrada detectados: ", lista)
	print("MIC opcion cargada: ", gs._mic_option != null, " | items=", gs._mic_option.item_count if gs._mic_option else -1)
	print("MIC estado visible: '", gs._mic_estado_grande.text if gs._mic_estado_grande else "NULL", "'")
	print("MIC detalle: '", gs._mic_status.text if gs._mic_status else "NULL", "'")
	gs.voice_enabled = true; gs._update_microphone_status()
	print("MIC con voz activada: '", gs._mic_estado_grande.text, "'")
	gs.voice_enabled = false; gs._update_microphone_status()
	print("MIC con voz apagada: '", gs._mic_estado_grande.text, "'")
	# elegir un dispositivo no debe romper nada, ni siquiera con el que no existe
	gs.audio_input_device = "Microfono-que-no-existe"
	gs._aplicar_microfono_guardado()
	print("MIC dispositivo inexistente -> cae a: ", AudioServer.input_device)
	# el medidor en partida no debe vaciar el buffer de la voz
	VoiceManager._match_active = true
	print("MIC nivel en partida (debe ser 0): ", VoiceManager.nivel_microfono())
	arbol.quit()
