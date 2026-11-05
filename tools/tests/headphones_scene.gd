extends Node
func _ready() -> void:
	var gs = get_node_or_null("/root/GameSettings")
	print("GameSettings autoload: ", gs != null)
	if gs == null:
		get_tree().quit(2); return
	var casos = [["Auriculares (Realtek High Definition Audio)", true],["Headphones (Razer Kraken)", true],["Headset Earphone (HyperX Cloud II)", true],["Altavoces (Realtek High Definition Audio)", false],["Speakers (USB Audio Device)", false],["AirPods Pro de Yostin", true],["Auriculares Bluetooth (JBL Tune)", true],["Default", false],["LG HDR 4K (NVIDIA High Definition Audio)", false],["Manos libres AG Audio", true]]
	var fallos := 0
	for c in casos:
		var got: bool = gs.is_headphone_name(c[0])
		if got != c[1]: fallos += 1
		print(("OK   " if got == c[1] else "FALLA"), " ", c[0], " -> ", got)
	print("RESULTADO: %d/%d" % [casos.size() - fallos, casos.size()])
	print("Dispositivos de salida vistos por Godot: ", AudioServer.get_output_device_list())
	print("Dispositivo activo: ", AudioServer.output_device, " | audifonos: ", gs.headphones_connected)
	# fuerza un ciclo del sondeo y de la lista para ejercitar el codigo nuevo
	gs._rebuild_device_list(); gs._refresh_audio_devices(); gs._update_device_status()
	print("Sondeo/rebuild sin errores")
	get_tree().quit(1 if fallos > 0 else 0)
