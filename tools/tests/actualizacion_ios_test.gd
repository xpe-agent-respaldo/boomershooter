extends SceneTree
## Ciclo completo de actualizacion remota en iPhone (simulado en escritorio):
## manifiesto con patch_ios -> descarga -> hash -> user://patch -> montar -> el juego cambia.
## Uso: godot --headless --script tools/tests/actualizacion_ios_test.gd -- <base.pck> <parche.pck> <puerto>
var aciertos := 0
var fallos := 0
func ok(n: String, c: bool, d: String = "") -> void:
	if c: aciertos += 1; print("  ok   ", n)
	else: fallos += 1; print("  FALLA ", n, "  ", d)

func _initialize() -> void:
	_correr()

func _correr() -> void:
	var a := OS.get_cmdline_user_args()
	var base: String = a[0]; var parche: String = a[1]; var puerto: String = a[2]
	for i in 6: await process_frame
	var um := root.get_node("UpdateManager")
	um.plataforma_simulada = "iOS"
	um.permitir_en_editor = true
	print("== ACTUALIZACION REMOTA EN IPHONE ==")
	var f := FileAccess.open(parche, FileAccess.READ); var bytes := f.get_length(); f.close()
	var man := {"version": "1.3.1", "minimum_version": "1.3.0", "notes": "Prueba",
		"windows_url": "https://x/win.exe", "windows_size": 1, "windows_sha256": "00",
		"patch_ios": {"url": "http://127.0.0.1:%s/content.pck" % puerto, "size": bytes,
			"sha256": FileAccess.get_sha256(parche), "min_base": "1.3.0", "engine_revision": "1", "version": "1.3.1"}}
	um._manifest = man
	ok("iOS ve su parche (patch_ios)", um._patch_available())
	ok("iOS puede autoactualizarse", um.can_self_update())
	ok("iOS NO usa la URL del .exe de Windows", um._platform_url() == "")
	um.plataforma_simulada = "Windows"
	ok("Windows NO ve el parche de iOS", not um._patch_available())
	um.plataforma_simulada = "Linux"
	ok("Linux NO ve el parche de iOS", not um._patch_available())
	um.plataforma_simulada = "iOS"
	# Un parche para otro motor se ignora
	var otro := man.duplicate(true); otro["patch_ios"]["engine_revision"] = "99"; um._manifest = otro
	ok("parche de otro motor se ignora", not um._patch_available())
	# Un parche exigiendo base mas nueva que la instalada se ignora
	var nueva := man.duplicate(true); nueva["patch_ios"]["min_base"] = "9.0.0"; um._manifest = nueva
	ok("parche que exige una base mas nueva se ignora", not um._patch_available())
	um._manifest = man

	# Descarga real por HTTP + verificacion de hash + instalacion del parche
	um._show_update_screen("1.3.1")
	um._start_download()
	var t := 0.0
	while um._installing and t < 30.0:
		await create_timer(0.2).timeout; t += 0.2
		if FileAccess.file_exists("user://patch/content.pck") and FileAccess.file_exists("user://patch/content.json"): break
	await create_timer(1.5).timeout
	print("   [dbg] installing=", um._installing, " estado='", um._status.text if um._status else "?", "' destino=", um._target_path, " existe=", FileAccess.file_exists(um._target_path))
	ok("el parche se descargo e instalo en user://patch", FileAccess.file_exists("user://patch/content.pck"))
	ok("el hash del parche instalado coincide", FileAccess.file_exists("user://patch/content.pck") and FileAccess.get_sha256("user://patch/content.pck") == FileAccess.get_sha256(parche))
	var info = JSON.parse_string(FileAccess.get_file_as_string("user://patch/content.json")) if FileAccess.file_exists("user://patch/content.json") else null
	ok("content.json declara la version nueva", info is Dictionary and str(info.get("version", "")) == "1.3.1")
	ok("el cliente ya se considera en 1.3.1 (no pide actualizar otra vez)", um._current_version() == "1.3.1", um._current_version())
	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	quit(1 if fallos > 0 else 0)
