extends SceneTree
# Prueba de la deteccion de audifonos con nombres tipicos de dispositivos.
func _init() -> void:
	var S = load("res://Scripts/game_settings.gd")
	var si = [
		["Auriculares (Realtek High Definition Audio)", true],
		["Headphones (Razer Kraken)", true],
		["Headset Earphone (HyperX Cloud II)", true],
		["Altavoces (Realtek High Definition Audio)", false],
		["Speakers (USB Audio Device)", false],
		["AirPods Pro de Yostin", true],
		["Auriculares Bluetooth (JBL Tune)", true],
		["Default", false],
		["LG HDR 4K (NVIDIA High Definition Audio)", false],
		["Manos libres AG Audio", true],
	]
	var fails := 0
	for c in si:
		var got: bool = S.is_headphone_name(c[0])
		var ok: bool = (got == c[1])
		if not ok: fails += 1
		print(("OK   " if ok else "FALLA"), " ", c[0], " -> ", got)
	print("RESULTADO: %d/%d" % [si.size() - fails, si.size()])
	quit(1 if fails > 0 else 0)
