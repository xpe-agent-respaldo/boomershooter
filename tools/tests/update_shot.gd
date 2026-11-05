extends Node
func _ready() -> void:
	var um = get_node("/root/UpdateManager")
	var modo := "forced" if "--forced" in OS.get_cmdline_user_args() else "optional"
	var m := {"version": "1.1.4", "minimum_version": "1.1.9" if modo == "forced" else "1.0.0", "notes": ["Deteccion de audifonos y selector de salida", "Salas publicas que por fin juntan a los jugadores", "Mapas de arena reconstruidos con colisiones", "Alertas de equipo: H pide ayuda, G marca"], "windows_url": "https://example.invalid/x.exe"}
	um.handle_manifest(m)
	if modo == "optional":
		um._progress.visible = true; um._progress.value = 63.0
		um._set_status("Descargando... 88.4 / 139.1 MB")
	for i in 40: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/update_%s.png" % modo)
	get_tree().quit()
