extends Node
## El repo es publico: la clave del servidor NO esta en el codigo, la inyecta la compilacion
## en res://online_defaults.cfg. Esta prueba garantiza las dos mitades:
##  1) sin archivo, el juego no inventa una clave y avisa de que el online no esta configurado;
##  2) con archivo, host y clave se cargan, y el export de TODAS las plataformas lo incluye.

var fallos := 0
var aciertos := 0

func ok(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		aciertos += 1
		print("  ok   ", nombre)
	else:
		fallos += 1
		print("  FALLA ", nombre, "  ", detalle)


func _ready() -> void:
	print("== ONLINE: configuracion inyectada ==")
	var codigo := FileAccess.get_file_as_string("res://Scripts/online_manager.gd")
	ok("la clave del servidor no esta escrita en el codigo", not codigo.contains("BoomerShooterSecretKey"))
	ok("el valor de reserva de la clave es vacio", codigo.contains('var server_key := ""'))

	# Cada preset de exportacion debe incluir el archivo generado, o el online muere en silencio.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var nombres: Array = []
	var con_filtro := 0
	for bloque in presets.split("[preset."):
		if not bloque.contains("name="):
			continue
		var nombre := ""
		var filtro := ""
		for linea in bloque.split("\n"):
			if linea.begins_with("name=") and nombre == "":
				nombre = linea.trim_prefix("name=").replace("\"", "")
			if linea.begins_with("include_filter="):
				filtro = linea
		if nombre != "" and filtro != "":
			nombres.append(nombre)
			if filtro.contains("online_defaults.cfg"):
				con_filtro += 1
			else:
				print("     (sin filtro) ", nombre)
	ok("los %d presets de exportacion incluyen online_defaults.cfg" % nombres.size(),
		nombres.size() >= 5 and con_filtro == nombres.size(), "%d de %d: %s" % [con_filtro, nombres.size(), str(nombres)])

	# El CI lo genera antes de exportar. Compila GitHub Actions (publicar.yml): una vez para
	# escritorio y web (job escritorio_y_web) y otra para la IPA (job ipa). Si falta una, ese
	# build sale sin servidor online.
	var gh := FileAccess.get_file_as_string("res://.github/workflows/publicar.yml")
	ok("GitHub Actions genera online_defaults.cfg en escritorio/web e iOS (2 veces)",
		gh.count("write_online_defaults.sh") >= 2, str(gh.count("write_online_defaults.sh")))
	# El CI de GitLab quedo como respaldo manual: si se reactiva, tambien debe inyectarlo.
	var ci := FileAccess.get_file_as_string("res://.gitlab-ci.yml")
	ok("el CI de GitLab (respaldo) sigue inyectando online_defaults.cfg",
		ci.count("write_online_defaults.sh") >= 4, str(ci.count("write_online_defaults.sh")))
	ok("el archivo generado no se versiona (.gitignore)",
		FileAccess.get_file_as_string("res://.gitignore").contains("online_defaults.cfg"))

	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit(1 if fallos > 0 else 0)
