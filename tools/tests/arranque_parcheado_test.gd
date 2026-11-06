extends SceneTree
## Segundo arranque tras instalar un parche (ya en user://patch): PatchLoader lo valida, lo monta
## y el contenido nuevo gana a la base. Se ejecuta sobre la BASE de la IPA (-- main-pack base.pck).
var aciertos := 0
var fallos := 0
func ok(n: String, c: bool, d: String = "") -> void:
	if c: aciertos += 1; print("  ok   ", n)
	else: fallos += 1; print("  FALLA ", n, "  ", d)
func _initialize() -> void:
	_c()
func _c() -> void:
	for i in 4: await process_frame
	var pl = root.get_node("PatchLoader")
	var clase = pl.get_script()
	clase.set("montar_en_editor", true)
	print("== ARRANQUE CON PARCHE INSTALADO ==")
	var antes = ResourceLoader.load("res://Scripts/lobby_music.gd", "", ResourceLoader.CACHE_MODE_IGNORE).get("FUNDIDO")
	pl.montar_parche()
	var despues = ResourceLoader.load("res://Scripts/lobby_music.gd", "", ResourceLoader.CACHE_MODE_IGNORE).get("FUNDIDO")
	ok("PatchLoader monta el parche y declara la version", str(clase.get("mounted_version")) == "1.3.1", "version='%s'" % str(clase.get("mounted_version")))
	ok("el contenido del parche gana a la base (FUNDIDO cambia)", despues != antes, "antes=%s despues=%s" % [antes, despues])
	print("   FUNDIDO antes=", antes, " despues=", despues)
	# Un parche corrupto jamas se monta
	var ruta := ProjectSettings.globalize_path("user://patch/content.pck")
	var f := FileAccess.open(ruta, FileAccess.READ_WRITE); f.seek(100); f.store_8(0xFF); f.close()
	clase.set("mounted_version", "")
	pl.montar_parche()
	ok("un parche corrupto NO se monta (y se borra)", str(clase.get("mounted_version")) == "" and not FileAccess.file_exists("user://patch/content.pck"))
	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	quit(1 if fallos > 0 else 0)
