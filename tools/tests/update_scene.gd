extends Node
var fails := 0
func ok(name: String, cond: bool, detail := "") -> void:
	if not cond: fails += 1
	print(("OK    " if cond else "FALLA "), name, " ", detail if not cond else "")
func _ready() -> void:
	var um = get_node_or_null("/root/UpdateManager")
	ok("autoload UpdateManager", um != null)
	if um == null:
		get_tree().quit(2); return
	# versiones
	ok("1.1.4 > 1.1.3", um._version_is_newer("1.1.4", "1.1.3"))
	ok("1.1.3 no > 1.1.3", not um._version_is_newer("1.1.3", "1.1.3"))
	ok("1.2.0 > 1.1.9", um._version_is_newer("1.2.0", "1.1.9"))
	ok("1.1.2 no > 1.1.3", not um._version_is_newer("1.1.2", "1.1.3"))
	# notas
	var n1: PackedStringArray = um.parse_notes(["A", " B ", ""])
	ok("notas lista JSON", n1.size() == 2 and n1[1] == "B", str(n1))
	var n2: PackedStringArray = um.parse_notes("uno; dos;tres\ncuatro")
	ok("notas texto con ; y saltos", n2.size() == 4 and n2[2] == "tres", str(n2))
	# scripts de relevo
	var w: String = um.build_windows_script("C:/Juegos/BoomerShooter.exe", "C:/Users/x/AppData/Roaming/Godot/app_userdata/Boomer Shooter/update/BoomerShooter.new.exe")
	ok("cmd usa barras de Windows", w.contains("C:\\Juegos\\BoomerShooter.exe") and not w.contains("C:/Juegos"))
	ok("cmd reintenta y relanza", w.contains("goto wait") and w.contains("start \"\" \"%CUR%\"") and w.contains("copy /y"))
	ok("cmd tolera espacios en la ruta", w.contains("Boomer Shooter\\update"))
	var u: String = um.build_unix_script("/home/a b/it's/boomershooter.x86_64", "/tmp/x.new")
	ok("sh escapa comillas simples", u.contains("it'\\''s"))
	# manifiesto: con version nueva debe abrir la pantalla y NO bloquear
	um.handle_manifest({"version": "9.9.9", "minimum_version": "0.0.1", "notes": ["Mapas nuevos", "Mejor audio", "Menos lag"], "windows_url": "https://example.invalid/x.exe", "windows_sha256": "abc", "windows_size": 10})
	await get_tree().process_frame
	ok("aviso opcional se muestra", um._layer != null)
	ok("aviso opcional NO bloquea", um.blocks_game == false)
	ok("tiene boton Mas tarde", um._later_button != null)
	um._close_screen()
	ok("Mas tarde cierra el aviso", um._layer == null)
	# manifiesto: version minima superior => obligatorio
	um.handle_manifest({"version": "9.9.9", "minimum_version": "9.0.0", "notes": "Obligatoria", "windows_url": "https://example.invalid/x.exe"})
	await get_tree().process_frame
	ok("aviso obligatorio bloquea", um.blocks_game == true and um._layer != null)
	ok("obligatorio sin Mas tarde", um._later_button == null)
	# en el editor/servidor no se puede autoactualizar -> cae al navegador, no revienta
	ok("can_self_update es false aqui", um.can_self_update() == false)
	print("RESULTADO fallos=", fails)
	get_tree().quit(1 if fails > 0 else 0)
